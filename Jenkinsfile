pipeline {
  agent { label 'docker-agent' }
  parameters {
    string(name: 'REGISTRY', defaultValue: 'localhost:5000', description: 'Docker registry host:port')
    string(name: 'IMAGE_NAME', defaultValue: 'devops-demo-app', description: 'Image name')
    string(name: 'APP_DIR', defaultValue: 'app', description: 'Source directory mounted into the test container')
    string(name: 'DOCKERFILE', defaultValue: 'app/Dockerfile', description: 'Path to Dockerfile (relative to repo root)')
    string(name: 'DOCKER_TARGET', defaultValue: 'runtime', description: 'docker build --target')
    string(name: 'BUILD_CONTEXT_DIR', defaultValue: 'app', description: 'docker build context directory')
    string(name: 'TEST_IMAGE', defaultValue: 'node:20-slim', description: 'Container image used for App Lint & Test')
    text(name: 'TEST_SCRIPT', defaultValue: '''set -eu
cp -a /src/. /app/
test -f package-lock.json
npm ci
npm run lint
npm test
''', description: 'Shell script run inside TEST_IMAGE. Empty = skip stage.')
    string(name: 'HELM_CHART', defaultValue: 'helm/devops-demo-app', description: 'Helm chart dir. Empty = skip Helm Lint.')
    string(name: 'KUSTOMIZE_OVERLAYS', defaultValue: 'dev staging prod', description: 'Space-separated overlay names. Empty = skip Kustomize Build.')
    string(name: 'GITOPS_DIR', defaultValue: 'gitops', description: 'GitOps overlays root. Empty = skip bump+push stages.')
    string(name: 'VALUES_FILE', defaultValue: 'values.yaml', description: 'File under ${GITOPS_DIR}/${OVERLAY}/ to bump')
    string(name: 'PROD_BRANCHES', defaultValue: 'main,master', description: 'CSV of branch names that build for prod')
    string(name: 'STAGING_BRANCH', defaultValue: 'staging', description: 'Branch that builds for staging')
    string(name: 'DEV_BRANCH', defaultValue: 'develop', description: 'Branch that builds for dev')
    string(name: 'GIT_USER_NAME', defaultValue: 'jenkins-ci', description: 'GitOps commit author name')
    string(name: 'GIT_USER_EMAIL', defaultValue: 'jenkins@local', description: 'GitOps commit author email')
    string(name: 'GIT_CREDENTIALS_ID', defaultValue: 'github-push', description: 'Jenkins credential: GitHub user + PAT')
  }

  options {
    timestamps()
    disableConcurrentBuilds()
    timeout(time: 30, unit: 'MINUTES')
    buildDiscarder(logRotator(numToKeepStr: '20'))
  }

  environment {
    REGISTRY = "${params.REGISTRY}"
    IMAGE_NAME = "${params.IMAGE_NAME}"
    APP_DIR = "${params.APP_DIR}"
    DOCKERFILE = "${params.DOCKERFILE}"
    DOCKER_TARGET = "${params.DOCKER_TARGET}"
    BUILD_CONTEXT_DIR = "${params.BUILD_CONTEXT_DIR}"
    TEST_IMAGE = "${params.TEST_IMAGE}"
    HELM_CHART = "${params.HELM_CHART}"
    KUSTOMIZE_OVERLAYS = "${params.KUSTOMIZE_OVERLAYS}"
    GITOPS_DIR = "${params.GITOPS_DIR}"
    VALUES_FILE = "${params.VALUES_FILE}"
    SKIP = 'false'
  }

  stages {
    stage('Checkout & Resolve Strategy') {
      steps {
        checkout scm
        script {
          def shortSha = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
          def commitMsg = sh(script: 'git log -1 --pretty=%B', returnStdout: true).trim()
          def branch = env.BRANCH_NAME ?: sh(script: 'git rev-parse --abbrev-ref HEAD', returnStdout: true).trim()
          def tag = env.TAG_NAME
          def skipCi = commitMsg.contains('[skip ci]') || commitMsg.contains('[ci skip]')

          if (skipCi) {
            env.SKIP = 'true'
            currentBuild.result = 'NOT_BUILT'
            currentBuild.description = 'skipped [skip ci]'
            echo 'Commit is marked [skip ci] — skipping CI stages.'
            return
          }

          def prodBranches = params.PROD_BRANCHES.split(',').collect { it.trim() }.findAll { it }

          def cfg
          if (tag) {
            cfg = [target: 'prod', push: true, bump: true, approval: true, overlay: 'prod', version: tag]
          } else if (prodBranches.contains(branch)) {
            cfg = [target: 'prod', push: true, bump: true, approval: true, overlay: 'prod', version: "prod-${env.BUILD_NUMBER}-${shortSha}"]
          } else if (branch == params.STAGING_BRANCH) {
            cfg = [target: 'staging', push: true, bump: true, approval: false, overlay: 'staging', version: "rc-${env.BUILD_NUMBER}-${shortSha}"]
          } else if (branch == params.DEV_BRANCH) {
            cfg = [target: 'dev', push: true, bump: true, approval: false, overlay: 'dev', version: "dev-${env.BUILD_NUMBER}-${shortSha}"]
          } else if (branch.startsWith('release/')) {
            def rc = branch.replaceFirst('release/', '').replaceAll('[^A-Za-z0-9._-]', '-')
            cfg = [target: 'release', push: true, bump: false, approval: false, overlay: null, version: "rc-${rc}-${shortSha}"]
          } else if (branch.startsWith('hotfix/')) {
            def hf = branch.replaceFirst('hotfix/', '').replaceAll('[^A-Za-z0-9._-]', '-')
            cfg = [target: 'hotfix', push: true, bump: false, approval: false, overlay: null, version: "hotfix-${hf}-${shortSha}"]
          } else {
            cfg = [target: 'feature', push: false, bump: false, approval: false, overlay: null, version: "feat-${env.BUILD_NUMBER}-${shortSha}"]
          }

          env.TARGET_ENV = cfg.target
          env.DO_PUSH = cfg.push.toString()
          env.DO_BUMP = cfg.bump.toString()
          env.REQUIRE_APPROVAL = cfg.approval.toString()
          env.OVERLAY = cfg.overlay ?: ''
          env.VERSION = cfg.version
          env.IMAGE = "${env.REGISTRY}/${env.IMAGE_NAME}:${cfg.version}"
          env.GIT_BRANCH_NAME = branch

          echo "--- Strategy ---"
          echo "Branch=${branch}  Tag=${tag ?: '-'}  Target=${cfg.target}  Overlay=${cfg.overlay ?: '-'}"
          echo "Image=${env.IMAGE}"
          echo "Push=${cfg.push}  Bump=${cfg.bump}  Approval=${cfg.approval}"
          currentBuild.description = "${cfg.target} ${env.VERSION}"
        }
      }
    }

    stage('Test') {
      when { expression { env.SKIP != 'true' } }
      parallel {
        stage('App Lint & Test') {
          when { expression { params.TEST_SCRIPT?.trim() } }
          steps {
            retry(2) {
              script {
                writeFile file: '.ci-test.sh', text: params.TEST_SCRIPT
                sh '''
                  set -eu
                  docker run --rm \
                    -v "$PWD/${APP_DIR}:/src:ro" \
                    -v "$PWD/.ci-test.sh:/test.sh:ro" \
                    -w /app \
                    "${TEST_IMAGE}" sh /test.sh
                '''
              }
            }
          }
        }
        stage('Helm Lint') {
          when { expression { env.HELM_CHART?.trim() } }
          steps {
            sh '''
              set -eu
              helm lint "${HELM_CHART}"
              helm template lint-check "${HELM_CHART}" > /dev/null
            '''
          }
        }
        stage('Kustomize Build') {
          when {
            allOf {
              expression { env.KUSTOMIZE_OVERLAYS?.trim() }
              expression { env.GITOPS_DIR?.trim() }
            }
          }
          steps {
            sh '''
              set -eu
              kubectl version --client=true >/dev/null
              for overlay in ${KUSTOMIZE_OVERLAYS}; do
                echo "--- Rendering ${GITOPS_DIR}/${overlay} ---"
                kubectl kustomize --enable-helm "${GITOPS_DIR}/${overlay}" > /dev/null
              done
            '''
          }
        }
      }
    }

    stage('Docker Build') {
      when { expression { env.SKIP != 'true' } }
      steps {
        retry(2) {
          sh '''
            set -eu
            docker build --file "${DOCKERFILE}" --target "${DOCKER_TARGET}" \
              --label ci.build="${BUILD_NUMBER}" \
              --label ci.commit="$(git rev-parse --short HEAD)" \
              --label ci.target="${TARGET_ENV}" \
              --build-arg APP_VERSION="${VERSION}" \
              -t "${IMAGE}" "${BUILD_CONTEXT_DIR}"
          '''
        }
      }
    }

    stage('Image Push') {
      when {
        allOf {
          expression { env.SKIP != 'true' }
          expression { env.DO_PUSH == 'true' }
        }
      }
      steps {
        retry(2) {
          sh 'docker push "${IMAGE}"'
        }
      }
    }

    stage('Production Approval') {
      when {
        allOf {
          expression { env.SKIP != 'true' }
          expression { env.DO_BUMP == 'true' }
          expression { env.REQUIRE_APPROVAL == 'true' }
        }
      }
      steps {
        input message: "Promote ${env.IMAGE} to ${env.OVERLAY}?", ok: 'Promote'
      }
    }

    stage('Bump GitOps Image Tag') {
      when {
        allOf {
          expression { env.SKIP != 'true' }
          expression { env.DO_BUMP == 'true' }
          expression { env.GITOPS_DIR?.trim() }
        }
      }
      steps {
        script {
          def valuesFile = "${env.GITOPS_DIR}/${env.OVERLAY}/${env.VALUES_FILE}"
          sh """
            set -eu
            test -f "${valuesFile}"
            tmp=\$(mktemp)
            awk -v repo="${env.REGISTRY}/${env.IMAGE_NAME}" -v tag="${env.VERSION}" '
              BEGIN { in_image=0 }
              /^image:/ { in_image=1; print; next }
              in_image && /^  repository:/ { print "  repository: " repo; next }
              in_image && /^  tag:/ { print "  tag: " tag; next }
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
          expression { env.SKIP != 'true' }
          expression { env.DO_BUMP == 'true' }
          expression { env.GITOPS_DIR?.trim() }
        }
      }
      steps {
        withCredentials([usernamePassword(credentialsId: "${params.GIT_CREDENTIALS_ID}",
                                          usernameVariable: 'GIT_USER',
                                          passwordVariable: 'GIT_TOKEN')]) {
          sh '''
            set -eu
            git config user.name "${GIT_USER_NAME}"
            git config user.email "${GIT_USER_EMAIL}"

            target="${GITOPS_DIR}/${OVERLAY}/${VALUES_FILE}"
            if git diff --quiet -- "${target}"; then
              echo "No change in ${target} — nothing to commit."
              exit 0
            fi

            git add "${target}"
            git commit -m "ci(${OVERLAY}): bump ${IMAGE_NAME} to ${VERSION}"

            remote_url=$(git config --get remote.origin.url)
            push_url=$(echo "$remote_url" | sed -E "s#https://#https://${GIT_USER}:${GIT_TOKEN}@#")
            gitops_branch="gitops/${OVERLAY}"

            if git ls-remote --exit-code --heads "$push_url" "$gitops_branch" >/dev/null 2>&1; then
              git push --force-with-lease "$push_url" "HEAD:${gitops_branch}"
            else
              git push "$push_url" "HEAD:${gitops_branch}"
            fi
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
