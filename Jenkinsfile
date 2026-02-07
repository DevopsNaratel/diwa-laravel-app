import groovy.json.JsonOutput

def sendWebhook(status, progress, stageName) {
    def payload = JsonOutput.toJson([
        jobName    : env.JOB_NAME,
        buildNumber: env.BUILD_NUMBER,
        status     : status,
        progress   : progress,
        stage      : stageName,
        version    : env.APP_VERSION ?: null,
        url        : env.BUILD_URL ?: null
    ])
    if (env.WEBUI_API?.trim()) {
        writeFile file: 'webui_payload.json', text: payload
        sh(returnStatus: true, script: "curl -s -X POST '${env.WEBUI_API}/api/webhooks/jenkins' -H 'Content-Type: application/json' --data @webui_payload.json || true")
    }
}

def registerPending(file, retries = 2) {
    for (int attempt = 0; attempt <= retries; attempt++) {
        def http = sh(script: "curl -sS -o /dev/null -w '%{http_code}' -X POST '${env.WEBUI_API}/api/jenkins/pending' -H 'Content-Type: application/json' --data @${file}", returnStdout: true).trim()
        if (http ==~ /2\d\d/) return
        if (attempt < retries) {
            echo "registerPending attempt ${attempt + 1} failed (HTTP ${http}), retrying in 5s..."
            sleep 5
        } else {
            error "Failed to register approval in WebUI after ${retries + 1} attempts (HTTP ${http}). WEBUI_API=${env.WEBUI_API}"
        }
    }
}

def triggerSync() {
    sh(returnStatus: true, script: "curl -sS -X POST '${env.WEBUI_API}/api/sync' || true")
}

def waitForSync(int maxWaitSec = 90, int pollSec = 10) {
    // Drain all pending sync jobs by repeatedly calling /api/sync
    int elapsed = 0
    while (elapsed < maxWaitSec) {
        def body = sh(script: "curl -sS -X POST '${env.WEBUI_API}/api/sync'", returnStdout: true).trim()
        if (body.contains('No pending jobs')) {
            echo "All sync jobs processed."
            return
        }
        echo "Sync job processed, checking for more... (${elapsed}s elapsed)"
        sleep pollSec
        elapsed += pollSec
    }
    echo "Warning: sync wait timed out after ${maxWaitSec}s"
}

def cleanupPendingApprovals() {
    // Best-effort: remove any leftover pending jobs for this build
    def ids = [
        "${env.APP_NAME}-${env.BUILD_NUMBER}-ApproveDeploy",
        "${env.APP_NAME}-${env.BUILD_NUMBER}-ConfirmProd"
    ]
    ids.each { pendingId ->
        sh(returnStatus: true, script: "curl -sS -X DELETE '${env.WEBUI_API}/api/jenkins/pending?id=${pendingId}' || true")
    }
}

pipeline {
    agent any

    options {
        timeout(time: 4, unit: 'HOURS')
    }

    environment {
        APP_NAME       = "laravel-diwa"
        DOCKER_IMAGE   = "devopsnaratel/laravel-diwa"
        DOCKER_CRED_ID = "docker-hub"

        // URL WebUI Base
        WEBUI_API      = "https://nonfortifiable-mandie-uncontradictablely.ngrok-free.dev"
    }

    stages {
        stage('Checkout & Get Version') {
            steps {
                script {
                    sendWebhook('STARTED', 2, 'Checkout')
                    checkout scm
                    sh "git fetch --tags --force"

                    def latestTag = sh(script: "git tag --sort=-creatordate | head -n 1", returnStdout: true).trim()
                    if (latestTag) {
                        env.APP_VERSION = latestTag
                        echo "Using latest git tag ${env.APP_VERSION}"
                    } else {
                        def commitShort = sh(script: "git rev-parse --short HEAD", returnStdout: true).trim()
                        env.APP_VERSION = "build-${env.BUILD_NUMBER}-${commitShort}"
                        echo "No git tags found. Using unique version ${env.APP_VERSION}"
                    }
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
                    def payloadObj = [
                        appName    : env.APP_NAME,
                        buildNumber: env.BUILD_NUMBER.toString(),
                        version    : env.APP_VERSION,
                        jenkinsUrl : (env.BUILD_URL ?: '').toString(),
                        inputId    : 'ApproveDeploy',
                        source     : 'jenkins'
                    ]
                    writeFile file: 'pending_payload.json', text: JsonOutput.toJson(payloadObj)
                    registerPending('pending_payload.json')

                    timeout(time: 2, unit: 'HOURS') {
                        input message: "Waiting for configuration & approval from Dashboard...", id: 'ApproveDeploy'
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

                    def http = sh(script: "curl -sS -o /tmp/deploy_test_resp.json -w '%{http_code}' -X POST ${env.WEBUI_API}/api/jenkins/deploy-test -H 'Content-Type: application/json' -d '${deployPayload}'", returnStdout: true).trim()
                    if (!(http ==~ /2\d\d/)) {
                        def body = sh(script: "cat /tmp/deploy_test_resp.json 2>/dev/null || echo 'no response'", returnStdout: true).trim()
                        error "deploy-test failed (HTTP ${http}): ${body}"
                    }
                    waitForSync(90, 10)
                    echo "Waiting 30s for ArgoCD reconciliation..."
                    sleep 30
                }
            }
        }

        stage('Integration Tests') {
            steps {
                script {
                    sendWebhook('IN_PROGRESS', 80, 'Tests')
                    echo "Running Tests..."
                }
            }
        }

        stage('Final Production Approval') {
            steps {
                script {
                    sendWebhook('IN_PROGRESS', 90, 'Prod Approval')
                    def payloadFinal = [
                        appName    : env.APP_NAME,
                        buildNumber: env.BUILD_NUMBER.toString(),
                        version    : env.APP_VERSION,
                        jenkinsUrl : (env.BUILD_URL ?: '').toString(),
                        inputId    : 'ConfirmProd',
                        isFinal    : true,
                        source     : 'jenkins'
                    ]
                    writeFile file: 'pending_payload_final.json', text: JsonOutput.toJson(payloadFinal)
                    registerPending('pending_payload_final.json')

                    timeout(time: 2, unit: 'HOURS') {
                        input message: "Waiting for Final Production Confirmation...", id: 'ConfirmProd'
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

                    def http = sh(script: "curl -sS -o /tmp/prod_deploy_resp.json -w '%{http_code}' -X POST ${env.WEBUI_API}/api/manifest/update-image -H 'Content-Type: application/json' -d '${updatePayload}'", returnStdout: true).trim()
                    if (!(http ==~ /2\d\d/)) {
                        def body = sh(script: "cat /tmp/prod_deploy_resp.json 2>/dev/null || echo 'no response'", returnStdout: true).trim()
                        error "Production deploy failed (HTTP ${http}): ${body}"
                    }
                    waitForSync(90, 10)
                }
            }
        }
    }

    post {
        success { script { sendWebhook('SUCCESS', 100, 'Completed') } }
        failure { script { sendWebhook('FAILED', 100, 'Failed') } }
        always {
            script {
                // Cleanup: destroy ephemeral test env
                def destroyPayload = JsonOutput.toJson([appName: env.APP_NAME])
                sh(returnStatus: true, script: "curl -sS -X POST ${env.WEBUI_API}/api/jenkins/destroy-test -H 'Content-Type: application/json' -d '${destroyPayload}' || true")
                triggerSync()
                // Cleanup: remove any orphaned pending approvals for this build
                cleanupPendingApprovals()
            }
            cleanWs()
        }
    }
}
