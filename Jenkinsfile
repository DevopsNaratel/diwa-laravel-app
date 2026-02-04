def sendWebhook(status, progress, stageName) {
    def payload = """
    {
        \"jobName\": \"${env.JOB_NAME}\",
        \"buildNumber\": ${env.BUILD_NUMBER},
        \"status\": \"${status}\",
        \"progress\": ${progress},
        \"stage\": \"${stageName}\"
    }
    """
    sh(script: """
        curl -s -X POST ${env.WEBUI_API}/api/webhooks/jenkins \\
        -H \"Content-Type: application/json\" \\
        -d '${payload}'
    """)
}

pipeline {
    agent any

    environment {
        APP_NAME       = "diwaw-laravel"
        DOCKER_IMAGE   = "devopsnaratel/laravel-diwa"
        DOCKER_CRED_ID = "docker-hub"

        // URL WebUI Base
        WEBUI_API      = "https://nonfortifiable-mandie-uncontradictablely.ngrok-free.dev"
        
        APP_VERSION    = ""
            // Optional token for auto sync (set in Jenkins/secret)
            SYNC_JOB_TOKEN = ""
    }

    stages {
        stage('Checkout & Get Version') {
            steps {
                script {
                    sendWebhook('STARTED', 2, 'Checkout')
                    checkout scm
                    APP_VERSION = sh(
                        script: "git describe --tags --always --abbrev=0 || echo ${BUILD_NUMBER}",
                        returnStdout: true
                    ).trim()
                    echo "Building Version: ${APP_VERSION}"
                    sendWebhook('IN_PROGRESS', 8, 'Checkout')
                }
            }
        }

        stage('Build & Push Docker') {
            steps {
                script {
                    sendWebhook('IN_PROGRESS', 20, 'Build')
                    docker.withRegistry('', "${DOCKER_CRED_ID}") {
                        def customImage = docker.build("${DOCKER_IMAGE}:${APP_VERSION}")
                        customImage.push()
                        customImage.push("latest")
                    }
                    sendWebhook('IN_PROGRESS', 40, 'Build')
                }
            }
        }

        stage('Configuration & Approval') {
            steps {
                script {
                    sendWebhook('IN_PROGRESS', 55, 'Approval')
                    echo "Registering pending approval in Dashboard..."
                    def payload = """
                    {
                        "appName": "${APP_NAME}", 
                        "buildNumber": "${BUILD_NUMBER}", 
                        "version": "${APP_VERSION}",
                        "jenkinsUrl": "${JENKINS_URL}/job/${JOB_NAME}/${BUILD_NUMBER}",
                        "inputId": "ApproveDeploy",
                        "source": "jenkins"
                    }
                    """
                    
                    sh(script: """
                        curl -s -X POST ${WEBUI_API}/api/jenkins/pending \\
                        -H "Content-Type: application/json" \\
                        -d '${payload}'
                    """)

                    try {
                        input message: "Waiting for configuration & approval from Dashboard...",
                              id: 'ApproveDeploy'
                    } catch (Exception e) {
                        currentBuild.result = 'ABORTED'
                        error "Deployment Cancelled via Dashboard."
                    }
                }
            }
        }

        stage('Deploy Testing (Ephemeral)') {
            steps {
                script {
                    sendWebhook('IN_PROGRESS', 65, 'Deploy Testing')
                    echo "Triggering WebUI to create Ephemeral Testing Environment..."
                    def response = sh(script: """
                        curl -s -X POST ${WEBUI_API}/api/jenkins/deploy-test \\
                        -H "Content-Type: application/json" \\
                        -d '{"appName": "${APP_NAME}", "imageTag": "${APP_VERSION}", "source": "jenkins"}'
                    """, returnStdout: true).trim()

                    echo "WebUI Response: ${response}"

                    if (response.contains('"error"')) {
                        error "Failed to deploy testing env: ${response}"
                    }

                    echo "Waiting for pods to be ready..."
                    sleep 60

                    def syncHeader = SYNC_JOB_TOKEN?.trim() ? '-H "Authorization: Bearer ' + SYNC_JOB_TOKEN + '"' : ''
                    sh(script: """
                        curl -s -X POST ${WEBUI_API}/api/sync \
                        ${syncHeader}
                    """)
                }
            }
        }

        stage('Integration Tests') {
            steps {
                script {
                    sendWebhook('IN_PROGRESS', 80, 'Tests')
                    echo "Running Tests against Testing Env..."
                }
            }
        }

        stage('Final Production Approval') {
            steps {
                script {
                    sendWebhook('IN_PROGRESS', 90, 'Prod Approval')
                    echo "Requesting Final Confirmation from Dashboard..."
                    def payload = """
                    {
                        "appName": "${APP_NAME}", 
                        "buildNumber": "${BUILD_NUMBER}", 
                        "version": "${APP_VERSION}",
                        "jenkinsUrl": "${JENKINS_URL}/job/${JOB_NAME}/${BUILD_NUMBER}",
                        "inputId": "ConfirmProd",
                        "isFinal": true,
                        "source": "jenkins"
                    }
                    """
                    
                    sh(script: """
                        curl -s -X POST ${WEBUI_API}/api/jenkins/pending \\
                        -H "Content-Type: application/json" \\
                        -d '${payload}'
                    """)

                    try {
                        input message: "Waiting for Final Production Confirmation...",
                              id: 'ConfirmProd'
                    } catch (Exception e) {
                        currentBuild.result = 'ABORTED'
                        error "Production Deployment Cancelled."
                    }
                }
            }
        }

        stage('Deploy to Production') {
            steps {
                script {
                    sendWebhook('IN_PROGRESS', 95, 'Deploy Production')
                    echo "Updating Production Image Version..."
                    def response = sh(script: """
                        curl -s -X POST ${WEBUI_API}/api/manifest/update-image \\
                        -H "Content-Type: application/json" \\
                        -d '{"appName": "${APP_NAME}", "env": "prod", "imageTag": "${APP_VERSION}", "source": "jenkins"}'
                    """, returnStdout: true).trim()

                    echo "WebUI Response: ${response}"

                    if (response.contains('"error"')) {
                        error "Failed to update production: ${response}"
                    }

                    def syncHeader = SYNC_JOB_TOKEN?.trim() ? '-H "Authorization: Bearer ' + SYNC_JOB_TOKEN + '"' : ''
                    sh(script: """
                        curl -s -X POST ${WEBUI_API}/api/sync \
                        ${syncHeader}
                    """)
                }
            }
        }

        stage('Tag Stable Version') {
            steps {
                script {
                    sendWebhook('IN_PROGRESS', 98, 'Tag')
                    def tagName = "v${APP_VERSION}-prod"
                    echo "Requesting Dashboard to tag Manifest Repo: ${tagName}"
                    
                    def response = sh(script: """
                        curl -s -X POST ${WEBUI_API}/api/manifest/tag \\
                        -H "Content-Type: application/json" \\
                        -d '{"appName": "${APP_NAME}", "tagName": "${tagName}", "message": "Stable release v${APP_VERSION} for ${APP_NAME}", "source": "jenkins"}'
                    """, returnStdout: true).trim()
                    
                    echo "WebUI Response: ${response}"

                    def syncHeader = SYNC_JOB_TOKEN?.trim() ? '-H "Authorization: Bearer ' + SYNC_JOB_TOKEN + '"' : ''
                    sh(script: """
                        curl -s -X POST ${WEBUI_API}/api/sync \
                        ${syncHeader}
                    """)
                }
            }
        }
    }

    post {
        success {
            script {
                sendWebhook('SUCCESS', 100, 'Completed')
            }
        }
        failure {
            script {
                sendWebhook('FAILED', 100, 'Failed')
            }
        }
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
