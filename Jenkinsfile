
pipeline {
    agent any

    options {
        skipDefaultCheckout(true)
        disableConcurrentBuilds()
        timestamps()
    }

    environment {
        IMAGE_REPO = 'hhasif/kanban-dashboard'
        PROXY_NAME = 'kanban-proxy'
        DOCKER_NETWORK = 'kanban-net'
        NGINX_CONF = '/opt/kanban/kanban-nginx.conf'
        DEPLOY_PORT = '3000'
        CONTAINER_PORT = '8080'
    }

    stages {

        // ==========================================
        // 1. CHECKOUT SOURCE CODE
        // ==========================================

        stage('Checkout Source') {
            steps {
                checkout scm

                script {
                    def gitSha = sh(
                        script: 'git rev-parse --short=7 HEAD',
                        returnStdout: true
                    ).trim()

                    def imageTag = "${BUILD_NUMBER}-${gitSha}"

                    writeFile(
                        file: '.build-meta',
                        text: "GIT_SHA=${gitSha}\nIMAGE_TAG=${imageTag}\n"
                    )

                    echo "Git SHA: ${gitSha}"
                    echo "Image Tag: ${imageTag}"
                }
            }
        }

        // ==========================================
        // 2. DOCKER BUILD
        // ==========================================

        stage('Docker Build & Tag') {
            steps {
                sh '''
                    set -eu
                    . ./.build-meta

                    echo "===== DOCKER BUILD ====="

                    docker build \
                      -t "$IMAGE_REPO:$IMAGE_TAG" \
                      -t "$IMAGE_REPO:latest" .

                    echo "Docker image built successfully."
                    docker images "$IMAGE_REPO"
                '''
            }
        }

        // ==========================================
        // 3. DOCKER HUB LOGIN AND PUSH
        // ==========================================

        stage('Registry Login & Push') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'dockerhub-creds',
                        usernameVariable: 'DOCKER_USER',
                        passwordVariable: 'DOCKER_PASS'
                    )
                ]) {
                    sh '''
                        set -eu
                        . ./.build-meta

                        echo "===== DOCKER HUB LOGIN ====="

                        set +x

                        trap 'docker logout >/dev/null 2>&1 || true' EXIT

                        printf '%s' "$DOCKER_PASS" |
                          docker login \
                            -u "$DOCKER_USER" \
                            --password-stdin

                        echo "===== PUSHING VERSIONED IMAGE ====="

                        docker push "$IMAGE_REPO:$IMAGE_TAG"

                        echo "===== PUSHING LATEST IMAGE ====="

                        docker push "$IMAGE_REPO:latest"

                        echo "Docker Hub push completed."
                    '''
                }
            }
        }

        // ==========================================
        // 4. IDENTIFY ACTIVE BLUE/GREEN ENVIRONMENT
        // ==========================================

        stage('Identify Active Environment') {
            steps {
                script {
                    echo "===== IDENTIFYING ACTIVE ENVIRONMENT ====="

                    def detectedColor = sh(
                        script: '''
                            set -eu

                            if grep -Fq \
                              'proxy_pass http://kanban-blue:8080' \
                              "$NGINX_CONF"; then
                                echo blue

                            elif grep -Fq \
                              'proxy_pass http://kanban-green:8080' \
                              "$NGINX_CONF"; then
                                echo green

                            else
                                echo unknown
                            fi
                        ''',
                        returnStdout: true
                    ).trim()

                    echo "Detected active color: [${detectedColor}]"

                    if (!(detectedColor in ['blue', 'green'])) {
                        error('Unable to identify active Blue-Green environment. Deployment stopped.')
                    }

                    def targetColor =
                        detectedColor == 'blue' ? 'green' : 'blue'

                    def activeName = "kanban-${detectedColor}"
                    def targetName = "kanban-${targetColor}"

                    // Persist state in workspace.
                    // Later stages read this file directly.

                    writeFile(
                        file: '.bg-state',
                        text: """ACTIVE_COLOR=${detectedColor}
TARGET_COLOR=${targetColor}
ACTIVE_NAME=${activeName}
TARGET_NAME=${targetName}
DEPLOY_ATTEMPTED=true
"""
                    )

                    echo "Active color: ${detectedColor}"
                    echo "Active container: ${activeName}"
                    echo "Target color: ${targetColor}"
                    echo "Target container: ${targetName}"

                    echo "Deployment state saved successfully."
                }
            }
        }

        // ==========================================
        // 5. DEPLOY TO INACTIVE ENVIRONMENT
        // ==========================================

        stage('Deploy Inactive Environment') {
            steps {
                sh '''
                    set -eu

                    . ./.bg-state
                    . ./.build-meta

                    echo "===== DEPLOYING NEW ENVIRONMENT ====="

                    echo "Active container: $ACTIVE_NAME"
                    echo "Target container: $TARGET_NAME"
                    echo "Image: $IMAGE_REPO:$IMAGE_TAG"

                    docker network inspect "$DOCKER_NETWORK" >/dev/null

                    docker inspect "$PROXY_NAME" >/dev/null

                    # Verify that the existing production container
                    # is still available before deployment.

                    docker inspect "$ACTIVE_NAME" >/dev/null

                    # Remove only the old inactive candidate.

                    docker rm -f "$TARGET_NAME" 2>/dev/null || true

                    # Start the new application container.

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

                    docker ps -a \
                      --filter "name=^${TARGET_NAME}$"
                '''
            }
        }

        // ==========================================
        // 6. NEW CONTAINER HEALTH CHECK
        // ==========================================

        stage('New Container Health Check') {
            steps {
                sh '''
                    set -eu

                    . ./.bg-state

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

                        echo "Health status: $HEALTH_STATUS ($attempt/30)"

                        if [ "$HEALTH_STATUS" = "healthy" ]; then
                            break
                        fi

                        if [ "$HEALTH_STATUS" = "unhealthy" ] ||
                           [ "$HEALTH_STATUS" = "no-healthcheck" ]; then
                            echo "Container health validation failed."
                            exit 1
                        fi

                        sleep 2
                    done

                    if [ "$HEALTH_STATUS" != "healthy" ]; then
                        echo "Health check timed out."
                        exit 1
                    fi

                    echo "Docker health: healthy"

                    echo "===== CHECK 3: DIRECT APPLICATION TEST ====="

                    docker exec "$TARGET_NAME" \
                      wget -qO- \
                      "http://127.0.0.1:${CONTAINER_PORT}/" \
                      >/dev/null

                    echo "Application responds successfully."
                '''
            }
        }

        // ==========================================
        // 7. SWITCH NGINX TRAFFIC
        // ==========================================

        stage('Switch Traffic to New Environment') {
            steps {
                sh '''
                    set -eu

                    . ./.bg-state

                    echo "===== SWITCHING NGINX TRAFFIC ====="

                    # Update existing Nginx configuration file.
                    # Keep the file path unchanged because it is
                    # bind-mounted into the proxy container.

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

                    echo "===== VALIDATING NGINX CONFIGURATION ====="

                    docker exec "$PROXY_NAME" nginx -t

                    echo "===== RELOADING NGINX ====="

                    docker exec "$PROXY_NAME" nginx -s reload

                    echo "Traffic switched to: $TARGET_NAME"
                '''
            }
        }

        // ==========================================
        // 8. PRODUCTION VALIDATION
        // ==========================================

        stage('Production Validation') {
            steps {
                sh '''
                    set -eu

                    . ./.bg-state

                    echo "===== PRODUCTION VALIDATION ====="

                    HTTP_STATUS=""

                    for attempt in $(seq 1 15); do

                        HTTP_STATUS=$(curl -sS \
                          -o /dev/null \
                          -w '%{http_code}' \
                          --max-time 5 \
                          "http://127.0.0.1:${DEPLOY_PORT}/" || true)

                        echo "HTTP status: $HTTP_STATUS ($attempt/15)"

                        if [ "$HTTP_STATUS" = "200" ]; then
                            break
                        fi

                        sleep 2
                    done

                    if [ "$HTTP_STATUS" != "200" ]; then
                        echo "Production validation failed."
                        exit 1
                    fi

                    echo "Production HTTP status: 200"

                    echo "===== ACTIVE BACKEND ====="

                    grep 'proxy_pass' "$NGINX_CONF"

                    echo "===== ACTIVE CONTAINER ====="

                    docker ps \
                      --filter "name=^${TARGET_NAME}$"

                    echo "BLUE-GREEN DEPLOYMENT SUCCESSFUL!"
                '''
            }
        }
    }

    // ==========================================
    // POST ACTIONS
    // ==========================================

    post {

        success {
            sh '''
                set -eu

                echo "===== DEPLOYMENT SUCCESSFUL ====="

                if [ -f .bg-state ]; then
                    . ./.bg-state

                    echo "New active container: $TARGET_NAME"
                    echo "Previous container: $ACTIVE_NAME"

                    # Remove previous environment only after
                    # successful production validation.

                    docker rm -f "$ACTIVE_NAME" 2>/dev/null || true

                    echo "Previous environment cleanup completed."
                fi
            '''

            echo 'Blue-Green deployment completed successfully!'
        }

        failure {
            sh '''
                set +e

                echo "===== FAILURE DIAGNOSTICS ====="

                docker ps -a

                if [ -f .bg-state ]; then

                    . ./.bg-state

                    echo "Failed target: $TARGET_NAME"
                    echo "Previous active: $ACTIVE_NAME"

                    if [ "$DEPLOY_ATTEMPTED" = "true" ]; then

                        echo "===== RESTORING PREVIOUS ENVIRONMENT ====="

                        if docker inspect "$ACTIVE_NAME" >/dev/null 2>&1; then

                            # Ensure previous application is running.

                            docker start "$ACTIVE_NAME" >/dev/null 2>&1

                            # Restore previous Nginx backend.

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

                                ROLLBACK_OK=false

                                for attempt in $(seq 1 15); do

                                    if curl -fsS \
                                      --max-time 5 \
                                      "http://127.0.0.1:${DEPLOY_PORT}/" \
                                      >/dev/null; then

                                        echo "ROLLBACK SUCCESSFUL!"
                                        ROLLBACK_OK=true
                                        break
                                    fi

                                    echo "Waiting for rollback validation: $attempt/15"
                                    sleep 2
                                done

                                # Remove failed candidate only after
                                # successful rollback validation.

                                if [ "$ROLLBACK_OK" = "true" ]; then
                                    docker rm -f "$TARGET_NAME" 2>/dev/null || true
                                else
                                    echo "WARNING: Rollback validation failed."
                                    echo "Both containers are being preserved for investigation."
                                fi

                            else
                                echo "WARNING: Restored Nginx configuration is invalid."
                                echo "Containers are being preserved."
                            fi

                        else
                            echo "ERROR: Previous environment is unavailable."
                            echo "Manual recovery may be required."
                        fi
                    fi

                else
                    echo "No deployment state file found."
                    echo "Failure occurred before deployment state was saved."
                fi

                echo "===== CONTAINER LOGS ====="

                if [ -f .bg-state ]; then
                    . ./.bg-state
                    docker logs --tail 100 "$TARGET_NAME" 2>&1
                fi

                echo "===== ROLLBACK PROCEDURE FINISHED ====="
            '''

            echo 'Pipeline failed. Check diagnostics above.'
        }

        always {
            echo '===== PIPELINE EXECUTION FINISHED ====='
        }
    }
}

