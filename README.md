# DevOps Engineer Case Study

CI bằng Jenkins → Docker image; CD bằng ArgoCD pulling Kustomize+Helm overlays. Mỗi branch ánh xạ vào một môi trường.
## Repo layout
```text
.
├── app/                              Demo Node.js service + Dockerfile
├── helm/devops-demo-app/              Base Helm chart (Deployment, Service, ConfigMap, …)
├── gitops/
│   ├── dev/      kustomization.yaml + values.yaml   # ArgoCD source for devops-demo-dev
│   ├── staging/  kustomization.yaml + values.yaml   # ArgoCD source for devops-demo-staging
│   └── prod/     kustomization.yaml + values.yaml   # ArgoCD source for devops-demo-prod
├── argocd/
│   ├── project.yaml                                # AppProject scoping the 3 envs
│   ├── application-dev.yaml                        # auto-sync, prune, selfHeal
│   ├── application-staging.yaml                    # auto-sync, prune, selfHeal
│   └── application-prod.yaml                       # manual sync (approval gate)
├── jenkins/{controller,agent}/        Jenkins images + JCasC
├── scripts/                           start-local.sh, create-polling-job.sh, minikube-cilium.sh
├── docker-compose.yml                 Jenkins + agent + registry + demo app
└── Jenkinsfile                        CI + GitOps bump
```

## Gitflow → environment matrix

| Branch / Ref     | Image tag pattern            | docker push | bump gitops/  | ArgoCD app           | Approval |
|------------------|------------------------------|-------------|---------------|----------------------|----------|
| `feature/*`      | `feat-<build>-<sha>`         | —           | —             | —                    | —        |
| `develop`        | `dev-<build>-<sha>`          | ✓           | `gitops/dev`      | auto-sync            | —        |
| `release/*`      | `rc-<name>-<sha>`            | ✓           | —             | (manual promote)     | —        |
| `staging`        | `rc-<build>-<sha>`           | ✓           | `gitops/staging`  | auto-sync            | —        |
| `hotfix/*`       | `hotfix-<name>-<sha>`        | ✓           | —             | (manual promote)     | —        |
| `main`           | `prod-<build>-<sha>`         | ✓           | `gitops/prod`     | manual sync          | ✓        |
| tag `v*`         | `<tag>` (e.g. `v1.0.0`)       | ✓           | `gitops/prod`     | manual sync          | ✓        |

Merge flow:

```text
feature/x ──► develop ──► staging ──► main ──► tag vX.Y.Z
                                ▲
                                └── release/X.Y  (cut from develop, fix-only)
hotfix/x ─────────────────────────► main  (also merge back to develop)
```

## End-to-end loop

```text
git push origin <branch>
        │
        ▼
 GitHub commits land
        │
        ▼
 Jenkins polls every ~2 min  (jobs created from scripts/create-polling-job.sh)
        │ checkout / test / docker build
        │ push image to registry  (develop/staging/main/release/hotfix/tag)
        │ bump gitops/<env>/values.yaml.image.tag and push commit  (develop/staging/main/tag)
        ▼
 GitHub now has the new image tag in gitops/<env>/values.yaml
        │
        ▼
 ArgoCD detects out-of-sync (auto for dev/staging, manual for prod)
        │ renders kustomize+helm overlay
        ▼
 Kubernetes namespace devops-demo-<env> rolls out the new image
```

Loop protection: Jenkins commits its GitOps bumps with `[skip ci]` in the message. Jenkins stage 1 reads the commit message and aborts when it sees that marker, so a bump commit never re-enters CI.

## Local prerequisites

1. Docker / Docker Compose.
2. Optional, for actually testing ArgoCD locally: Minikube + ArgoCD installed in the cluster (see `scripts/minikube-cilium.sh start`).

## Start Jenkins + registry + demo app

```bash
chmod +x scripts/*.sh
./scripts/start-local.sh           # builds & runs jenkins-controller, jenkins-agent, registry, demo-app
# Jenkins:  http://localhost:8080    admin / admin123
```

## Wire Jenkins to GitHub

1. Create or reuse a GitHub Personal Access Token with `repo` scope.
2. In Jenkins → **Manage Jenkins → Credentials → System → Global**, add:
   - Kind: **Username with password**
   - Scope: Global
   - Username: your GitHub username (e.g. `MADARAKZ`)
   - Password: the PAT
   - ID: **`github-push`**  (this matches the default `params.GIT_CREDENTIALS_ID`)
3. Create a pipeline job that polls the repo:

   ```bash
   ./scripts/create-polling-job.sh https://github.com/<owner>/<repo>.git main
   ```

   Repeat (or use a Multibranch job) for `develop`, `staging`, etc., or set up one Multibranch Pipeline.

## Install ArgoCD applications

After ArgoCD is running in the cluster:

```bash
kubectl apply -n argocd -f argocd/project.yaml
kubectl apply -n argocd -f argocd/application-dev.yaml
kubectl apply -n argocd -f argocd/application-staging.yaml
kubectl apply -n argocd -f argocd/application-prod.yaml
```

ArgoCD now watches `gitops/dev`, `gitops/staging`, `gitops/prod`. Dev/staging auto-sync on every commit; prod waits for a manual sync in the ArgoCD UI/CLI.

## Demo a full flow

```bash
git checkout -b feature/say-hello
echo "hello" >> app/readme.md
git commit -am "feature: greet the user"
git push origin feature/say-hello
# Jenkins runs test + build (no push, no bump). ArgoCD untouched.

# Promote into the dev environment
git checkout develop
git merge feature/say-hello
git push origin develop
# Jenkins runs test + build + push + bumps gitops/dev/values.yaml + commits with [skip ci].
# ArgoCD dev application detects new image tag and rolls it out to namespace devops-demo-dev.

# Promote to staging, then production:
git checkout staging && git merge develop && git push origin staging
git checkout main    && git merge staging && git push origin main
# main build requires manual approval in Jenkins before it bumps gitops/prod.
# Even after the bump, ArgoCD prod waits for manual sync.

# Cut a release tag
git tag -a v1.0.0 -m "first release"
git push origin v1.0.0
# Image tagged v1.0.0 is pushed; gitops/prod is bumped (with approval) to image.tag=v1.0.0.
```

## Rollback

GitOps rollback is a `git revert`:

```bash
git revert <bump-commit> -m "revert: rollback prod to previous image"
git push origin main
# ArgoCD reconciles back to the previous image tag.
```

Or in ArgoCD CLI:

```bash
argocd app history devops-demo-prod
argocd app rollback devops-demo-prod <history-id>
```

## Files of interest

- `Jenkinsfile`                            — CI + image tag bump back to repo.
- `helm/devops-demo-app/values.yaml`        — chart defaults (security context, probes, …).
- `gitops/<env>/values.yaml`               — per-env overrides; the `image.tag` is what Jenkins rewrites.
- `gitops/<env>/kustomization.yaml`         — `helmCharts:` + `helmGlobals.chartHome: ../../helm`.
- `argocd/application-<env>.yaml`           — sets ArgoCD source path + sync policy.
