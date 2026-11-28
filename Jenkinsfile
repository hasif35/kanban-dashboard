
pipeline {

    agent any

    options {
        skipDefaultCheckout(true)
        disableConcurrentBuilds()
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

        // 1. CHECKOUT SOURCE

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

        // 2. DOCKER BUILD AND TAG

        stage('Docker Build & Tag') {
            steps {
                sh '''
                    set -eu

                    docker build \
                      -t "$IMAGE_REPO:$IMAGE_TAG" \
                      -t "$IMAGE_REPO:latest" .
                '''
            }
        }

        // 3. REGISTRY LOGIN AND PUSH

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

        // 4. IDENTIFY ACTIVE ENVIRONMENT

        stage('Identify Active Environment') {
            steps {
                script {

                    def active = sh(
                        script: '''
                            set -eu

                            if grep -q 'proxy_pass http://kanban-blue:8080' "$NGINX_CONF"; then
                                echo blue

                            elif grep -q 'proxy_pass http://kanban-green:8080' "$NGINX_CONF"; then
                                echo green

                            else
                                echo unknown
                            fi
                        ''',
                        returnStdout: true
                    ).trim()

                    if (!(active in ['blue', 'green'])) {
                        error("Cannot identify active environment: ${active}")
                    }

                    // Assign Jenkins environment variables

                    env.ACTIVE_COLOR = active

                    env.TARGET_COLOR =
                        active == 'blue' ? 'green' : 'blue'

                    env.ACTIVE_NAME = "kanban-${env.ACTIVE_COLOR}"

                    env.TARGET_NAME = "kanban-${env.TARGET_COLOR}"

                    env.DEPLOY_ATTEMPTED = 'true'

                    echo "===== ENVIRONMENT IDENTIFICATION ====="

                    echo "Active environment: ${env.ACTIVE_COLOR}"
                    echo "Active container: ${env.ACTIVE_NAME}"

                    echo "New deployment target: ${env.TARGET_COLOR}"
                    echo "Target container: ${env.TARGET_NAME}"
                }
            }
        }

        // 5. DEPLOY INACTIVE ENVIRONMENT

        stage('Deploy Inactive Environment') {
            steps {
                sh '''
                    set -eu

                    echo "===== DEPLOYING NEW ENVIRONMENT ====="

                    # Verify Docker network

                    docker network inspect "$DOCKER_NETWORK" >/dev/null

                    # Verify Nginx proxy

                    docker inspect "$PROXY_NAME" >/dev/null

                    # Verify image exists locally

                    docker image inspect "$IMAGE_REPO:$IMAGE_TAG" >/dev/null

                    # Remove previous inactive container if present

                    docker rm -f "$TARGET_NAME" 2>/dev/null || true

                    # Deploy new application container

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

        // 6. NEW CONTAINER HEALTH CHECK

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

        // 7. SWITCH NGINX TRAFFIC

        stage('Switch Traffic to New Environment') {
            steps {
                sh '''
                    set -eu

                    echo "===== SWITCHING NGINX TRAFFIC ====="

                    # Update existing Nginx configuration

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

                    # Validate configuration

                    docker exec "$PROXY_NAME" nginx -t

                    # Reload Nginx

                    docker exec "$PROXY_NAME" nginx -s reload

                    echo "Nginx switched to $TARGET_NAME"
                '''
            }
        }

        // 8. PRODUCTION VALIDATION

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

    // 9. POST ACTIONS

    post {

        success {
            echo 'Blue-Green deployment successful!'

            sh '''
                echo "===== DEPLOYMENT SUMMARY ====="

                echo "Previous environment: $ACTIVE_NAME"
                echo "New active environment: $TARGET_NAME"

                echo "Previous container retained for rollback."

                docker ps \
                  --filter "name=kanban-" \
                  --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

                echo "Deployment completed successfully."
            '''
        }

        failure {
            script {

                if (env.DEPLOY_ATTEMPTED == 'true' &&
                    env.ACTIVE_NAME &&
                    env.TARGET_NAME) {

                    echo 'Deployment failed. Starting automatic rollback.'

                    sh '''
                        set +e

                        echo "===== FAILURE DIAGNOSTICS ====="

                        docker ps -a

                        if docker inspect "$TARGET_NAME" >/dev/null 2>&1; then
                            docker logs --tail 100 "$TARGET_NAME" 2>&1
                        fi

                        echo "===== RESTORING PREVIOUS ENVIRONMENT ====="

                        if docker inspect "$ACTIVE_NAME" >/dev/null 2>&1; then

                            # Ensure previous application is running

                            docker start "$ACTIVE_NAME" 2>/dev/null || true

                            # Restore previous Nginx configuration

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

                            # Validate and reload previous configuration

                            if docker exec "$PROXY_NAME" nginx -t; then

                                docker exec "$PROXY_NAME" nginx -s reload

                                echo "Previous traffic configuration restored."

                                # Validate rollback

                                ROLLBACK_STATUS=""

                                for attempt in $(seq 1 15); do

                                    ROLLBACK_STATUS=$(curl -sS \
                                      -o /dev/null \
                                      -w '%{http_code}' \
                                      --max-time 5 \
                                      "http://127.0.0.1:${DEPLOY_PORT}/" || true)

                                    if [ "$ROLLBACK_STATUS" = "200" ]; then
                                        break
                                    fi

                                    sleep 2
                                done

                                if [ "$ROLLBACK_STATUS" = "200" ]; then
                                    echo "ROLLBACK SUCCESSFUL!"
                                else
                                    echo "WARNING: Rollback validation failed."
                                fi

                            else
                                echo "ERROR: Nginx configuration validation failed."
                            fi

                        else
                            echo "ERROR: Previous environment is unavailable."
                        fi

                        # Remove failed candidate only after rollback attempt

                        docker rm -f "$TARGET_NAME" 2>/dev/null || true

                        echo "===== ROLLBACK PROCEDURE FINISHED ====="
                    '''
                }

                echo 'Pipeline failed. Check diagnostics above.'
            }
        }

        always {
            echo 'Pipeline execution finished.'
        }
    }
}

