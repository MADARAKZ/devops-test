def sanitizeBranchName(String branch) {
  return (branch ?: 'detached')
    .replaceFirst(/^refs\/heads\//, '')
    .replaceAll(/[^A-Za-z0-9._-]+/, '-')
    .replaceAll(/^-+|-+$/, '')
}

def isProdBranch(String branch) {
  return branch in ['main', 'master']
}

def resolveStrategy(String branch, String tag, String buildNumber, String shortSha) {
  if (tag?.trim()) {
    return [
      targetEnv: 'prod',
      overlay: 'prod',
      imageTag: tag,
      pushImage: true,
      updateGitOps: true,
      requiresApproval: true,
      gitopsBranch: 'main'
    ]
  }

  if (isProdBranch(branch)) {
    return [
      targetEnv: 'prod',
      overlay: 'prod',
      imageTag: "prod-${buildNumber}-${shortSha}",
      pushImage: true,
      updateGitOps: true,
      requiresApproval: true,
      gitopsBranch: branch
    ]
  }

  if (branch in ['develop', 'dev']) {
    return [
      targetEnv: 'dev',
      overlay: 'dev',
      imageTag: "dev-${buildNumber}-${shortSha}",
      pushImage: true,
      updateGitOps: true,
      requiresApproval: false,
      gitopsBranch: branch
    ]
  }

  if (branch == 'staging' || branch?.startsWith('release/')) {
    return [
      targetEnv: 'staging',
      overlay: 'staging',
      imageTag: "rc-${buildNumber}-${shortSha}",
      pushImage: true,
      updateGitOps: true,
      requiresApproval: false,
      gitopsBranch: branch
    ]
  }

  if (branch?.startsWith('hotfix/')) {
    def hotfixName = sanitizeBranchName(branch.replaceFirst(/^hotfix\//, ''))
    return [
      targetEnv: 'prod',
      overlay: 'prod',
      imageTag: "hotfix-${hotfixName}-${buildNumber}-${shortSha}",
      pushImage: true,
      updateGitOps: true,
      requiresApproval: true,
      gitopsBranch: branch
    ]
  }

  return [
    targetEnv: 'feature',
    overlay: '',
    imageTag: "feat-${buildNumber}-${shortSha}",
    pushImage: false,
    updateGitOps: false,
    requiresApproval: false,
    gitopsBranch: branch
  ]
}

def resolveQualityGate(String appDir) {
  if (fileExists("${appDir}/package.json")) {
    return [
      image: 'node:20-slim',
      command: 'if [ -f package-lock.json ] || [ -f npm-shrinkwrap.json ]; then npm ci; else npm install; fi; npm run lint --if-present; npm test --if-present'
    ]
  }

  if (fileExists("${appDir}/pom.xml")) {
    return [
      image: 'maven:3.9-eclipse-temurin-21',
      command: 'mvn -B test'
    ]
  }

  if (fileExists("${appDir}/build.gradle") || fileExists("${appDir}/build.gradle.kts")) {
    return [
      image: 'gradle:8-jdk21',
      command: 'gradle test --no-daemon'
    ]
  }

  if (fileExists("${appDir}/go.mod")) {
    return [
      image: 'golang:1.23',
      command: 'go test ./...'
    ]
  }

  if (fileExists("${appDir}/requirements.txt") || fileExists("${appDir}/pyproject.toml")) {
    return [
      image: 'python:3.12-slim',
      command: 'python -m pip install --upgrade pip; if [ -f requirements.txt ]; then pip install -r requirements.txt; fi; python -m pytest'
    ]
  }

  return null
}

pipeline {
  agent { label 'docker-agent' }

  parameters {
    string(name: 'REGISTRY', defaultValue: 'localhost:5000', description: 'Docker registry host:port')
    string(name: 'IMAGE_NAME', defaultValue: 'devops-demo-app', description: 'Docker image name')
    string(name: 'APP_DIR', defaultValue: 'app', description: 'Application directory')
    string(name: 'CHART_PATH', defaultValue: 'helm/devops-demo-app', description: 'Helm chart path')
    string(name: 'GITOPS_DIR', defaultValue: 'gitops', description: 'GitOps overlays directory')
    string(name: 'DOCKER_CREDENTIALS_ID', defaultValue: 'docker-registry', description: 'Jenkins username/password credential for Docker registry')
    string(name: 'GIT_CREDENTIALS_ID', defaultValue: 'github-push', description: 'Jenkins username/password credential for Git push')
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
    CHART_PATH = "${params.CHART_PATH}"
    GITOPS_DIR = "${params.GITOPS_DIR}"
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
        script {
          env.SHORT_SHA = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
          env.SOURCE_BRANCH = env.CHANGE_BRANCH ?: env.BRANCH_NAME ?: sh(
            script: 'git rev-parse --abbrev-ref HEAD',
            returnStdout: true
          ).trim()
          env.SOURCE_TAG = env.TAG_NAME ?: ''

          def commitMessage = sh(script: 'git log -1 --pretty=%B', returnStdout: true).trim().toLowerCase()
          if (commitMessage.contains('[skip ci]') || commitMessage.contains('[ci skip]')) {
            env.SKIP_CI = 'true'
            currentBuild.result = 'NOT_BUILT'
            currentBuild.description = 'skipped by commit message'
            echo 'Commit message contains [skip ci] or [ci skip].'
          }
        }
      }
    }

    stage('Resolve Strategy') {
      when { expression { env.SKIP_CI != 'true' } }
      steps {
        script {
          def strategy = resolveStrategy(env.SOURCE_BRANCH, env.SOURCE_TAG, env.BUILD_NUMBER, env.SHORT_SHA)

          env.TARGET_ENV = strategy['targetEnv']
          env.OVERLAY = strategy['overlay']
          env.IMAGE_TAG = strategy['imageTag']
          env.IMAGE = "${params.REGISTRY}/${params.IMAGE_NAME}:${strategy['imageTag']}"
          env.DO_PUSH = strategy['pushImage'].toString()
          env.DO_GITOPS_UPDATE = strategy['updateGitOps'].toString()
          env.REQUIRE_APPROVAL = strategy['requiresApproval'].toString()
          env.GITOPS_TARGET_BRANCH = strategy['gitopsBranch']
          env.VALUES_FILE_PATH = strategy['overlay'] ? "${params.GITOPS_DIR}/${strategy['overlay']}/values.yaml" : ''
          env.DEPLOY_FAILED = 'false'
          env.GITOPS_COMMIT_CREATED = 'false'

          currentBuild.description = "${env.TARGET_ENV} ${env.IMAGE_TAG}"
          echo "Branch: ${env.SOURCE_BRANCH}"
          echo "Tag: ${env.SOURCE_TAG ?: '-'}"
          echo "Image: ${env.IMAGE}"
          echo "Overlay: ${env.OVERLAY ?: '-'}"
          echo "Push image: ${env.DO_PUSH}"
          echo "Update GitOps: ${env.DO_GITOPS_UPDATE}"
          echo "Approval required: ${env.REQUIRE_APPROVAL}"
        }
      }
    }

    stage('Quality Gates') {
      when { expression { env.SKIP_CI != 'true' } }
      parallel {
        stage('App Lint & Test') {
          steps {
            script {
              def gate = resolveQualityGate(params.APP_DIR)
              if (gate == null) {
                echo "No supported quality gate found in ${params.APP_DIR}; skipping app lint/test."
                return
              }

              withEnv([
                "QUALITY_IMAGE=${gate.image}",
                "QUALITY_COMMAND=${gate.command}"
              ]) {
                sh '''
                  set -eu
                  test -d "${APP_DIR}"
                  test_container="app-test-${BUILD_NUMBER}-${SHORT_SHA}"
                  docker rm -f "${test_container}" >/dev/null 2>&1 || true

                  docker create \
                    --name "${test_container}" \
                    -w /workspace \
                    "${QUALITY_IMAGE}" \
                    sh -ec "${QUALITY_COMMAND}"

                  trap 'docker rm -f "${test_container}" >/dev/null 2>&1 || true' EXIT
                  docker cp "${APP_DIR}/." "${test_container}:/workspace"
                  docker start -a "${test_container}"
                '''
              }
            }
          }
        }

        stage('Helm Lint') {
          steps {
            sh '''
              set -eu
              test -d "${CHART_PATH}"
              helm lint "${CHART_PATH}"
              helm template lint-check "${CHART_PATH}" > /dev/null
            '''
          }
        }

        stage('Kustomize Render') {
          steps {
            sh '''
              set -eu
              test -d "${GITOPS_DIR}"

              rendered=0
              for overlay in dev staging prod; do
                path="${GITOPS_DIR}/${overlay}"
                if [ -d "${path}" ]; then
                  kubectl kustomize --enable-helm "${path}" > /dev/null
                  rendered=$((rendered + 1))
                fi
              done

              test "${rendered}" -gt 0
            '''
          }
        }
      }
    }

    stage('Build Image') {
      when { expression { env.SKIP_CI != 'true' } }
      steps {
        sh '''
          set -eu
          docker build \
            --file "${APP_DIR}/Dockerfile" \
            --label ci.build="${BUILD_NUMBER}" \
            --label ci.commit="${SHORT_SHA}" \
            --label ci.target="${TARGET_ENV}" \
            --build-arg APP_VERSION="${IMAGE_TAG}" \
            --tag "${IMAGE}" \
            "${APP_DIR}"
        '''
      }
    }

    stage('Scan Image if needed') {
      when { expression { env.SKIP_CI != 'true' } }
      steps {
        sh '''
          set -eu
          if command -v trivy >/dev/null 2>&1; then
            trivy image --exit-code 1 --severity HIGH,CRITICAL "${IMAGE}"
          else
            echo "trivy not installed; skipping image scan"
          fi
        '''
      }
    }

    stage('Push Image') {
      when {
        allOf {
          expression { env.SKIP_CI != 'true' }
          expression { env.DO_PUSH == 'true' }
        }
      }
      steps {
        withCredentials([usernamePassword(
          credentialsId: params.DOCKER_CREDENTIALS_ID,
          usernameVariable: 'DOCKER_USERNAME',
          passwordVariable: 'DOCKER_PASSWORD'
        )]) {
          sh '''
            set -eu
            printf '%s' "${DOCKER_PASSWORD}" | docker login "${REGISTRY}" \
              --username "${DOCKER_USERNAME}" \
              --password-stdin
            docker push "${IMAGE}"
          '''
        }
      }
    }

    stage('Manual Approval') {
      when {
        allOf {
          expression { env.SKIP_CI != 'true' }
          expression { env.DO_GITOPS_UPDATE == 'true' }
          expression { env.REQUIRE_APPROVAL == 'true' }
        }
      }
      steps {
        input message: "Promote ${env.IMAGE} to ${env.TARGET_ENV}?", ok: 'Promote'
      }
    }

    stage('Update GitOps') {
      when {
        allOf {
          expression { env.SKIP_CI != 'true' }
          expression { env.DO_GITOPS_UPDATE == 'true' }
        }
      }
      steps {
        withCredentials([usernamePassword(
          credentialsId: params.GIT_CREDENTIALS_ID,
          usernameVariable: 'GIT_USERNAME',
          passwordVariable: 'GIT_PASSWORD'
        )]) {
          sh '''
            set -eu
            test -n "${GITOPS_TARGET_BRANCH}"
            test -n "${VALUES_FILE_PATH}"

            auth_header="$(printf '%s:%s' "${GIT_USERNAME}" "${GIT_PASSWORD}" | base64 | tr -d '\n')"
            git -c http.extraHeader="Authorization: Basic ${auth_header}" fetch origin "${GITOPS_TARGET_BRANCH}"
            git checkout -B "${GITOPS_TARGET_BRANCH}" FETCH_HEAD

            test -f "${VALUES_FILE_PATH}"
            image_repository="${REGISTRY}/${IMAGE_NAME}"

            if command -v yq >/dev/null 2>&1; then
              IMAGE_REPOSITORY="${image_repository}" yq -i \
                '.image.repository = strenv(IMAGE_REPOSITORY) | .image.tag = strenv(IMAGE_TAG)' \
                "${VALUES_FILE_PATH}"
            else
              tmp_file="$(mktemp)"
              awk -v repository="${image_repository}" -v tag="${IMAGE_TAG}" '
                /^image:[[:space:]]*$/ {
                  in_image = 1
                  print
                  next
                }
                in_image && /^[^[:space:]]/ {
                  in_image = 0
                }
                in_image && /^[[:space:]]+repository:/ {
                  sub(/repository:.*/, "repository: " repository)
                  print
                  next
                }
                in_image && /^[[:space:]]+tag:/ {
                  sub(/tag:.*/, "tag: " tag)
                  print
                  next
                }
                { print }
              ' "${VALUES_FILE_PATH}" > "${tmp_file}"
              mv "${tmp_file}" "${VALUES_FILE_PATH}"
            fi

            git diff -- "${VALUES_FILE_PATH}"
          '''
        }
      }
    }

    stage('Commit GitOps') {
      when {
        allOf {
          expression { env.SKIP_CI != 'true' }
          expression { env.DO_GITOPS_UPDATE == 'true' }
        }
      }
      steps {
        withCredentials([usernamePassword(
          credentialsId: params.GIT_CREDENTIALS_ID,
          usernameVariable: 'GIT_USERNAME',
          passwordVariable: 'GIT_PASSWORD'
        )]) {
          script {
            if (sh(returnStatus: true, script: 'git diff --quiet -- "${VALUES_FILE_PATH}"') == 0) {
              echo 'No GitOps change to commit.'
              return
            }

            sh '''
              set -eu
              git config user.name "jenkins-ci"
              git config user.email "jenkins-ci@local"
              git add "${VALUES_FILE_PATH}"
              git commit -m "ci(${OVERLAY}): bump ${IMAGE_NAME} to ${IMAGE_TAG} [skip ci]"

              auth_header="$(printf '%s:%s' "${GIT_USERNAME}" "${GIT_PASSWORD}" | base64 | tr -d '\n')"
              git -c http.extraHeader="Authorization: Basic ${auth_header}" pull --rebase origin "${GITOPS_TARGET_BRANCH}"
            '''

            env.GITOPS_COMMIT = sh(script: 'git rev-parse HEAD', returnStdout: true).trim()
            env.GITOPS_COMMIT_CREATED = 'true'

            sh '''
              set -eu
              auth_header="$(printf '%s:%s' "${GIT_USERNAME}" "${GIT_PASSWORD}" | base64 | tr -d '\n')"
              git -c http.extraHeader="Authorization: Basic ${auth_header}" push origin "HEAD:refs/heads/${GITOPS_TARGET_BRANCH}"
            '''
          }
        }
      }
    }

    stage('Verify Deployment') {
      when {
        allOf {
          expression { env.SKIP_CI != 'true' }
          expression { env.DO_GITOPS_UPDATE == 'true' }
          expression { env.GITOPS_COMMIT_CREATED == 'true' }
        }
      }
      steps {
        script {
          def status = sh(
            returnStatus: true,
            script: '''
              set -eu
              if ! command -v kubectl >/dev/null 2>&1; then
                echo "kubectl not installed; skipping deployment verification"
                exit 0
              fi

              namespace="${OVERLAY}"
              if ! kubectl -n "${namespace}" get deploy "${IMAGE_NAME}" >/dev/null 2>&1; then
                namespace="default"
              fi

              if ! kubectl -n "${namespace}" get deploy "${IMAGE_NAME}" >/dev/null 2>&1; then
                echo "No deployment found for ${IMAGE_NAME}; skipping rollout verification"
                exit 0
              fi

              kubectl -n "${namespace}" rollout status "deployment/${IMAGE_NAME}" --timeout=180s
            '''
          )

          if (status != 0) {
            env.DEPLOY_FAILED = 'true'
            currentBuild.result = 'UNSTABLE'
            echo 'Deployment verification failed. Manual rollback stage will run.'
          }
        }
      }
    }

    stage('Manual Rollback') {
      when {
        allOf {
          expression { env.SKIP_CI != 'true' }
          expression { env.DO_GITOPS_UPDATE == 'true' }
          expression { env.GITOPS_COMMIT_CREATED == 'true' }
          expression { env.DEPLOY_FAILED == 'true' }
        }
      }
      steps {
        input message: "Deployment failed. Roll back ${env.OVERLAY} to the previous image tag?", ok: 'Rollback'
      }
    }

    stage('Rollback GitOps') {
      when {
        allOf {
          expression { env.SKIP_CI != 'true' }
          expression { env.DO_GITOPS_UPDATE == 'true' }
          expression { env.GITOPS_COMMIT_CREATED == 'true' }
          expression { env.DEPLOY_FAILED == 'true' }
        }
      }
      steps {
        withCredentials([usernamePassword(
          credentialsId: params.GIT_CREDENTIALS_ID,
          usernameVariable: 'GIT_USERNAME',
          passwordVariable: 'GIT_PASSWORD'
        )]) {
          sh '''
            set -eu
            git config user.name "jenkins-ci"
            git config user.email "jenkins-ci@local"

            auth_header="$(printf '%s:%s' "${GIT_USERNAME}" "${GIT_PASSWORD}" | base64 | tr -d '\n')"
            git -c http.extraHeader="Authorization: Basic ${auth_header}" fetch origin "${GITOPS_TARGET_BRANCH}"
            git checkout -B "${GITOPS_TARGET_BRANCH}" FETCH_HEAD
            git revert --no-commit "${GITOPS_COMMIT}"

            if git diff --quiet -- "${VALUES_FILE_PATH}"; then
              echo "No rollback change to commit."
              exit 0
            fi

            git add "${VALUES_FILE_PATH}"
            git commit -m "ci(${OVERLAY}): rollback ${IMAGE_NAME} after failed deploy [skip ci]"
            git -c http.extraHeader="Authorization: Basic ${auth_header}" pull --rebase origin "${GITOPS_TARGET_BRANCH}"
            git -c http.extraHeader="Authorization: Basic ${auth_header}" push origin "HEAD:refs/heads/${GITOPS_TARGET_BRANCH}"
          '''
        }
      }
    }

  }

  post {
    always {
      sh '''
        set +e
        docker logout "${REGISTRY}" >/dev/null 2>&1
        docker image prune -f --filter "label=ci.build=${BUILD_NUMBER}" >/dev/null 2>&1
        rm -rf .jenkins-app-test
      '''
    }
  }
}
