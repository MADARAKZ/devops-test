#!/usr/bin/env bash
set -euo pipefail

JOB_NAME="${JOB_NAME:-devops-case-study}"
JENKINS_URL="${JENKINS_URL:-http://localhost:8080}"
JENKINS_USER="${JENKINS_USER:-admin}"
JENKINS_PASSWORD="${JENKINS_PASSWORD:-admin123}"
REPO_URL="${1:-}"
BRANCH="${2:-main}"
POLL_SCHEDULE="${POLL_SCHEDULE:-H/2 * * * *}"

if [ -z "${REPO_URL}" ]; then
  echo "Usage: $0 <github-repo-url> [branch]"
  echo "Example: $0 https://github.com/your-user/devops-case-study.git main"
  exit 1
fi

CONFIG_FILE="$(mktemp)"
COOKIE_FILE="$(mktemp)"
trap 'rm -f "${CONFIG_FILE}" "${COOKIE_FILE}"' EXIT

CRUMB_HEADER="$(curl -fsS -u "${JENKINS_USER}:${JENKINS_PASSWORD}" \
  -c "${COOKIE_FILE}" \
  "${JENKINS_URL}/crumbIssuer/api/xml?xpath=concat(//crumbRequestField,\":\",//crumb)")"

cat > "${CONFIG_FILE}" <<XML
<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="workflow-job">
  <actions/>
  <description>Pipeline created for DevOps case study. Polls GitHub and runs Jenkinsfile on docker-agent.</description>
  <keepDependencies>false</keepDependencies>
  <properties/>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition" plugin="workflow-cps">
    <scm class="hudson.plugins.git.GitSCM" plugin="git">
      <configVersion>2</configVersion>
      <userRemoteConfigs>
        <hudson.plugins.git.UserRemoteConfig>
          <url>${REPO_URL}</url>
        </hudson.plugins.git.UserRemoteConfig>
      </userRemoteConfigs>
      <branches>
        <hudson.plugins.git.BranchSpec>
          <name>*/${BRANCH}</name>
        </hudson.plugins.git.BranchSpec>
      </branches>
      <doGenerateSubmoduleConfigurations>false</doGenerateSubmoduleConfigurations>
      <submoduleCfg class="empty-list"/>
      <extensions/>
    </scm>
    <scriptPath>Jenkinsfile</scriptPath>
    <lightweight>true</lightweight>
  </definition>
  <triggers>
    <hudson.triggers.SCMTrigger>
      <spec>${POLL_SCHEDULE}</spec>
      <ignorePostCommitHooks>false</ignorePostCommitHooks>
    </hudson.triggers.SCMTrigger>
  </triggers>
  <disabled>false</disabled>
</flow-definition>
XML

if curl -fsS -u "${JENKINS_USER}:${JENKINS_PASSWORD}" \
  -b "${COOKIE_FILE}" \
  "${JENKINS_URL}/job/${JOB_NAME}/api/json" >/dev/null 2>&1; then
  curl -fsS -u "${JENKINS_USER}:${JENKINS_PASSWORD}" \
    -b "${COOKIE_FILE}" \
    -H "${CRUMB_HEADER}" \
    -H "Content-Type: application/xml" \
    --data-binary "@${CONFIG_FILE}" \
    "${JENKINS_URL}/job/${JOB_NAME}/config.xml" >/dev/null
  echo "Updated Jenkins job: ${JOB_NAME}"
else
  curl -fsS -u "${JENKINS_USER}:${JENKINS_PASSWORD}" \
    -b "${COOKIE_FILE}" \
    -H "${CRUMB_HEADER}" \
    -H "Content-Type: application/xml" \
    --data-binary "@${CONFIG_FILE}" \
    "${JENKINS_URL}/createItem?name=${JOB_NAME}" >/dev/null
  echo "Created Jenkins job: ${JOB_NAME}"
fi

echo "Repository: ${REPO_URL}"
echo "Branch: ${BRANCH}"
echo "Poll SCM: ${POLL_SCHEDULE}"
echo "Open: ${JENKINS_URL}/job/${JOB_NAME}/"
