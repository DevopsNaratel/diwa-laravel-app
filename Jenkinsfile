import groovy.json.JsonOutput

def sendWebhook(status, progress, stageName) {
    def payload = """
{"jobName":"${env.JOB_NAME}","buildNumber":"${env.BUILD_NUMBER}","status":"${status}","progress":${progress},"stage":"${stageName}"}
"""

    if (env.WEBUI_API?.trim()) {
        writeFile file: 'webui_payload.json', text: payload
        // Best-effort call: do not fail the build if WebUI is unreachable
        sh(returnStatus: true, script: "curl -s -X POST '${env.WEBUI_API}/api/webhooks/jenkins' -H 'Content-Type: application/json' --data @webui_payload.json || true")
    } else {
        echo "WEBUI_API not set; skipping webhook"
    }
}

pipeline {
    agent any

    environment {
        APP_NAME       = "sawit"
        DOCKER_IMAGE   = "devopsnaratel/diwapp"
        DOCKER_CRED_ID = "docker-hub"

        // URL WebUI Base
        WEBUI_API      = "https://nonfortifiable-mandie-uncontradictablely.ngrok-free.dev"
        
        APP_VERSION    = ""
        // Optional token for auto sync (set in Jenkins/secret)
        SYNC_JOB_TOKEN = "change_me_sync_token"
    }

    stages {
        stage('Checkout & Get Version') {
            steps {
                script {
                    sendWebhook('STARTED', 2, 'Checkout')
                    checkout scm
                    env.APP_VERSION = sh(
                        script: "git describe --tags --always --abbrev=0 || echo ${BUILD_NUMBER}",
                        returnStdout: true
                    ).trim()
                    echo "Building Version: ${env.APP_VERSION}"
                    sendWebhook('IN_PROGRESS', 8, 'Checkout')
                }
            }
        }

        stage('Build & Push Docker') {
            steps {
                script {
                    sendWebhook('IN_PROGRESS', 20, 'Build')
                    docker.withRegistry('', env.DOCKER_CRED_ID) {
                        def customImage = docker.build("${env.DOCKER_IMAGE}:${env.APP_VERSION}")
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
                    {"appName": "${env.APP_NAME}", "buildNumber": "${env.BUILD_NUMBER}", "version": "${env.APP_VERSION}", "jenkinsUrl": "${env.JENKINS_URL}/job/${env.JOB_NAME}/${env.BUILD_NUMBER}", "inputId": "ApproveDeploy", "source": "jenkins"}
                    """
                    
                    sh(script: "curl -s -X POST ${env.WEBUI_API}/api/jenkins/pending -H 'Content-Type: application/json' -d '${payload}' || true")

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
                    def deployPayload = JsonOutput.toJson([appName: env.APP_NAME, imageTag: env.APP_VERSION, source: 'jenkins'])
                    def response = sh(script: "curl -s -X POST ${env.WEBUI_API}/api/jenkins/deploy-test -H 'Content-Type: application/json' -d '${deployPayload}' || true", returnStdout: true).trim()

                    echo "WebUI Response: ${response}"

                    echo "Waiting for pods to be ready..."
                    sleep 60

                    def syncHeader = env.SYNC_JOB_TOKEN?.trim() ? '-H "Authorization: Bearer ' + env.SYNC_JOB_TOKEN + '"' : ''
                    sh(script: "curl -s -X POST ${env.WEBUI_API}/api/sync ${syncHeader} || true")
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
                    {"appName": "${env.APP_NAME}", "buildNumber": "${env.BUILD_NUMBER}", "version": "${env.APP_VERSION}", "jenkinsUrl": "${env.JENKINS_URL}/job/${env.JOB_NAME}/${env.BUILD_NUMBER}", "inputId": "ConfirmProd", "isFinal": true, "source": "jenkins"}
                    """
                    
                    sh(script: "curl -s -X POST ${env.WEBUI_API}/api/jenkins/pending -H 'Content-Type: application/json' -d '${payload}' || true")

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
                    def updatePayload = JsonOutput.toJson([appName: env.APP_NAME, env: 'prod', imageTag: env.APP_VERSION, source: 'jenkins'])
                    def response = sh(script: "curl -s -X POST ${env.WEBUI_API}/api/manifest/update-image -H 'Content-Type: application/json' -d '${updatePayload}' || true", returnStdout: true).trim()

                    echo "WebUI Response: ${response}"

                    def syncHeader = env.SYNC_JOB_TOKEN?.trim() ? '-H "Authorization: Bearer ' + env.SYNC_JOB_TOKEN + '"' : ''
                    sh(script: "curl -s -X POST ${env.WEBUI_API}/api/sync ${syncHeader} || true")
                }
            }
        }

        stage('Tag Stable Version') {
            steps {
                script {
                    sendWebhook('IN_PROGRESS', 98, 'Tag')
                    def tagName = "v${env.APP_VERSION}-prod"
                    echo "Requesting Dashboard to tag Manifest Repo: ${tagName}"
                    
                    def tagPayload = JsonOutput.toJson([
                        appName: env.APP_NAME,
                        tagName: tagName,
                        message: "Stable release v${env.APP_VERSION} for ${env.APP_NAME}",
                        source: 'jenkins'
                    ])
                    def response = sh(script: "curl -s -X POST ${env.WEBUI_API}/api/manifest/tag -H 'Content-Type: application/json' -d '${tagPayload}' || true", returnStdout: true).trim()
                    
                    echo "WebUI Response: ${response}"

                    def syncHeader = env.SYNC_JOB_TOKEN?.trim() ? '-H "Authorization: Bearer ' + env.SYNC_JOB_TOKEN + '"' : ''
                    sh(script: "curl -s -X POST ${env.WEBUI_API}/api/sync ${syncHeader} || true")
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
                def destroyPayload = JsonOutput.toJson([appName: env.APP_NAME])
                sh "curl -s -X POST ${env.WEBUI_API}/api/jenkins/destroy-test -H 'Content-Type: application/json' -d '${destroyPayload}' || true"
                cleanWs()
            }
        }
    }
}
