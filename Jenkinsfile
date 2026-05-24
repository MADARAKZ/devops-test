pipeline {
  agent { label 'docker-agent' }

  parameters {
    string(name: 'REGISTRY',     defaultValue: 'localhost:5000',           description: 'Docker registry host:port')
    string(name: 'IMAGE_NAME',   defaultValue: 'devops-demo-app',          description: 'Image name (without registry)')
    string(name: 'CHART_PATH',   defaultValue: 'helm/devops-demo-app',     description: 'Helm chart directory')
    string(name: 'GITOPS_DIR',   defaultValue: 'gitops',                   description: 'Root of GitOps overlays')
    string(name: 'GIT_USER_NAME',  defaultValue: 'jenkins-ci',             description: 'Author name for GitOps commits')
    string(name: 'GIT_USER_EMAIL', defaultValue: 'jenkins@local',          description: 'Author email for GitOps commits')
    string(name: 'GIT_CREDENTIALS_ID', defaultValue: 'github-push',        description: 'Jenkins credential ID with GitHub username + PAT')
  }

  options {
    timestamps()
    disableConcurrentBuilds()
    timeout(time: 30, unit: 'MINUTES')
    buildDiscarder(logRotator(numToKeepStr: '20'))
  }

  environment {
    APP_DIR     = 'app'
    REGISTRY    = "${params.REGISTRY}"
    IMAGE_NAME  = "${params.IMAGE_NAME}"
    CHART_PATH  = "${params.CHART_PATH}"
    GITOPS_DIR  = "${params.GITOPS_DIR}"
  }

  stages {

    stage('Checkout & Resolve Strategy') {
      steps {
        checkout scm
        script {
          def shortSha   = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
          def commitMsg  = sh(script: 'git log -1 --pretty=%B', returnStdout: true).trim()
          def branch     = env.BRANCH_NAME ?: sh(script: 'git rev-parse --abbrev-ref HEAD', returnStdout: true).trim()
          def tag        = env.TAG_NAME
          def skipCi     = commitMsg.contains('[skip ci]') || commitMsg.contains('[ci skip]')

          if (skipCi) {
            currentBuild.result = 'NOT_BUILT'
            currentBuild.description = 'skipped [skip ci]'
            echo 'Commit is marked [skip ci] — skipping CI stages.'
            return
          }

          def cfg
          if (tag) {
            cfg = [target:'prod', push:true, bump:true, approval:true, overlay:'prod', version: tag]
          } else if (branch == 'main' || branch == 'master') {
            cfg = [target:'prod', push:true, bump:true, approval:true, overlay:'prod',
                   version: "prod-${env.BUILD_NUMBER}-${shortSha}"]
          } else if (branch == 'staging') {
            cfg = [target:'staging', push:true, bump:true, approval:false, overlay:'staging',
                   version: "rc-${env.BUILD_NUMBER}-${shortSha}"]
          } else if (branch == 'develop') {
            cfg = [target:'dev', push:true, bump:true, approval:false, overlay:'dev',
                   version: "dev-${env.BUILD_NUMBER}-${shortSha}"]
          } else if (branch.startsWith('release/')) {
            def rc = branch.replaceFirst('release/', '').replaceAll('[^A-Za-z0-9._-]', '-')
            cfg = [target:'release', push:true, bump:false, approval:false, overlay:null,
                   version: "rc-${rc}-${shortSha}"]
          } else if (branch.startsWith('hotfix/')) {
            def hf = branch.replaceFirst('hotfix/', '').replaceAll('[^A-Za-z0-9._-]', '-')
            cfg = [target:'hotfix', push:true, bump:false, approval:false, overlay:null,
                   version: "hotfix-${hf}-${shortSha}"]
          } else {
            cfg = [target:'feature', push:false, bump:false, approval:false, overlay:null,
                   version: "feat-${env.BUILD_NUMBER}-${shortSha}"]
          }

          env.TARGET_ENV       = cfg.target
          env.DO_PUSH          = cfg.push.toString()
          env.DO_BUMP          = cfg.bump.toString()
          env.REQUIRE_APPROVAL = cfg.approval.toString()
          env.OVERLAY          = cfg.overlay ?: ''
          env.VERSION          = cfg.version
          env.IMAGE            = "${env.REGISTRY}/${env.IMAGE_NAME}:${cfg.version}"
          env.GIT_BRANCH_NAME  = branch

          echo "--- Strategy ---"
          echo "Branch=${branch}  Tag=${tag ?: '-'}  Target=${cfg.target}  Overlay=${cfg.overlay ?: '-'}"
          echo "Image=${env.IMAGE}"
          echo "Push=${cfg.push}  Bump=${cfg.bump}  Approval=${cfg.approval}"
          currentBuild.description = "${cfg.target} ${env.VERSION}"
        }
      }
    }

    stage('Test') {
      when { expression { currentBuild.result != 'NOT_BUILT' } }
      parallel {
        stage('App Lint & Test') {
          steps {
            retry(2) {
              sh '''
                set -eu
                docker run --rm \
                  -v "$PWD/${APP_DIR}:/workspace:ro" \
                  -w /tmp/app \
                  node:20-slim \
                  sh -c 'cp -a /workspace/. . && npm ci && npm run lint && npm test'
              '''
            }
          }
        }
        stage('Helm Lint') {
          steps {
            sh '''
              set -eu
              helm lint "${CHART_PATH}"
              helm template lint-check "${CHART_PATH}" > /dev/null
            '''
          }
        }
        stage('Kustomize Build') {
          steps {
            sh '''
              set -eu
              kubectl version --client=true >/dev/null
              for overlay in dev staging prod; do
                echo "--- Rendering ${GITOPS_DIR}/${overlay} ---"
                kubectl kustomize --enable-helm "${GITOPS_DIR}/${overlay}" > /dev/null
              done
            '''
          }
        }
      }
    }

    stage('Docker Build') {
      when { expression { currentBuild.result != 'NOT_BUILT' } }
      steps {
        retry(2) {
          sh '''
            set -eu
            docker build --file "${APP_DIR}/Dockerfile" --target runtime \
              --label ci.build="${BUILD_NUMBER}" \
              --label ci.commit="$(git rev-parse --short HEAD)" \
              --label ci.target="${TARGET_ENV}" \
              --build-arg APP_VERSION="${VERSION}" \
              -t "${IMAGE}" "${APP_DIR}"
          '''
        }
      }
    }

    stage('Image Push') {
      when {
        allOf {
          expression { currentBuild.result != 'NOT_BUILT' }
          expression { env.DO_PUSH == 'true' }
        }
      }
      steps {
        retry(2) {
          sh '''
            set -eu
            docker push "${IMAGE}"
          '''
        }
      }
    }

    stage('Production Approval') {
      when {
        allOf {
          expression { env.DO_BUMP == 'true' }
          expression { env.REQUIRE_APPROVAL == 'true' }
          expression { currentBuild.result != 'NOT_BUILT' }
        }
      }
      steps {
        input message: "Promote ${env.IMAGE} to ${env.OVERLAY}?", ok: 'Promote'
      }
    }

    stage('Bump GitOps Image Tag') {
      when {
        allOf {
          expression { currentBuild.result != 'NOT_BUILT' }
          expression { env.DO_BUMP == 'true' }
        }
      }
      steps {
        script {
          def valuesFile = "${env.GITOPS_DIR}/${env.OVERLAY}/values.yaml"
          sh """
            set -eu
            test -f "${valuesFile}"
            tmp=\$(mktemp)
            awk -v repo="${env.REGISTRY}/${env.IMAGE_NAME}" -v tag="${env.VERSION}" '
              BEGIN { in_image=0 }
              /^image:/ { in_image=1; print; next }
              in_image && /^  repository:/ { print "  repository: " repo; next }
              in_image && /^  tag:/         { print "  tag: " tag; next }
              in_image && /^[^ ]/ { in_image=0 }
              { print }
            ' "${valuesFile}" > "\$tmp"
            mv "\$tmp" "${valuesFile}"
            echo "--- New ${valuesFile} ---"
            sed -n '1,20p' "${valuesFile}"
          """
        }
      }
    }

    stage('Commit & Push GitOps') {
      when {
        allOf {
          expression { currentBuild.result != 'NOT_BUILT' }
          expression { env.DO_BUMP == 'true' }
        }
      }
      steps {
        withCredentials([usernamePassword(credentialsId: "${params.GIT_CREDENTIALS_ID}",
                                          usernameVariable: 'GIT_USER',
                                          passwordVariable: 'GIT_TOKEN')]) {
          sh '''
            set -eu
            git config user.name  "${GIT_USER_NAME}"
            git config user.email "${GIT_USER_EMAIL}"

            if git diff --quiet -- "${GITOPS_DIR}/${OVERLAY}/values.yaml"; then
              echo "No change in ${GITOPS_DIR}/${OVERLAY}/values.yaml — nothing to commit."
              exit 0
            fi

            git add "${GITOPS_DIR}/${OVERLAY}/values.yaml"
            git commit -m "ci(${OVERLAY}): bump ${IMAGE_NAME} to ${VERSION} [skip ci]"

            remote_url=$(git config --get remote.origin.url)
            push_url=$(echo "$remote_url" | sed -E "s#https://#https://${GIT_USER}:${GIT_TOKEN}@#")
            git fetch origin "${GIT_BRANCH_NAME}"
            git rebase "origin/${GIT_BRANCH_NAME}"
            git push "$push_url" "HEAD:${GIT_BRANCH_NAME}"
          '''
        }
      }
    }
  }

  post {
    success {
      echo "SUCCESS [${env.TARGET_ENV}] image=${env.IMAGE} push=${env.DO_PUSH} bump=${env.DO_BUMP}"
    }
    failure {
      echo "FAILURE [${env.TARGET_ENV}] version=${env.VERSION}"
    }
    always {
      sh '''
        if [ -n "${BUILD_NUMBER:-}" ]; then
          docker image prune -f --filter "label=ci.build=${BUILD_NUMBER}" >/dev/null 2>&1 || true
        fi
      '''
    }
  }
}
