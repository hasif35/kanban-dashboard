pipeline {
    agent any

    environment {
        IMAGE_NAME = "hhasif/kanban-dashboard"
    }

    stages {

        stage('Checkout') {
            steps {
                git branch: 'main',
                    url: 'https://github.com/hasif35/kanban-dashboard.git'
            }
        }

        stage('Build Docker Image') {
            steps {
                sh """
                    docker build \
                    -t ${IMAGE_NAME}:${BUILD_NUMBER} \
                    -t ${IMAGE_NAME}:latest .
                """
            }
        }

        stage('Docker Login') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'dockerhub-creds',
                        usernameVariable: 'DOCKER_USER',
                        passwordVariable: 'DOCKER_PASS'
                    )
                ]) {
                    sh '''
                        echo "USER=$DOCKER_USER"
                        echo "$DOCKER_PASS" | docker login \
                        -u "$DOCKER_USER" \
                        --password-stdin
                    '''
                }
            }
        }

        stage('Push Image') {
            steps {
                sh """
                    docker push ${IMAGE_NAME}:${BUILD_NUMBER}
                    docker push ${IMAGE_NAME}:latest
                """
            }
        }

        stage('Deploy Container') {
            steps {
                sh """
                    docker rm -f kanban-dashboard || true

                    docker run -d \
                    --name kanban-dashboard \
                    -p 3000:80 \
                    ${IMAGE_NAME}:latest
                """
            }
        }

    }

    post {
        success {
            echo 'Build, Push and Deployment Successful!'
        }

        failure {
            echo 'Pipeline Failed!'
        }
    }
}

