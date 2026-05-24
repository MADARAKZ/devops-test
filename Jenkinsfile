pipeline {
  agent { label 'docker-agent' }

  parameters {
    string(name: 'REGISTRY',     defaultValue: 'localhost:5000',           description: 'Docker registry host:port')
    string(name: 'IMAGE_NAME',   defaultValue: 'devops-demo-app',          description: 'Image name (without registry)')
    choice(name: 'DEPLOY_MODE',  choices: ['mock', 'helm'],                description: 'mock = print commands only; helm = real rollout')
    string(name: 'NAMESPACE',    defaultValue: 'devops-demo',              description: 'Kubernetes namespace')
    string(name: 'RELEASE',      defaultValue: 'devops-demo-app',          description: 'Helm release name')
    string(name: 'CHART_PATH',   defaultValue: 'helm/devops-demo-app',     description: 'Helm chart directory')
    string(name: 'APP_PORT',     defaultValue: '8080',                     description: 'Container port')
    booleanParam(name: 'PROD_APPROVAL', defaultValue: true,                description: 'Require manual approval for prod deploy')
  }

  options {
    timestamps()
    disableConcurrentBuilds()
    timeout(time: 30, unit: 'MINUTES')
    buildDiscarder(logRotator(numToKeepStr: '20'))
  }

  environment {
    APP_DIR   = 'app'
    IMAGE     = ''
    VERSION   = ''
    IS_PROD   = 'false'
  }

  stages {

    stage('Checkout') {
      steps {
        checkout scm
        script {
          def shortSha   = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
          def branch     = env.BRANCH_NAME ?: sh(script: 'git rev-parse --abbrev-ref HEAD', returnStdout: true).trim()
          env.VERSION    = "${env.BUILD_NUMBER}-${shortSha}"
          env.IMAGE      = "${params.REGISTRY}/${params.IMAGE_NAME}:${env.VERSION}"
          env.IS_PROD    = (branch == 'main' || branch == 'master') ? 'true' : 'false'
          echo "Branch=${branch} Version=${env.VERSION} Image=${env.IMAGE} IsProd=${env.IS_PROD}"
        }
      }
    }

    stage('Test') {
      parallel {
        stage('Unit Test') {
          steps {
            sh '''
              set -eu
              docker build --file "${APP_DIR}/Dockerfile" --target test \
                -t "${IMAGE_NAME}:test-${BUILD_NUMBER}" "${APP_DIR}"
            '''
          }
        }
        stage('Helm Lint') {
          steps {
            sh '''
              set -eu
              helm lint "${CHART_PATH}"
              helm template "${RELEASE}-lint" "${CHART_PATH}" > /dev/null
            '''
          }
        }
      }
    }

    stage('Docker Build') {
      steps {
        sh '''
          set -eu
          docker build --file "${APP_DIR}/Dockerfile" --target runtime \
            --label ci.build="${BUILD_NUMBER}" \
            --label ci.commit="$(git rev-parse --short HEAD)" \
            --build-arg APP_VERSION="${VERSION}" \
            -t "${IMAGE}" "${APP_DIR}"
        '''
      }
    }

    stage('Image Push') {
      steps {
        sh '''
          set -eu
          docker push "${IMAGE}"
        '''
      }
    }

    stage('Production Approval') {
      when {
        allOf {
          expression { return env.IS_PROD == 'true' }
          expression { return params.PROD_APPROVAL }
          expression { return params.DEPLOY_MODE == 'helm' }
        }
      }
      steps {
        input message: "Deploy ${env.IMAGE} to production?", ok: 'Deploy'
      }
    }

    stage('Deploy') {
      steps {
        script {
          def cmd = """\
helm upgrade --install ${params.RELEASE} ${params.CHART_PATH} \\
  --namespace ${params.NAMESPACE} \\
  --create-namespace \\
  --set image.repository=${params.REGISTRY}/${params.IMAGE_NAME} \\
  --set image.tag=${env.VERSION} \\
  --set config.data.PORT=${params.APP_PORT} \\
  --set deployment.strategy.type=RollingUpdate \\
  --set deployment.strategy.rollingUpdate.maxUnavailable=0 \\
  --set deployment.strategy.rollingUpdate.maxSurge=1
""".stripIndent()
          writeFile file: 'deploy-command.txt', text: cmd

          if (params.DEPLOY_MODE == 'helm') {
            sh cmd
            sh "kubectl rollout status deployment/${params.RELEASE} -n ${params.NAMESPACE} --timeout=180s"
          } else {
            echo "[mock] Would execute:\n${cmd}"
          }
        }
      }
    }

    stage('Smoke Test') {
      steps {
        script {
          if (params.DEPLOY_MODE != 'helm') {
            echo "[mock] Skipping smoke test (DEPLOY_MODE=${params.DEPLOY_MODE})."
            return
          }
          sh """
            set -eu
            for i in 1 2 3 4 5; do
              if kubectl exec deployment/${params.RELEASE} -n ${params.NAMESPACE} -- \\
                   wget -qO- http://localhost:${params.APP_PORT}/health \\
                   | tee smoke-test.log \\
                   | grep -q '"status":"ok"'; then
                echo "Smoke test passed on attempt \$i."
                exit 0
              fi
              echo "Attempt \$i failed; retrying in 5s..."
              sleep 5
            done
            echo "Smoke test failed."
            exit 1
          """
        }
      }
    }
  }

  post {
    success {
      echo "SUCCESS: ${env.IMAGE} deployed (mode=${params.DEPLOY_MODE})"
    }

    failure {
      script {
        echo 'FAILURE: attempting auto-rollback if applicable.'
        if (params.DEPLOY_MODE != 'helm') {
          echo "DEPLOY_MODE=${params.DEPLOY_MODE}; nothing to roll back."
          return
        }
        def revisions = sh(
          script: "helm history ${params.RELEASE} -n ${params.NAMESPACE} -o json 2>/dev/null | grep -c '\"revision\"' || true",
          returnStdout: true
        ).trim().toInteger()
        if (revisions < 2) {
          echo "Only ${revisions} revision(s) for ${params.RELEASE}; no rollback target."
          return
        }
        echo "Rolling back ${params.RELEASE} in namespace ${params.NAMESPACE}..."
        sh """
          set -eu
          helm rollback ${params.RELEASE} -n ${params.NAMESPACE}
          kubectl rollout status deployment/${params.RELEASE} -n ${params.NAMESPACE} --timeout=120s
          helm history ${params.RELEASE} -n ${params.NAMESPACE}
        """
      }
    }

    always {
      sh '''
        docker rmi "${IMAGE_NAME}:test-${BUILD_NUMBER}" >/dev/null 2>&1 || true
        docker image prune -f --filter label=ci.build="${BUILD_NUMBER}" >/dev/null 2>&1 || true
      '''
      archiveArtifacts artifacts: 'deploy-command.txt,smoke-test.log', allowEmptyArchive: true
    }
  }
}
