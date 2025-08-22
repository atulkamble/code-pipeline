# 🚀 Code Pipeline – Hello World

**Basic AWS CodePipeline + CodeBuild project** using Python and Docker.  
It builds a Docker image that runs a simple **Hello World** Python script.

---

## 📂 Project Structure

```

.
├── helloworld.py    # Python script that prints "Hello World"
├── Dockerfile       # Docker image definition
├── buildspec.yml    # AWS CodeBuild build instructions
├── README.md        # Project documentation
└── LICENSE

````

---

## 🐍 Python Script

`helloworld.py`:
```python
print("Hello World")
````

---

## 🐳 Dockerfile

```dockerfile
FROM python:latest
WORKDIR /usr/app/src
COPY helloworld.py ./
CMD ["python", "./helloworld.py"]
```

Build and run locally:

```bash
docker build -t helloworld .
docker run --rm helloworld
```

---

## 🔧 buildspec.yml

The buildspec defines build steps for **AWS CodeBuild**:

```yaml
version: 0.2

phases:
  install:
    runtime-versions:
      python: 3.9
    commands:
      - echo "Installing dependencies..."
      - pip install --upgrade pip
  build:
    commands:
      - echo "Building Docker image..."
      - docker build -t helloworld:latest .
  post_build:
    commands:
      - echo "Running container..."
      - docker run --rm helloworld:latest

artifacts:
  files:
    - '**/*'
```

---

## 🚀 Run Locally

```bash
# Clone repo
git clone https://github.com/atulkamble/code-pipeline.git
cd code-pipeline

# Build and run with Docker
docker build -t helloworld .
docker run --rm helloworld
```

Output:

```
Hello World
```

---

## ☁️ Deploy with AWS CodePipeline

1. Create an **S3 bucket** for pipeline artifacts.
2. Create a **CodeBuild project** pointing to this repo.
3. Add this repo as the **source stage** in **AWS CodePipeline**.
4. Connect CodeBuild with the provided `buildspec.yml`.
5. Trigger the pipeline → It will build the Docker image and run the script.
6. Delete ECR Public Repo.

---
