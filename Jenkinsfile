pipeline {
    agent any

    environment {
        APP_NAME       = "laravel-diwa"
        DOCKER_IMAGE   = "devopsnaratel/laravel-diwa"
        DOCKER_CRED_ID = "docker-hub"

        // URL WebUI Base
        WEBUI_API      = "https://nonfortifiable-mandie-uncontradictablely.ngrok-free.dev"
        
        APP_VERSION    = ""
    }

    stages {
        stage('Checkout & Get Version') {
            steps {
                script {
                    checkout scm
                    APP_VERSION = sh(
                        script: "git describe --tags --always --abbrev=0 || echo ${BUILD_NUMBER}",
                        returnStdout: true
                    ).trim()
                    echo "Building Version: ${APP_VERSION}"
                }
            }
        }

        stage('Build & Push Docker') {
            steps {
                script {
                    docker.withRegistry('', "${DOCKER_CRED_ID}") {
                        def customImage = docker.build("${DOCKER_IMAGE}:${APP_VERSION}")
                        customImage.push()
                        customImage.push("latest")
                    }
                }
            }
        }

        stage('Deploy Testing (Ephemeral)') {
            steps {
                script {
                    echo "Triggering WebUI to create Ephemeral Testing Environment..."
                    def response = sh(script: """
                        curl -s -X POST ${WEBUI_API}/api/jenkins/deploy-test \\
                        -H "Content-Type: application/json" \\
                        -d '{"appName": "${APP_NAME}", "imageTag": "${APP_VERSION}"}'
                    """, returnStdout: true).trim()

                    echo "WebUI Response: ${response}"

                    if (response.contains('"error"')) {
                        error "Failed to deploy testing env: ${response}"
                    }

                    echo "Waiting for pods to be ready..."
                    sleep 60
                }
            }
        }

        stage('Integration Tests') {
            steps {
                script {
                    echo "Running Tests against Testing Env..."
                    // Add your test commands here
                }
            }
        }

        stage('Approval for Production') {
            steps {
                script {
                    try {
                        input message: "Testing Done. Approve deploy ${APP_VERSION} to Production?",
                              id: 'ApproveDeploy'
                    } catch (Exception e) {
                        currentBuild.result = 'ABORTED'
                        error "Deployment to Production Cancelled."
                    }
                }
            }
        }

        stage('Deploy to Production') {
            steps {
                script {
                    echo "Updating Production Image Version..."
                    def response = sh(script: """
                        curl -s -X POST ${WEBUI_API}/api/manifest/update-image \\
                        -H "Content-Type: application/json" \\
                        -d '{"appName": "${APP_NAME}", "env": "prod", "imageTag": "${APP_VERSION}"}'
                    """, returnStdout: true).trim()

                    echo "WebUI Response: ${response}"

                    if (response.contains('"error"')) {
                        error "Failed to update production: ${response}"
                    }
                }
            }
        }
    }

    post {
        always {
            script {
                echo "Cleaning up Ephemeral Testing Environment..."
                sh """
                    curl -s -X POST ${WEBUI_API}/api/jenkins/destroy-test \\
                    -H "Content-Type: application/json" \\
                    -d '{"appName": "${APP_NAME}"}'
                """
                cleanWs()
            }
        }
    }
}
