pipeline {
    agent any

    environment {
        // --- KONFIGURASI APLIKASI ---
        APP_NAME      = "laravel-diwa"              // Sesuaikan dengan nama aplikasi di Registry/WebUI
        DOCKER_IMAGE  = "devopsnaratel/laravel-diwa" // Image Repository
        
        // --- KONFIGURASI GITOPS ---
        GITOPS_REPO   = "https://github.com/DevopsNaratel/Deployment-Manifest-App.git"
        GITOPS_BRANCH = "main"
        
        // Credential ID yang tersimpan di Jenkins (Username & Password/Token Git)
        GIT_CRED_ID   = "git-token" 
        
        // Credential ID untuk Docker Hub
        DOCKER_CRED_ID = "docker-hub"
    }

    stages {
        stage('Checkout Code') {
            steps {
                checkout scm
            }
        }

        stage('Build & Push Docker Image') {
            steps {
                script {
                    docker.withRegistry('', "${DOCKER_CRED_ID}") {
                        def customImage = docker.build("${DOCKER_IMAGE}:${BUILD_NUMBER}")
                        customImage.push()
                        customImage.push("latest")
                    }
                }
            }
        }

        stage('Deploy to Testing') {
            steps {
                script {
                    updateManifest("testing", "${APP_NAME}", "${DOCKER_IMAGE}", "${BUILD_NUMBER}")
                }
            }
        }

        // --- APPROVAL GATEWAY (WebUI Integration) ---
        stage('Waiting for Approval') {
            steps {
                script {
                    echo "Pipeline paused. Waiting for approval via Naratel DevOps Dashboard..."
                    // 'id' ini penting agar WebUI bisa mengidentifikasi input step
                    // WebUI Anda akan memanggil API Jenkins untuk meng-approve step ini
                    input message: 'Approve deployment to Production?', id: 'ApproveDeploy'
                }
            }
        }
        // ---------------------------------------------

        stage('Deploy to Production') {
            steps {
                script {
                    updateManifest("prod", "${APP_NAME}", "${DOCKER_IMAGE}", "${BUILD_NUMBER}")
                }
            }
        }
    }

    post {
        always {
            cleanWs()
        }
        success {
            echo "Pipeline successfully completed."
        }
    }
}

// --- Helper Function untuk Update Manifest GitOps ---
def updateManifest(envName, appName, imageRepo, imageTag) {
    // Tentukan folder target berdasarkan struktur folder generator WebUI
    // Format: apps/[appName]-[env] (contoh: apps/ngetest-testing)
    def targetFolder = "apps/${appName}-${envName}"
    
    dir('gitops-repo') {
        // Clone GitOps Repo
        git branch: "${GITOPS_BRANCH}",
            url: "${GITOPS_REPO}",
            credentialsId: "${GIT_CRED_ID}"

        // Cek apakah folder aplikasi ada
        if (fileExists(targetFolder)) {
            echo "Updating manifest for ${envName} in ${targetFolder}..."
            
            // Update tag image di values.yaml menggunakan sed
            // Mencari baris 'tag: "..."' dan menggantinya
            sh """
                sed -i 's|tag: ".*"|tag: "${imageTag}"|' ${targetFolder}/values.yaml
            """
            
            // Konfigurasi Git Identity (jika belum ada di global config agent)
            sh """
                git config user.email "jenkins@naratel.id"
                git config user.name "Jenkins Pipeline"
            """

            // Commit & Push
            try {
                withCredentials([usernamePassword(credentialsId: "${GIT_CRED_ID}", usernameVariable: 'GIT_USERNAME', passwordVariable: 'GIT_PASSWORD')]) {
                    sh """
                        git add ${targetFolder}/values.yaml
                        git commit -m "ci: update ${appName} ${envName} image to tag ${imageTag}"
                        git push https://${GIT_USERNAME}:${GIT_PASSWORD}@${GITOPS_REPO.replace('https://', '')} HEAD:${GITOPS_BRANCH}
                    """
                }
            } catch (Exception e) {
                echo "No changes to commit or push failed: ${e.message}"
            }
        } else {
            error "Folder ${targetFolder} not found in GitOps repo! Please generate manifest via WebUI first."
        }
    }
}