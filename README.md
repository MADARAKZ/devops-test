# DevOps Engineer Case Study

Solution for the DevOps Engineer case study.

## What This Solution Covers

- Jenkins Controller and Agent architecture
- CI/CD pipeline with unit test, code quality, Docker build, image push, deploy, smoke test, and rollback
- Dockerized Node.js demo application
- Helm chart for Kubernetes deployment with probes, rolling update, resources, and replicas
- Local demo using Docker Compose, local registry, and Minikube Cilium
- Written report PDF and slide outline

## Repository Layout

```text
.
|-- app/                         # Demo Node.js service
|-- docker-compose.yml           # Jenkins, agent, registry, and app
|-- Jenkinsfile                  # CI/CD pipeline
|-- jenkins/                     # Jenkins images and JCasC template
|-- helm/                        # Helm chart for Kubernetes deployment
|-- scripts/                     # Helper scripts
`-- docs/                        # Case study report and slide outline
```

## Quick Start

Use the startup script instead of running `docker compose up` directly. The script generates local-only Jenkins SSH credentials and renders the JCasC file required by the controller.

```bash
chmod +x scripts/*.sh
./scripts/start-local.sh
```

Jenkins:

```text
URL: http://localhost:8080
Username: admin
Password: admin123
```

Demo app:

```bash
curl http://localhost:3000/health
```

## GitHub Polling Pipeline

Push this repository to GitHub, then create a Jenkins Pipeline job that polls GitHub for changes:

```bash
./scripts/create-polling-job.sh https://github.com/your-user/devops-case-study.git main
```

By default the job is named `devops-case-study` and uses:

```text
Poll SCM: H/2 * * * *
Script Path: Jenkinsfile
Agent Label: docker-agent
```

With this setup, the flow is:

```text
git push to GitHub
  -> Jenkins polls GitHub every few minutes
  -> Jenkins Controller detects a new commit
  -> Jenkins Agent runs Jenkinsfile
  -> Jenkins tests the app, builds the image, pushes to localhost:5000, and runs deploy mock
```

You can customize the job name and poll schedule:

```bash
JOB_NAME=my-pipeline POLL_SCHEDULE="H/5 * * * *" ./scripts/create-polling-job.sh https://github.com/your-user/devops-case-study.git main
```

## Minikube + Cilium Demo

Start a local Kubernetes cluster with one control-plane node, two worker nodes, containerd, and Cilium CNI:

```bash
./scripts/minikube-cilium.sh start
```

Deploy the demo app to that cluster:

```bash
./scripts/minikube-cilium.sh deploy
helm status devops-demo-app -n devops-demo
kubectl get pods,svc -n devops-demo -o wide
```

The report PDF for submission is generated at:

```text
docs/DevOps_CaseStudy_Report.pdf
```

## Case Study Documents

- Report PDF: `docs/DevOps_CaseStudy_Report.pdf`
- Report source: `docs/DevOps_CaseStudy_Report.md`
- Slide outline: `docs/slide-outline.md`
