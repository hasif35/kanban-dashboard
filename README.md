Kanban Dashboard – CI/CD Deployment with Docker, Jenkins & AWS


Project Overview
This project demonstrates an end-to-end DevOps CI/CD pipeline for deploying a Kanban Dashboard application using Jenkins, Docker, Docker Hub, and AWS EC2.
The pipeline automates source code checkout, Docker image building, image publishing, and application deployment using a Blue-Green Deployment strategy.

Architecture

Deployment Flow:
GitHub → Jenkins → Docker Build → Docker Hub → AWS EC2 → Nginx Reverse Proxy → Kanban Dashboard
Technologies Used
* Cloud: AWS EC2
* Version Control: Git and GitHub
* CI/CD: Jenkins
* Containerization: Docker
* Container Registry: Docker Hub
* Reverse Proxy: Nginx
* Application: Kanban Dashboard (Vite)

Project Features
* Automated CI/CD pipeline triggered by GitHub webhook
* Multi-stage Docker build
* Lightweight Alpine-based container images
* Non-root container execution
* Docker health checks
* Docker image publishing to Docker Hub
* Blue-Green Deployment using Docker containers
* Nginx reverse proxy for traffic switching
* Application health and production endpoint validation
* Rollback handling when deployment validation faill


Docker Configuration
The application uses a multi-stage Dockerfile:
1. Node.js Alpine image for building the application.
2. Nginx unprivileged Alpine image for serving the production build.



CI/CD Pipeline
The Jenkins pipeline performs the following stages:
1. Checkout source code from GitHub.
2. Identify the Git commit and generate an image tag.
3. Build the Docker image.
4. Push the versioned image and latest tag to Docker Hub.
5. Identify the currently active Blue or Green environment.
6. Deploy the new version to the inactive environment.
7. Validate Docker container health and application responsiveness.
8. Switch Nginx traffic to the new environment.
9. Validate the production endpoint.
10. Clean up the previous environment after successful deployment.

Blue-Green Deployment Strategy
This project uses Blue-Green Deployment to minimize application downtime.
* The active environment continues serving production traffic.
* The new application version is deployed to the inactive environment.
* Jenkins checks container health and application availability.
* Nginx switches traffic to the new environment after successful validation.
* Production HTTP response is verified.
* The previous environment is removed after successful deployment.
If deployment validation fails, the pipeline attempts to restore the previous Nginx backend.


Docker Hub Repository

Docker Hub Repository:
https://hub.docker.com/r/hhasif/kanban-dashboard

The pipeline also publishes the latest tag.
Application Access
Application URL: http://13.233.9.106:3000

Jenkins Pipeline
Jenkins URL: http://13.233.9.106:8080

The pipeline is configured to build and deploy the application automatically when changes are pushed to the connected GitHub repository.


