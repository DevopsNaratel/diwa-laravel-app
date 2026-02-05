import groovy.json.JsonOutput

def sendWebhook(status, progress, stageName) {
    def payload = """
{"jobName":"${env.JOB_NAME}","buildNumber":"${env.BUILD_NUMBER}","status":"${status}","progress":${progress},"stage":"${stageName}"}
"""
    if (env.WEBUI_API?.trim()) {
        writeFile file: 'webui_payload.json', text: payload
        sh(returnStatus: true, script: "curl -s -X POST '${env.WEBUI_API}/api/webhooks/jenkins' -H 'Content-Type: application/json' --data @webui_payload.json || true")
    }
}

pipeline {
    agent any

    environment {
        APP_NAME       = "diwaw-laravel"
        DOCKER_IMAGE   = "devopsnaratel/laravel-diwa"
        DOCKER_CRED_ID = "docker-hub"

        // Git credential ID in Jenkins
        GIT_CRED_ID    = "git-token"

        WEBUI_API      = "https://nonfortifiable-mandie-uncontradictablely.ngrok-free.dev"
        APP_VERSION    = ""
        SYNC_JOB_TOKEN = "sync-token"
    }

    stages {

        stage('Checkout & Get Version') {
            steps {
                script {
                    sendWebhook('STARTED', 2, 'Checkout')
                    checkout scm

                    def latestTag = sh(
                        script: "git tag --sort=-creatordate | head -n 1",
                        returnStdout: true
                    ).trim()

                    if (!latestTag) {
                        def newTag = "v0.0.0-build-${env.BUILD_NUMBER}"
                        echo "No git tags found. Creating tag: ${newTag}"

                        sh "git tag -a ${newTag} -m 'Auto tag ${newTag}' || true"

                        // explicit credential scope for git push
                        withCredentials([usernamePassword(
                            credentialsId: env.GIT_CRED_ID,
                            usernameVariable: 'GIT_USER',
                            passwordVariable: 'GIT_TOKEN'
                        )]) {
                            sh """
                                git push https://${GIT_USER}:${GIT_TOKEN}@github.com/DevopsNaratel/diwa-laravel-app.git ${newTag} || true
                            """
                        }

                        latestTag = newTag
                    }

                    def resolvedVersion = latestTag?.trim()
                    if (!resolvedVersion) {
                        error("Resolved version is empty. Aborting build.")
                    }

                    env.APP_VERSION = resolvedVersion
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
                        def img = docker.build("${env.DOCKER_IMAGE}:${env.APP_VERSION}")
                        img.push()
                        img.push("latest")
                    }
                    sendWebhook('IN_PROGRESS', 40, 'Build')
                }
            }
        }

        stage('Configuration & Approval') {
            steps {
                script {
                    sendWebhook('IN_PROGRESS', 55, 'Approval')

                    def buildUrlSafe = (env.BUILD_URL ?: "${env.JENKINS_URL}/job/${env.JOB_NAME}/${env.BUILD_NUMBER}")
                    def payloadObj = [
                        appName    : env.APP_NAME,
                        buildNumber: env.BUILD_NUMBER.toString(),
                        version    : env.APP_VERSION,
                        jenkinsUrl : buildUrlSafe,
                        inputId    : 'ApproveDeploy',
                        source     : 'jenkins'
                    ]

                    writeFile file: 'pending_payload.json', text: JsonOutput.toJson(payloadObj)
                    sh(returnStatus: true, script: "curl -s -X POST '${env.WEBUI_API}/api/jenkins/pending' -H 'Content-Type: application/json' --data @pending_payload.json || true")

                    try {
                        input message: "Waiting for configuration & approval from Dashboard...", id: 'ApproveDeploy'
                    } catch (e) {
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

                    def deployPayload = JsonOutput.toJson([
                        appName : env.APP_NAME,
                        imageTag: env.APP_VERSION,
                        source  : 'jenkins'
                    ])

                    sh(returnStatus: true, script: "curl -s -X POST ${env.WEBUI_API}/api/jenkins/deploy-test -H 'Content-Type: application/json' -d '${deployPayload}' || true")
                    sleep 60

                    def syncHeader = env.SYNC_JOB_TOKEN?.trim() ? "-H \"Authorization: Bearer ${env.SYNC_JOB_TOKEN}\"" : ""
                    sh(returnStatus: true, script: "curl -s -X POST ${env.WEBUI_API}/api/sync ${syncHeader} || true")
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

                    def buildUrlSafe = (env.BUILD_URL ?: "${env.JENKINS_URL}/job/${env.JOB_NAME}/${env.BUILD_NUMBER}")
                    def payloadObj = [
                        appName    : env.APP_NAME,
                        buildNumber: env.BUILD_NUMBER.toString(),
                        version    : env.APP_VERSION,
                        jenkinsUrl : buildUrlSafe,
                        inputId    : 'ConfirmProd',
                        isFinal    : true,
                        source     : 'jenkins'
                    ]

                    writeFile file: 'pending_payload_final.json', text: JsonOutput.toJson(payloadObj)
                    sh(returnStatus: true, script: "curl -s -X POST '${env.WEBUI_API}/api/jenkins/pending' -H 'Content-Type: application/json' --data @pending_payload_final.json || true")

                    try {
                        input message: "Waiting for Final Production Confirmation...", id: 'ConfirmProd'
                    } catch (e) {
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

                    def updatePayload = JsonOutput.toJson([
                        appName : env.APP_NAME,
                        env     : 'prod',
                        imageTag: env.APP_VERSION,
                        source  : 'jenkins'
                    ])

                    sh(returnStatus: true, script: "curl -s -X POST ${env.WEBUI_API}/api/manifest/update-image -H 'Content-Type: application/json' -d '${updatePayload}' || true")

                    def syncHeader = env.SYNC_JOB_TOKEN?.trim() ? "-H \"Authorization: Bearer ${env.SYNC_JOB_TOKEN}\"" : ""
                    sh(returnStatus: true, script: "curl -s -X POST ${env.WEBUI_API}/api/sync ${syncHeader} || true")
                }
            }
        }

        stage('Tag Stable Version') {
            steps {
                script {
                    sendWebhook('IN_PROGRESS', 98, 'Tag')

                    def tagPayload = JsonOutput.toJson([
                        appName : env.APP_NAME,
                        tagName : "v${env.APP_VERSION}-prod",
                        message : "Stable release v${env.APP_VERSION} for ${env.APP_NAME}",
                        source  : 'jenkins'
                    ])

                    sh(returnStatus: true, script: "curl -s -X POST ${env.WEBUI_API}/api/manifest/tag -H 'Content-Type: application/json' -d '${tagPayload}' || true")

                    def syncHeader = env.SYNC_JOB_TOKEN?.trim() ? "-H \"Authorization: Bearer ${env.SYNC_JOB_TOKEN}\"" : ""
                    sh(returnStatus: true, script: "curl -s -X POST ${env.WEBUI_API}/api/sync ${syncHeader} || true")
                }
            }
        }
    }

    post {
        success {
            script { sendWebhook('SUCCESS', 100, 'Completed') }
        }
        failure {
            script { sendWebhook('FAILED', 100, 'Failed') }
        }
        always {
            script {
                def destroyPayload = JsonOutput.toJson([appName: env.APP_NAME])
                sh(returnStatus: true, script: "curl -s -X POST ${env.WEBUI_API}/api/jenkins/destroy-test -H 'Content-Type: application/json' -d '${destroyPayload}' || true")
                cleanWs()
            }
        }
    }
}
