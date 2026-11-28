
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
        DEPLOY_ATTEMPTED = 'false'
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
                        trap 'docker logout >/dev/null 2>&1 || true' EXIT

                        printf '%s' "$DOCKER_PASS" |
                          docker login -u "$DOCKER_USER" --password-stdin

                        docker push "$IMAGE_REPO:$IMAGE_TAG"
                        docker push "$IMAGE_REPO:latest"
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
                    echo "Preparing deployment..."

                    # Remove any older backup
                    docker rm -f "$BACKUP_NAME" 2>/dev/null || true

                    # Preserve existing working container
                    if docker inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
                        docker stop "$CONTAINER_NAME"
                        docker rename "$CONTAINER_NAME" "$BACKUP_NAME"

                        echo "Previous container backed up."
                    fi

                    # Deploy new version
                    docker run -d \
                      --restart unless-stopped \
                      --name "$CONTAINER_NAME" \
                      --memory=250m \
                      --memory-reservation=125m \
                      --memory-swap=250m \
                      --cpus=0.25 \
                      -p "$DEPLOY_PORT:$CONTAINER_PORT" \
                      "$IMAGE_REPO:$IMAGE_TAG"

                    echo "New container deployed with resource limits."
                '''
            }
        }

        stage('Health Check & Validation') {
            steps {
                sh '''
                    set -eu

                    echo "===== CHECK 1: CONTAINER RUNNING ====="

                    if ! docker ps \
                        --filter "name=^${CONTAINER_NAME}$" \
                        --filter "status=running" \
                        --format '{{.Names}}' |
                        grep -qx "$CONTAINER_NAME"; then

                        echo "FAILED: Container is not running."
                        exit 1
                    fi

                    echo "PASSED: Container is running."

                    echo "===== CHECK 2: DOCKER HEALTHCHECK ====="

                    HEALTH_STATUS=""

                    for attempt in $(seq 1 30); do

                        HEALTH_STATUS=$(docker inspect \
                            --format='{{.State.Health.Status}}' \
                            "$CONTAINER_NAME" 2>/dev/null || true)

                        if [ "$HEALTH_STATUS" = "healthy" ]; then
                            break
                        fi

                        if [ "$HEALTH_STATUS" = "unhealthy" ]; then
                            echo "FAILED: Container is unhealthy."
                            exit 1
                        fi

                        echo "Waiting for Docker health... $attempt/30"
                        sleep 2
                    done

                    if [ "$HEALTH_STATUS" != "healthy" ]; then
                        echo "FAILED: Docker health check timed out."
                        exit 1
                    fi

                    echo "PASSED: Docker health status is healthy."

                    echo "===== CHECK 3: APPLICATION HTTP RESPONSE ====="

                    HTTP_STATUS=""

                    for attempt in $(seq 1 15); do

                        HTTP_STATUS=$(curl -sS \
                            -o /dev/null \
                            -w '%{http_code}' \
                            --max-time 5 \
                            "http://127.0.0.1:${DEPLOY_PORT}/" || true)

                        if [ "$HTTP_STATUS" = "200" ]; then
                            break
                        fi

                        echo "Waiting for HTTP 200... $attempt/15"
                        sleep 2
                    done

                    if [ "$HTTP_STATUS" != "200" ]; then
                        echo "FAILED: Application did not return HTTP 200."
                        exit 1
                    fi

                    echo "PASSED: Application returned HTTP 200."

                    echo "===================================="
                    echo "ALL HEALTH CHECKS PASSED!"
                    echo "DEPLOYMENT VALIDATION SUCCESSFUL!"
                    echo "===================================="
                '''
            }
        }
    }

    post {

        success {
            echo 'CI/CD Pipeline Successful!'
            echo 'Build, Push, Deployment and All Health Checks Passed!'

            sh '''
                # Remove old container only after successful validation
                docker rm -f "$BACKUP_NAME" 2>/dev/null || true

                echo "Previous backup cleaned up."
                echo "Deployment completed successfully."
            '''
        }

        failure {
            script {
                if (env.DEPLOY_ATTEMPTED == 'true') {

                    echo 'DEPLOYMENT FAILED!'
                    echo 'Starting automatic rollback...'

                    sh '''
                        # Remove failed new container
                        docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

                        # Restore previous working container
                        if docker inspect "$BACKUP_NAME" >/dev/null 2>&1; then

                            docker rename "$BACKUP_NAME" "$CONTAINER_NAME"
                            docker start "$CONTAINER_NAME"

                            echo "Previous container restored."

                            # Verify restored application
                            for attempt in $(seq 1 15); do

                                if curl -fsS \
                                    "http://127.0.0.1:${DEPLOY_PORT}/" >/dev/null; then

                                    echo "ROLLBACK SUCCESSFUL!"
                                    echo "Previous application is responding."
                                    exit 0
                                fi

                                sleep 2
                            done

                            echo "WARNING: Restored application failed HTTP validation."
                            exit 1

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

