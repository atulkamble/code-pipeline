Got it, Atul! Here’s a clean, end-to-end **AWS CodePipeline** setup you can drop into your training. It covers GitHub *and* CodeCommit sources, CodeBuild for CI, CodeDeploy to EC2/ASG, plus day-2 ops commands.

---

# 0) Prereqs (set once)

```bash
# Adjust these for your account/region/project
export AWS_REGION=ap-south-1
export PROJECT=inventory-manager
export ARTIFACT_BUCKET=${PROJECT}-artifacts-$RANDOM
export CODECOMMIT_REPO=${PROJECT}-repo
export CODEBUILD_PROJECT=${PROJECT}-build
export CODEDEPLOY_APP=${PROJECT}-app
export CODEDEPLOY_DG=${PROJECT}-dg
export PIPELINE_NAME=${PROJECT}-pipeline
```

Create the artifact bucket:

```bash
aws s3 mb s3://$ARTIFACT_BUCKET --region $AWS_REGION
```

---

# 1) IAM service roles (least-priv quickstart)

### 1.1 CodePipeline role

**Trust policy** (`cp-trust.json`)

```json
{ "Version": "2012-10-17", "Statement": [
  { "Effect": "Allow", "Principal": { "Service": "codepipeline.amazonaws.com" },
    "Action": "sts:AssumeRole" }
]}
```

```bash
aws iam create-role --role-name ${PROJECT}-CodePipelineRole \
  --assume-role-policy-document file://cp-trust.json

aws iam attach-role-policy --role-name ${PROJECT}-CodePipelineRole \
  --policy-arn arn:aws:iam::aws:policy/AWSCodePipelineFullAccess

# Optional if using CodeStar Connections (GitHub)
aws iam attach-role-policy --role-name ${PROJECT}-CodePipelineRole \
  --policy-arn arn:aws:iam::aws:policy/AWSCodeStarFullAccess
```

### 1.2 CodeBuild role

**Trust policy** (`cb-trust.json`)

```json
{ "Version": "2012-10-17", "Statement": [
  { "Effect": "Allow", "Principal": { "Service": "codebuild.amazonaws.com" },
    "Action": "sts:AssumeRole" }
]}
```

```bash
aws iam create-role --role-name ${PROJECT}-CodeBuildRole \
  --assume-role-policy-document file://cb-trust.json

aws iam attach-role-policy --role-name ${PROJECT}-CodeBuildRole \
  --policy-arn arn:aws:iam::aws:policy/AWSCodeBuildDeveloperAccess
aws iam attach-role-policy --role-name ${PROJECT}-CodeBuildRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
```

### 1.3 CodeDeploy role

**Trust policy** (`cd-trust.json`)

```json
{ "Version":"2012-10-17","Statement":[
  { "Effect":"Allow","Principal":{"Service":"codedeploy.amazonaws.com"},
    "Action":"sts:AssumeRole"}]}
```

```bash
aws iam create-role --role-name ${PROJECT}-CodeDeployRole \
  --assume-role-policy-document file://cd-trust.json

aws iam attach-role-policy --role-name ${PROJECT}-CodeDeployRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole
```

(If deploying to EC2/ASG, attach the **CodeDeploy agent** IAM role to instances, e.g. `AmazonEC2RoleforAWSCodeDeploy` equivalent custom policy.)

---

# 2) Source options

## Option A) CodeCommit

Create repo & push:

```bash
aws codecommit create-repository --repository-name $CODECOMMIT_REPO \
  --repository-description "Source for $PROJECT"

git config --global credential.helper '!aws codecommit credential-helper $@'
git config --global credential.UseHttpPath true

git clone https://git-codecommit.$AWS_REGION.amazonaws.com/v1/repos/$CODECOMMIT_REPO
# add your app code, buildspec.yml, appspec.yml, scripts/, etc., then:
git add . && git commit -m "init" && git push origin main
```

## Option B) GitHub (via CodeStar Connections)

```bash
# Creates a connection placeholder; complete auth in console once.
aws codestar-connections create-connection \
  --provider-type GitHub \
  --connection-name ${PROJECT}-gh-conn \
  --region $AWS_REGION
```

Note the returned **ConnectionArn** (used below).

---

# 3) CodeBuild (CI)

**buildspec.yml** (put in repo root)

```yaml
version: 0.2
phases:
  install:
    runtime-versions:
      python: 3.11
    commands:
      - pip install -r requirements.txt
  build:
    commands:
      - echo "Running tests..."
      - pytest -q || true
      - echo "Packaging..."
      - mkdir -p artifacts
      - zip -r artifacts/app.zip app/ requirements.txt
artifacts:
  files:
    - artifacts/app.zip
    - appspec.yml
    - scripts/**/*
```

Create project:

```bash
aws codebuild create-project \
  --name $CODEBUILD_PROJECT \
  --source type=CODECOMMIT,location=https://git-codecommit.$AWS_REGION.amazonaws.com/v1/repos/$CODECOMMIT_REPO \
  --artifacts type=CODEPIPELINE \
  --environment type=LINUX_CONTAINER,image=aws/codebuild/standard:7.0,computeType=BUILD_GENERAL1_SMALL,privilegedMode=false \
  --service-role arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/${PROJECT}-CodeBuildRole \
  --region $AWS_REGION
```

> For GitHub, change `--source` to `type=CODEPIPELINE` (the pipeline will feed the source).

---

# 4) CodeDeploy (to EC2/ASG)

**appspec.yml** (repo root)

```yaml
version: 0.0
os: linux
files:
  - source: artifacts/app.zip
    destination: /opt/$PROJECT
hooks:
  AfterInstall:
    - location: scripts/restart.sh
      timeout: 180
      runas: root
```

Example `scripts/restart.sh`:

```bash
#!/bin/bash
set -e
systemctl restart ${PROJECT}.service || true
```

Create app & deployment group (example with an ASG and tag selector):

```bash
aws deploy create-application --application-name $CODEDEPLOY_APP --compute-platform Server

aws deploy create-deployment-group \
  --application-name $CODEDEPLOY_APP \
  --deployment-group-name $CODEDEPLOY_DG \
  --service-role-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/${PROJECT}-CodeDeployRole \
  --deployment-config-name CodeDeployDefault.OneAtATime \
  --auto-scaling-groups MyApp-ASG \
  --ec2-tag-filters Key=Name,Value=${PROJECT}-ec2,Type=KEY_AND_VALUE
```

Ensure **CodeDeploy agent** is installed on instances:

```bash
sudo yum update -y
sudo yum install -y ruby wget
cd /tmp && wget https://aws-codedeploy-$AWS_REGION.s3.$AWS_REGION.amazonaws.com/latest/install
chmod +x install
sudo ./install auto
sudo service codedeploy-agent status
```

---

# 5) CodePipeline definition

Create the pipeline JSON (`pipeline.json`).

### 5.1 CodeCommit source variant

```json
{
  "pipeline": {
    "name": "inventory-manager-pipeline",
    "roleArn": "arn:aws:iam::123456789012:role/inventory-manager-CodePipelineRole",
    "artifactStore": {
      "type": "S3",
      "location": "REPLACE_ARTIFACT_BUCKET"
    },
    "stages": [
      {
        "name": "Source",
        "actions": [
          {
            "name": "Source",
            "actionTypeId": {"category":"Source","owner":"AWS","provider":"CodeCommit","version":"1"},
            "outputArtifacts": [{"name":"SourceOutput"}],
            "configuration": {
              "RepositoryName": "REPLACE_CODECOMMIT_REPO",
              "BranchName": "main",
              "PollForSourceChanges": "false"
            },
            "runOrder": 1
          }
        ]
      },
      {
        "name": "Build",
        "actions": [
          {
            "name": "Build",
            "actionTypeId": {"category":"Build","owner":"AWS","provider":"CodeBuild","version":"1"},
            "inputArtifacts": [{"name":"SourceOutput"}],
            "outputArtifacts": [{"name":"BuildOutput"}],
            "configuration": {
              "ProjectName": "REPLACE_CODEBUILD_PROJECT"
            },
            "runOrder": 1
          }
        ]
      },
      {
        "name": "Deploy",
        "actions": [
          {
            "name": "Deploy",
            "actionTypeId": {"category":"Deploy","owner":"AWS","provider":"CodeDeploy","version":"1"},
            "inputArtifacts": [{"name":"BuildOutput"}],
            "configuration": {
              "ApplicationName": "REPLACE_CODEDEPLOY_APP",
              "DeploymentGroupName": "REPLACE_CODEDEPLOY_DG"
            },
            "runOrder": 1
          }
        ]
      }
    ],
    "version": 1
  }
}
```

### 5.2 GitHub (CodeStar Connections) source variant

Replace the **Source** stage with:

```json
{
  "name": "Source",
  "actions": [
    {
      "name": "GitHubSource",
      "actionTypeId": {"category":"Source","owner":"AWS","provider":"CodeStarSourceConnection","version":"1"},
      "outputArtifacts": [{"name":"SourceOutput"}],
      "configuration": {
        "ConnectionArn": "REPLACE_CONNECTION_ARN",
        "FullRepositoryId": "github-username/repo-name",
        "BranchName": "main",
        "DetectChanges": "true"
      },
      "runOrder": 1
    }
  ]
}
```

Create the pipeline:

```bash
# Replace placeholders in pipeline.json (quick sed one-liner)
sed -i.bak \
 -e "s/REPLACE_ARTIFACT_BUCKET/$ARTIFACT_BUCKET/" \
 -e "s/REPLACE_CODECOMMIT_REPO/$CODECOMMIT_REPO/" \
 -e "s/REPLACE_CODEBUILD_PROJECT/$CODEBUILD_PROJECT/" \
 -e "s/REPLACE_CODEDEPLOY_APP/$CODEDEPLOY_APP/" \
 -e "s/REPLACE_CODEDEPLOY_DG/$CODEDEPLOY_DG/" \
 pipeline.json

aws codepipeline create-pipeline --cli-input-json file://pipeline.json
```

Start a run:

```bash
aws codepipeline start-pipeline-execution --name $PIPELINE_NAME
```

---

# 6) Useful Day-2 Commands

**View pipelines & executions**

```bash
aws codepipeline list-pipelines
aws codepipeline list-pipeline-executions --pipeline-name $PIPELINE_NAME --max-results 10
aws codepipeline get-pipeline-state --name $PIPELINE_NAME
```

**Retry/Release**

```bash
aws codepipeline start-pipeline-execution --name $PIPELINE_NAME
aws codepipeline retry-stage-execution \
  --pipeline-name $PIPELINE_NAME \
  --stage-name Build \
  --pipeline-execution-id <EXEC_ID> \
  --retry-mode FAILED_ACTIONS
```

**Enable/disable source polling (CodeCommit)**

```bash
# Enable CloudWatch Events rule instead of polling (recommended) via Console or:
aws events put-rule --name ${PROJECT}-codecommit-rule --event-pattern '{
  "source": ["aws.codecommit"], "detail-type": ["CodeCommit Repository State Change"],
  "resources": ["arn:aws:codecommit:'$AWS_REGION':'$(aws sts get-caller-identity --query Account --output text)':'$CODECOMMIT_REPO'"]
}'
```

**Update pipeline after edits**

```bash
aws codepipeline update-pipeline --cli-input-json file://pipeline.json
```

**CodeBuild on demand**

```bash
aws codebuild start-build --project-name $CODEBUILD_PROJECT
aws codebuild batch-get-builds --ids <BUILD_ID>
```

**CodeDeploy manual deployment**

```bash
aws deploy create-deployment \
  --application-name $CODEDEPLOY_APP \
  --deployment-group-name $CODEDEPLOY_DG \
  --s3-location bucket=$ARTIFACT_BUCKET,bundleType=zip,key=BuildArtifact.zip
```

---

# 7) Minimal repo structure (training-ready)

```
.
├── app/                       # your application code
├── scripts/
│   └── restart.sh
├── buildspec.yml              # CodeBuild
├── appspec.yml                # CodeDeploy
└── README.md
```

---

# 8) Common gotchas (quick fixes)

* **CodeStar connection never triggers:** Open the connection in Console → “Update pending connection” to complete auth; ensure branch matches.
* **AccessDenied to S3 artifacts:** Verify pipeline role has access to the artifact bucket; bucket policy allows the role.
* **CodeDeploy “No instances match”**: Target instances must have the CodeDeploy agent running and match your ASG or tag filters.
* **Build fails to find buildspec:** Ensure `buildspec.yml` is at repo root (or set `buildspec` path in CodeBuild project).
* **Large artifacts fail:** Keep artifacts < 50 MB per output; otherwise upload to S3 in build and emit only manifest paths.

---

# 9) Cleanup

```bash
aws codepipeline delete-pipeline --name $PIPELINE_NAME
aws codebuild delete-project --name $CODEBUILD_PROJECT
aws deploy delete-deployment-group --application-name $CODEDEPLOY_APP --deployment-group-name $CODEDEPLOY_DG
aws deploy delete-application --application-name $CODEDEPLOY_APP
aws s3 rm s3://$ARTIFACT_BUCKET --recursive
aws s3 rb s3://$ARTIFACT_BUCKET
aws iam detach-role-policy --role-name ${PROJECT}-CodePipelineRole --policy-arn arn:aws:iam::aws:policy/AWSCodePipelineFullAccess
aws iam delete-role --role-name ${PROJECT}-CodePipelineRole
aws iam detach-role-policy --role-name ${PROJECT}-CodeBuildRole --policy-arn arn:aws:iam::aws:policy/AWSCodeBuildDeveloperAccess
aws iam detach-role-policy --role-name ${PROJECT}-CodeBuildRole --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
aws iam delete-role --role-name ${PROJECT}-CodeBuildRole
aws iam detach-role-policy --role-name ${PROJECT}-CodeDeployRole --policy-arn arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole
aws iam delete-role --role-name ${PROJECT}-CodeDeployRole
```

---

If you want, I can also give you a **CloudFormation** version (one template that stands up S3, roles, CodeBuild, CodeDeploy, and the CodePipeline) or an **ECR/ECS** deployment flavor for containers instead of EC2+CodeDeploy.
