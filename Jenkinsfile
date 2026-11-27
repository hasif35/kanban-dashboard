
pipeline {
    agent any

    options {
        skipDefaultCheckout(true)
    }

    environment {
        IMAGE_REPO = 'hhasif/kanban-dashboard'
        CONTAINER_NAME = 'kanban-dashboard'
        BACKUP_NAME = 'kanban-dashboard-previous'
        DEPLOY_PORT = '3000'
        CONTAINER_PORT = '8080'
    }

    stages {

        stage('Checkout Source') {
            steps {
                checkout scm

                script {
                    env.GIT_SHA = sh(
                        script: 'git rev-parse --short=7 HEAD',
                        returnStdout: true
                    ).trim()

                    env.IMAGE_TAG = "${BUILD_NUMBER}-${env.GIT_SHA}"

                    echo "Git SHA: ${env.GIT_SHA}"
                    echo "Image Tag: ${env.IMAGE_TAG}"
                }
            }
        }

        stage('Docker Build & Tag') {
            steps {
                sh '''
                    docker build \
                      -t "$IMAGE_REPO:$IMAGE_TAG" \
                      -t "$IMAGE_REPO:latest" .
                '''
            }
        }

        stage('Registry Login & Push') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'dockerhub-creds',
                    usernameVariable: 'DOCKER_USER',
                    passwordVariable: 'DOCKER_PASS'
                )]) {
                    sh '''
                        set +x
                        printf '%s' "$DOCKER_PASS" |
                          docker login -u "$DOCKER_USER" --password-stdin

                        docker push "$IMAGE_REPO:$IMAGE_TAG"
                        docker push "$IMAGE_REPO:latest"

                        docker logout
                    '''
                }
            }
        }

        stage('Deploy to EC2') {
            steps {
                script {
                    env.DEPLOY_ATTEMPTED = 'true'
                }

                sh '''
                    docker rm -f "$BACKUP_NAME" 2>/dev/null || true

                    if docker inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
                        docker stop "$CONTAINER_NAME"
                        docker rename "$CONTAINER_NAME" "$BACKUP_NAME"
                    fi

                    docker run -d \
                      --restart unless-stopped \
                      --name "$CONTAINER_NAME" \
                      -p "$DEPLOY_PORT:$CONTAINER_PORT" \
                      "$IMAGE_REPO:$IMAGE_TAG"
                '''
            }
        }

        stage('Health Check') {
            steps {
                sh '''
                    echo "Checking application health..."

                    for attempt in $(seq 1 30); do
                        if curl -fsS \
                          "http://127.0.0.1:$DEPLOY_PORT/" >/dev/null; then
                            echo "Application health check PASSED"
                            exit 0
                        fi

                        echo "Attempt $attempt: Application not ready"
                        sleep 2
                    done

                    echo "Application health check FAILED"
                    exit 1
                '''
            }
        }

        stage('Finalize Deployment') {
            steps {
                sh '''
                    docker rm -f "$BACKUP_NAME" 2>/dev/null || true
                    echo "Previous container removed."
                '''
            }
        }
    }

    post {
        success {
            echo 'CI/CD Pipeline Successful!'
            echo 'Build, Push, Deployment and Health Check Passed!'
        }

        failure {
            script {
                if (env.DEPLOY_ATTEMPTED == 'true') {
                    echo 'Deployment failed. Attempting rollback...'

                    sh '''
                        docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

                        if docker inspect "$BACKUP_NAME" >/dev/null 2>&1; then
                            docker rename "$BACKUP_NAME" "$CONTAINER_NAME"
                            docker start "$CONTAINER_NAME"
                            echo "Rollback completed."
                        else
                            echo "No previous container available for rollback."
                        fi
                    '''
                }
            }

            echo 'Pipeline Failed!'
        }
    }
}

