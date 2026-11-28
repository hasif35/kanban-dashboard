
pipeline {

    agent any

    options {
        skipDefaultCheckout(true)
    }

    environment {
        IMAGE_REPO = 'hhasif/kanban-dashboard'

        PROXY_NAME = 'kanban-proxy'
        DOCKER_NETWORK = 'kanban-net'
        NGINX_CONF = '/opt/kanban/kanban-nginx.conf'

        DEPLOY_PORT = '3000'
        CONTAINER_PORT = '8080'

        DEPLOY_ATTEMPTED = 'false'
        ACTIVE_COLOR = ''
        TARGET_COLOR = ''
        ACTIVE_NAME = ''
        TARGET_NAME = ''
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

        stage('Identify Active Environment') {
            steps {
                script {
                    env.ACTIVE_COLOR = sh(
                        script: '''
                            if grep -q \
                              'proxy_pass http://kanban-blue:8080' \
                              "$NGINX_CONF"; then
                                echo blue
                            elif grep -q \
                              'proxy_pass http://kanban-green:8080' \
                              "$NGINX_CONF"; then
                                echo green
                            else
                                echo unknown
                            fi
                        ''',
                        returnStdout: true
                    ).trim()

                    if (env.ACTIVE_COLOR == 'unknown') {
                        error('Cannot identify active Blue-Green environment.')
                    }

                    env.TARGET_COLOR =
                        env.ACTIVE_COLOR == 'blue' ? 'green' : 'blue'

                    env.ACTIVE_NAME = "kanban-${env.ACTIVE_COLOR}"
                    env.TARGET_NAME = "kanban-${env.TARGET_COLOR}"

                    echo "Active: ${env.ACTIVE_NAME}"
                    echo "New deployment target: ${env.TARGET_NAME}"

                    env.DEPLOY_ATTEMPTED = 'true'
                }
            }
        }

        stage('Deploy Inactive Environment') {
            steps {
                sh '''
                    set -eu

                    echo "===== DEPLOYING NEW ENVIRONMENT ====="

                    docker network inspect "$DOCKER_NETWORK" >/dev/null

                    docker inspect "$PROXY_NAME" >/dev/null

                    # Remove an old inactive container if present
                    docker rm -f "$TARGET_NAME" 2>/dev/null || true

                    # Start new application without host port mapping
                    docker run -d \
                      --restart unless-stopped \
                      --name "$TARGET_NAME" \
                      --network "$DOCKER_NETWORK" \
                      --memory=250m \
                      --memory-reservation=125m \
                      --memory-swap=250m \
                      --cpus=0.25 \
                      "$IMAGE_REPO:$IMAGE_TAG"

                    echo "New container started: $TARGET_NAME"
                '''
            }
        }

        stage('New Container Health Check') {
            steps {
                sh '''
                    set -eu

                    echo "===== CHECK 1: CONTAINER RUNNING ====="

                    docker ps \
                      --filter "name=^${TARGET_NAME}$" \
                      --filter "status=running" \
                      --format '{{.Names}}' |
                      grep -qx "$TARGET_NAME"

                    echo "Container is running."

                    echo "===== CHECK 2: DOCKER HEALTH ====="

                    HEALTH_STATUS=""

                    for attempt in $(seq 1 30); do

                        HEALTH_STATUS=$(docker inspect \
                          --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' \
                          "$TARGET_NAME")

                        if [ "$HEALTH_STATUS" = "healthy" ]; then
                            break
                        fi

                        if [ "$HEALTH_STATUS" = "unhealthy" ] ||
                           [ "$HEALTH_STATUS" = "no-healthcheck" ]; then
                            echo "Container health validation failed."
                            exit 1
                        fi

                        echo "Waiting for health: $attempt/30"
                        sleep 2
                    done

                    if [ "$HEALTH_STATUS" != "healthy" ]; then
                        echo "Health check timed out."
                        exit 1
                    fi

                    echo "Docker health: healthy"

                    echo "===== CHECK 3: DIRECT APPLICATION TEST ====="

                    docker exec "$TARGET_NAME" \
                      wget -qO- "http://127.0.0.1:${CONTAINER_PORT}/" \
                      >/dev/null

                    echo "New application responds successfully."
                '''
            }
        }

        stage('Switch Traffic to New Environment') {
            steps {
                sh '''
                    set -eu

                    echo "===== SWITCHING NGINX TRAFFIC ====="

                    # Update the existing bind-mounted file in place.
                    # Do not replace it using mv.
                    cat > "$NGINX_CONF" <<EOF
server {
    listen 80;

    location / {
        proxy_pass http://${TARGET_NAME}:${CONTAINER_PORT};
        proxy_set_header Host \\$host;
        proxy_set_header X-Real-IP \\$remote_addr;
        proxy_set_header X-Forwarded-For \\$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \\$scheme;
    }
}
EOF

                    # Validate configuration before reload
                    docker exec "$PROXY_NAME" nginx -t

                    # Apply new backend
                    docker exec "$PROXY_NAME" nginx -s reload

                    echo "Nginx switched to $TARGET_NAME"
                '''
            }
        }

        stage('Production Validation') {
            steps {
                sh '''
                    set -eu

                    echo "===== CHECKING PRODUCTION ENDPOINT ====="

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

                        echo "Waiting for HTTP 200: $attempt/15"
                        sleep 2
                    done

                    if [ "$HTTP_STATUS" != "200" ]; then
                        echo "Production validation failed."
                        exit 1
                    fi

                    echo "Production HTTP status: 200"

                    echo "===== ACTIVE BACKEND ====="
                    grep 'proxy_pass' "$NGINX_CONF"

                    echo "BLUE-GREEN DEPLOYMENT SUCCESSFUL!"
                '''
            }
        }
    }

    post {

        success {
            echo 'Blue-Green deployment successful!'

            sh '''
                echo "Removing previous application container..."

                # Remove old environment only after production validation
                docker rm -f "$ACTIVE_NAME" 2>/dev/null || true

                echo "Previous environment cleaned up."
                echo "Active environment: $TARGET_NAME"
            '''
        }

        failure {
            script {
                if (env.DEPLOY_ATTEMPTED == 'true' &&
                    env.ACTIVE_NAME &&
                    env.TARGET_NAME) {

                    echo 'Deployment failed. Restoring previous environment.'

                    sh '''
                        set +e

                        echo "===== FAILURE DIAGNOSTICS ====="

                        docker ps -a

                        docker logs --tail 100 "$TARGET_NAME" 2>&1

                        echo "===== RESTORING PREVIOUS TRAFFIC ====="

                        # Restore previous backend configuration
                        if docker inspect "$ACTIVE_NAME" >/dev/null 2>&1; then

                            cat > "$NGINX_CONF" <<EOF
server {
    listen 80;

    location / {
        proxy_pass http://${ACTIVE_NAME}:${CONTAINER_PORT};
        proxy_set_header Host \\$host;
        proxy_set_header X-Real-IP \\$remote_addr;
        proxy_set_header X-Forwarded-For \\$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \\$scheme;
    }
}
EOF

                            if docker exec "$PROXY_NAME" nginx -t; then
                                docker exec "$PROXY_NAME" nginx -s reload
                                echo "Previous traffic configuration restored."
                            else
                                echo "WARNING: Nginx configuration validation failed."
                            fi

                            # Keep previous application running
                            docker start "$ACTIVE_NAME" 2>/dev/null || true

                            # Verify previous application through proxy
                            for attempt in $(seq 1 15); do

                                if curl -fsS \
                                  "http://127.0.0.1:${DEPLOY_PORT}/" \
                                  >/dev/null; then

                                    echo "ROLLBACK SUCCESSFUL!"
                                    break
                                fi

                                sleep 2
                            done

                        else
                            echo "ERROR: Previous environment is unavailable."
                        fi

                        # Remove failed candidate only after restoring traffic
                        docker rm -f "$TARGET_NAME" 2>/dev/null || true

                        echo "Rollback procedure completed."
                    '''
                }
            }

            echo 'Pipeline failed. Check diagnostics above.'
        }
    }
}

