pipeline {
    agent any

    environment {
        // --- KONFIGURASI APLIKASI ---
        APP_NAME       = "laravel-diwa"              // Nama aplikasi di GitOps repo
        DOCKER_IMAGE   = "devopsnaratel/laravel-diwa" // Nama image di Docker Hub
        
        // --- KONFIGURASI GITOPS REPO ---
        GITOPS_REPO    = "https://github.com/DevopsNaratel/Deployment-Manifest-App.git"
        GITOPS_BRANCH  = "main"
        
        // Credential IDs di Jenkins
        GIT_CRED_ID    = "git-token"  // Pastikan ID ini ada di Jenkins Credentials
        DOCKER_CRED_ID = "docker-hub" // Pastikan ID ini ada di Jenkins Credentials
    }

    stages {
        stage('Checkout & Get Tag') {
            steps {
                checkout scm
                script {
                    // Mengambil tag dari Git. Jika tidak ada tag, gunakan commit hash pendek.
                    // Ini menjawab keinginan agar tag Docker sama dengan tag dari programmer.
                    IMAGE_TAG = sh(script: "git describe --tags --always || git rev-parse --short HEAD", returnStdout: true).trim()
                    echo "Programmer Tag detected: ${IMAGE_TAG}"
                }
            }
        }

        stage('Build & Push Docker Image') {
            steps {
                script {
                    docker.withRegistry('', "${DOCKER_CRED_ID}") {
                        // Build menggunakan tag dari programmer
                        def customImage = docker.build("${DOCKER_IMAGE}:${IMAGE_TAG}")
                        customImage.push()
                        customImage.push("latest")
                    }
                }
            }
        }

        stage('Deploy to Testing') {
            steps {
                script {
                    // Update manifest di repo GitOps untuk env testing
                    updateManifest("testing", "${APP_NAME}", "${IMAGE_TAG}")
                }
            }
        }

        stage('Waiting for Approval') {
            steps {
                script {
                    echo "Pipeline paused. Menunggu approval manual untuk lanjut ke Production..."
                    input message: "Approve deployment tag ${IMAGE_TAG} ke Production?", id: 'ApproveDeploy'
                }
            }
        }

        stage('Deploy to Production') {
            steps {
                script {
                    // Update manifest di repo GitOps untuk env prod
                    updateManifest("prod", "${APP_NAME}", "${IMAGE_TAG}")
                }
            }
        }
    }

    post {
        always {
            cleanWs()
        }
        success {
            echo "Deployment tag ${IMAGE_TAG} berhasil diproses ke GitOps."
        }
    }
}

// --- Fungsi Helper: Update Manifest GitOps ---
def updateManifest(envName, appName, imageTag) {
    def targetFolder = "apps/${appName}-${envName}"
    
    dir('gitops-repo-dir') {
        // 1. Clone repo manifest
        git branch: "${GITOPS_BRANCH}",
            url: "${GITOPS_REPO}",
            credentialsId: "${GIT_CRED_ID}"

        if (fileExists(targetFolder)) {
            echo "Updating tag to ${imageTag} in ${targetFolder}/values.yaml"
            
            // 2. Gunakan sed untuk mengganti nilai tag di dalam file values.yaml
            sh "sed -i 's/tag: .*/tag: \"${imageTag}\"/' ${targetFolder}/values.yaml"

            // 3. Konfigurasi identitas Git lokal
            sh 'git config user.email "jenkins@naratel.id"'
            sh 'git config user.name "Jenkins Pipeline"'

            // 4. Logika Anti-Gagal: Hanya commit jika ada perubahan (Fix Exit Code 1)
            // Menggunakan --allow-empty agar tidak error jika programmer re-deploy tag yang sama
            withCredentials([usernamePassword(credentialsId: "${GIT_CRED_ID}", 
                             usernameVariable: 'GIT_USER', passwordVariable: 'GIT_PASS')]) {
                sh """
                    git add ${targetFolder}/values.yaml
                    if ! git diff --cached --exit-code > /dev/null; then
                        git commit -m "ci: update ${appName} ${envName} to tag ${imageTag}"
                        git push https://${GIT_USER}:${GIT_PASS}@${GITOPS_REPO.replace('https://', '')} HEAD:${GITOPS_BRANCH}
                    else
                        echo "No changes detected. Tag ${imageTag} sudah terpasang. Skipping push."
                    fi
                """
            }
        } else {
            error "Folder ${targetFolder} tidak ditemukan! Pastikan generator WebUI sudah membuat folder ini."
        }
    }
}