// Jenkinsfile for atul's code-pipeline repo
// Requires: Docker on the Jenkins agent. For Docker Hub push, add credentials with ID 'dockerhub-creds'.

pipeline {
  agent any

  options {
    timestamps()
    ansiColor('xterm')
    skipDefaultCheckout(true)
  }

  parameters {
    string(name: 'IMAGE_TAG', defaultValue: 'latest', description: 'Image tag to use for build/push')
    string(name: 'DOCKERHUB_REPO', defaultValue: '', description: 'Docker Hub repo (e.g., atuljkamble/code-pipeline). Leave empty to skip push.')
    booleanParam(name: 'PUSH_TO_DOCKERHUB', defaultValue: false, description: 'Enable to push image to Docker Hub')
  }

  environment {
    IMAGE_LOCAL = "code-pipeline:${params.IMAGE_TAG}"
  }

  stages {
    stage('Checkout') {
      steps {
        script {
          // Works best in Multibranch/SCM Pipeline
          // If using a simple Pipeline job, set the Git repo in the job config
          checkout scm
        }
        sh 'ls -la'
      }
    }

    stage('Build Docker Image') {
      steps {
        sh '''
          echo "Building ${IMAGE_LOCAL}..."
          docker build -t "${IMAGE_LOCAL}" .
          echo "Image built:"
          docker images | head -n 5
        '''
      }
    }

    stage('Test Container Output') {
      steps {
        sh '''
          echo "Running container test..."
          # Expecting "Hello World" from helloworld.py
          OUT=$(docker run --rm "${IMAGE_LOCAL}")
          echo "Container output: $OUT"
          echo "$OUT" | grep -q "Hello World"
        '''
      }
    }

    stage('Push to Docker Hub') {
      when {
        allOf {
          expression { return params.PUSH_TO_DOCKERHUB }
          expression { return params.DOCKERHUB_REPO?.trim() }
        }
      }
      steps {
        withCredentials([usernamePassword(credentialsId: 'dockerhub-creds',
                                          usernameVariable: 'DH_USER',
                                          passwordVariable: 'DH_PASS')]) {
          sh '''
            echo "Tagging image for Docker Hub..."
            docker tag "${IMAGE_LOCAL}" "${DOCKERHUB_REPO}:${IMAGE_TAG}"

            echo "Logging in to Docker Hub..."
            echo "$DH_PASS" | docker login -u "$DH_USER" --password-stdin

            echo "Pushing ${DOCKERHUB_REPO}:${IMAGE_TAG}..."
            docker push "${DOCKERHUB_REPO}:${IMAGE_TAG}"

            echo "Logout..."
            docker logout || true
          '''
        }
      }
    }
  }

  post {
    always {
      sh '''
        echo "Cleaning up dangling images (if any)..."
        docker image prune -f || true
      '''
    }
  }
}
