import groovy.json.JsonOutput

// =====================================================
// FINAL PRODUCTION JENKINSFILE
// GitHub private + Docker Hub credentials
// =====================================================

pipeline {
    agent none

    environment {
        APP_NAME       = 'laravel-app'
        DOCKER_IMAGE   = 'nginx'
        WEBUI_API      = 'http://117.103.71.154:31078'
        SYNC_JOB_TOKEN = 'sync-token'
    }

    options {
        disableConcurrentBuilds()
        timeout(time: 1, unit: 'HOURS')
        buildDiscarder(logRotator(numToKeepStr: '10'))
    }

    stages {

        // ===============================
        // STAGE 1: CHECKOUT & VERSIONING
        // ===============================
        stage('Checkout & Versioning') {
            agent { label 'jenkins-light' }
            steps {
                script {
                    checkout([
                        $class: 'GitSCM',
                        branches: scm.branches,
                        userRemoteConfigs: [[
                            url: scm.userRemoteConfigs[0].url,
                            credentialsId: 'github-cred'
                        ]]
                    ])
                }

                sh 'git fetch --tags --force'

                script {
                    String version = null

                    if (env.TAG_NAME?.trim()) {
                        version = env.TAG_NAME
                    } else {
                        def tag = sh(
                            script: "git describe --tags --exact-match HEAD 2>/dev/null || echo NOTAG",
                            returnStdout: true
                        ).trim()

                        if (tag.startsWith('v')) {
                            version = tag
                        }
                    }

                    env.APP_VERSION = version ?: "dev-${env.BUILD_NUMBER}"
                    echo "APP_VERSION = ${env.APP_VERSION}"
                }
            }
        }

        // ===============================
        // STAGE 2: BUILD & PUSH DOCKER
        // ===============================
        stage('Build & Push Docker') {
            agent { label 'jenkins-docker' }

            environment {
                DOCKER_CREDS = credentials('docker-cred')
            }

            steps {
                script {
                    checkout([
                        $class: 'GitSCM',
                        branches: scm.branches,
                        userRemoteConfigs: [[
                            url: scm.userRemoteConfigs[0].url,
                            credentialsId: 'github-cred'
                        ]]
                    ])
                }

                container('docker') {
                    sh '''
                        docker version

                        echo "$DOCKER_CREDS_PSW" | docker login \
                          -u "$DOCKER_CREDS_USR" --password-stdin

                        docker build -t ${DOCKER_IMAGE}:${APP_VERSION} .
                        docker push ${DOCKER_IMAGE}:${APP_VERSION}

                        if echo "${APP_VERSION}" | grep -Eq '^v[0-9]+.[0-9]+.[0-9]+$'; then
                            docker tag ${DOCKER_IMAGE}:${APP_VERSION} ${DOCKER_IMAGE}:latest
                            docker push ${DOCKER_IMAGE}:latest
                        fi
                    '''
                }
            }
        }

        // ===============================
        // STAGE 3: DEPLOY TESTING (AUTO)
        // ===============================
        stage('Deploy Testing') {
            agent { label 'jenkins-light' }
            steps {
                script {
                    def payload = JsonOutput.toJson([
                        appName  : APP_NAME,
                        imageTag : APP_VERSION
                    ])

                    writeFile file: 'deploy_test.json', text: payload

                    sh """
                        curl -s -X POST '${WEBUI_API}/api/jenkins/deploy-test' \
                          -H 'Content-Type: application/json' \
                          --data @deploy_test.json || true
                    """

                    sh """
                        curl -s -X POST '${WEBUI_API}/api/sync' \
                          -H 'Authorization: Bearer ${SYNC_JOB_TOKEN}' || true
                    """
                }
            }
        }

        // ===============================
        // STAGE 4: JENKINS APPROVAL (PROD)
        // ===============================
        stage('Approval Production') {
            agent { label 'jenkins-light' }
            steps {
                timeout(time: 30, unit: 'MINUTES') {
                    input(
                        message: "DEPLOY ${APP_NAME}:${APP_VERSION} TO PRODUCTION?",
                        ok: 'DEPLOY PROD'
                    )
                }
            }
        }

        // ===============================
        // STAGE 5: DESTROY TESTING ENV
        // ===============================
        stage('Destroy Testing Environment') {
            agent { label 'jenkins-light' }
            steps {
                script {
                    def payload = JsonOutput.toJson([
                        appName : APP_NAME,
                        source  : 'jenkins'
                    ])

                    writeFile file: 'destroy_test.json', text: payload

                    sh """
                        curl -s -X POST '${WEBUI_API}/api/jenkins/destroy-test' \
                          -H 'Content-Type: application/json' \
                          --data @destroy_test.json || true
                    """
                }
            }
        }

        // ===============================
        // STAGE 6: DEPLOY PRODUCTION
        // ===============================
        stage('Deploy Production') {
            agent { label 'jenkins-light' }
            steps {
                script {
                    def payload = JsonOutput.toJson([
                        appName  : APP_NAME,
                        imageTag : APP_VERSION,
                        env      : 'prod'
                    ])

                    writeFile file: 'deploy_prod.json', text: payload

                    sh """
                        curl -s -X POST '${WEBUI_API}/api/manifest/update-image' \
                          -H 'Content-Type: application/json' \
                          --data @deploy_prod.json || true
                    """

                    sh """
                        curl -s -X POST '${WEBUI_API}/api/sync' \
                          -H 'Authorization: Bearer ${SYNC_JOB_TOKEN}' || true
                    """
                }
            }
        }
    }

    post {
        always {
            node('jenkins-light') {
                cleanWs()
            }
        }
    }
}
