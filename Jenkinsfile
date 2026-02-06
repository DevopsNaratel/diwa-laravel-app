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

def registerPending(file) {
    def http = sh(
        script: "curl -sS -o /dev/null -w '%{http_code}' -X POST '${env.WEBUI_API}/api/jenkins/pending' -H 'Content-Type: application/json' --data @${file}",
        returnStdout: true
    ).trim()

    if (!(http ==~ /2\\d\\d/)) {
        error "Failed to register approval in WebUI (HTTP ${http})"
    }
}

def triggerSync() {
    def auth = env.SYNC_JOB_TOKEN?.trim() ? "-H 'Authorization: Bearer ${env.SYNC_JOB_TOKEN}'" : ''
    sh(returnStatus: true, script: "curl -sS -X POST '${env.WEBUI_API}/api/sync' ${auth} || true")
}

pipeline {
    agent any

    environment {
        APP_NAME     = "laravel-diwa"
        DOCKER_IMAGE = "devopsnaratel/laravel-diwa"

        // DEBUG: hardcoded image version
        APP_VERSION  = "1.0.0"

        WEBUI_API      = "https://nonfortifiable-mandie-uncontradictablely.ngrok-free.dev"
        SYNC_JOB_TOKEN = "sync-token"
    }

    stages {

        stage('Checkout (Debug)') {
            steps {
                script {
                    sendWebhook('STARTED', 5, 'Checkout')
                    checkout scm
                    echo "DEBUG MODE: Using prebuilt image ${DOCKER_IMAGE}:${APP_VERSION}"
                    sendWebhook('IN_PROGRESS', 10, 'Checkout')
                }
            }
        }

        stage('Build & Push Docker (SKIPPED)') {
            steps {
                script {
                    sendWebhook('IN_PROGRESS', 20, 'Build')
                    echo "DEBUG MODE: Skipping docker build & push"
                    echo "Assuming image exists: ${DOCKER_IMAGE}:${APP_VERSION}"
                    sendWebhook('IN_PROGRESS', 40, 'Build')
                }
            }
        }

        stage('Configuration & Approval') {
            steps {
                script {
                    sendWebhook('IN_PROGRESS', 55, 'Approval')

                    def payloadObj = [
                        appName     : env.APP_NAME,
                        buildNumber : env.BUILD_NUMBER.toString(),
                        version     : env.APP_VERSION,
                        jenkinsUrl  : (env.BUILD_URL ?: '').toString(),
                        inputId     : 'ApproveDeploy',
                        source      : 'jenkins',
                        debug       : true
                    ]

                    writeFile file: 'pending_payload.json', text: JsonOutput.toJson(payloadObj)
                    registerPending('pending_payload.json')

                    input message: "DEBUG MODE: Waiting for approval...", id: 'ApproveDeploy'
                }
            }
        }

        stage('Deploy Testing (Ephemeral)') {
            steps {
                script {
                    sendWebhook('IN_PROGRESS', 65, 'Deploy Testing')

                    def deployPayload = JsonOutput.toJson([
                        appName  : env.APP_NAME,
                        imageTag: env.APP_VERSION,
                        source  : 'jenkins',
                        debug   : true
                    ])

                    sh(returnStatus: true, script: """
                        curl -sS -X POST '${env.WEBUI_API}/api/jenkins/deploy-test' \
                        -H 'Content-Type: application/json' \
                        -d '${deployPayload}' || true
                    """)

                    triggerSync()
                    sleep 30
                }
            }
        }

        stage('Integration Tests (Debug)') {
            steps {
                script {
                    sendWebhook('IN_PROGRESS', 80, 'Tests')
                    echo "DEBUG MODE: Integration tests placeholder"
                }
            }
        }

        stage('Final Production Approval') {
            steps {
                script {
                    sendWebhook('IN_PROGRESS', 90, 'Prod Approval')

                    def payloadFinal = [
                        appName     : env.APP_NAME,
                        buildNumber : env.BUILD_NUMBER.toString(),
                        version     : env.APP_VERSION,
                        jenkinsUrl  : (env.BUILD_URL ?: '').toString(),
                        inputId     : 'ConfirmProd',
                        isFinal     : true,
                        source      : 'jenkins',
                        debug       : true
                    ]

                    writeFile file: 'pending_payload_final.json', text: JsonOutput.toJson(payloadFinal)
                    registerPending('pending_payload_final.json')

                    input message: "DEBUG MODE: Confirm production deploy", id: 'ConfirmProd'
                }
            }
        }

        stage('Deploy to Production') {
            steps {
                script {
                    sendWebhook('IN_PROGRESS', 95, 'Deploy Production')

                    def updatePayload = JsonOutput.toJson([
                        appName  : env.APP_NAME,
                        env      : 'prod',
                        imageTag: env.APP_VERSION,
                        source  : 'jenkins',
                        debug   : true
                    ])

                    sh(returnStatus: true, script: """
                        curl -sS -X POST '${env.WEBUI_API}/api/manifest/update-image' \
                        -H 'Content-Type: application/json' \
                        -d '${updatePayload}' || true
                    """)

                    triggerSync()
                }
            }
        }
    }

    post {
        success { script { sendWebhook('SUCCESS', 100, 'Completed') } }
        failure { script { sendWebhook('FAILED', 100, 'Failed') } }
        always {
            script {
                def destroyPayload = JsonOutput.toJson([
                    appName: env.APP_NAME,
                    debug  : true
                ])

                sh(returnStatus: true, script: """
                    curl -sS -X POST '${env.WEBUI_API}/api/jenkins/destroy-test' \
                    -H 'Content-Type: application/json' \
                    -d '${destroyPayload}' || true
                """)

                triggerSync()
            }
            cleanWs()
        }
    }
}
