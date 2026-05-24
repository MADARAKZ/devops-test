FROM jenkins/ssh-agent:jdk17

USER root

ARG JENKINS_AGENT_SSH_PUBKEY
ARG KUBECTL_VERSION=v1.30.6
ARG HELM_VERSION=v3.19.4
ENV JENKINS_AGENT_SSH_PUBKEY=${JENKINS_AGENT_SSH_PUBKEY}

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl git docker-cli \
    && curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" -o /usr/local/bin/kubectl \
    && chmod +x /usr/local/bin/kubectl \
    && curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz" -o /tmp/helm.tar.gz \
    && tar -xzf /tmp/helm.tar.gz -C /tmp \
    && mv /tmp/linux-amd64/helm /usr/local/bin/helm \
    && chmod +x /usr/local/bin/helm \
    && mkdir -p /home/jenkins/agent /home/jenkins/.kube \
    && chown -R jenkins:jenkins /home/jenkins \
    && rm -rf /tmp/helm.tar.gz /tmp/linux-amd64 \
    && rm -rf /var/lib/apt/lists/*

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

WORKDIR /home/jenkins/agent
CMD ["docker-entrypoint.sh"]
