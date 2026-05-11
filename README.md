# Monorepo — Spring Boot on AWS EKS

A production-ready monorepo containing two Java Spring Boot microservices 
deployed to AWS EKS via Terraform, Helm, GitHub Actions CI/CD, and ArgoCD GitOps.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                        Internet                         │
└───────────────────┬─────────────────────────────────────┘
                    │ HTTPS (443)
          ┌─────────▼──────────┐
          │   AWS ALB (HTTPS)  │  ← ACM Certificate
          │  ALB Ingress Ctrl  │
          └────┬──────────┬────┘
               │          │
    /api/v1/items   /api/v1/notifications
               │          │
    ┌──────────▼──┐  ┌────▼───────────┐
    │  service-a  │  │   service-b    │
    │ Spring Boot │  │ Spring WebFlux │
    │  (Port 8080)│  │  (Port 8081)   │
    └──────┬──────┘  └──────┬─────────┘
           │                │
           └───────┬────────┘
                   │ IRSA (IAM Roles for Service Accounts)
        ┌──────────▼──────────┐
        │  AWS Secrets Manager│
        │  - app-secret-key   │
        │  - notification-key │
        └─────────────────────┘

EKS Cluster (private node groups, 2–3 AZs)
ArgoCD (GitOps — watches helm/ directory)
```

---

## Repository Structure

```
monorepo/
├── services/                     # All Java microservices live here
│   ├── service-a/                # Spring Boot REST API (JPA + H2)
│   │   ├── src/
│   │   ├── build.gradle
│   │   └── Dockerfile
│   └── service-b/                # Spring Boot WebFlux (Reactive + Redis)
│       ├── src/
│       ├── build.gradle
│       └── Dockerfile
├── helm/
│   ├── service-a/                # Helm chart (Deployment, Service, HPA, PDB)
│   ├── service-b/                # Helm chart
│   └── ingress/                  # ALB Ingress with HTTPS
├── terraform/
│   ├── modules/
│   │   ├── networking/           # VPC, subnets, NAT gateways
│   │   ├── eks/                  # EKS cluster + node groups + OIDC
│   │   └── secrets/              # Secrets Manager + IRSA roles
│   └── environments/
│       ├── dev/                  # Dev environment config
│       └── prod/                 # Prod environment config
├── argocd/
│   ├── apps/                     # ArgoCD Application manifests
│   └── projects/                 # ArgoCD Project definitions
├── .github/workflows/
│   └── ci-cd.yml                 # Full CI/CD pipeline
├── scripts/
│   └── localstack-init.sh        # Local secret seeding
├── docker-compose.yml            # Local development stack
├── build.gradle                  # Root Gradle config
└── settings.gradle               # Subproject declarations
```

---

## Prerequisites

| Tool | Version |
|------|---------|
| Java | 21+ |
| Gradle | 8.7 (via wrapper) |
| Docker | 24+ |
| Terraform | 1.7+ |
| AWS CLI | 2.x |
| kubectl | 1.29+ |
| Helm | 3.14+ |
| ArgoCD CLI | 2.10+ |

---

## Quick Start — Local Development

## Git Useful commands
```bash
git status
git switch -c feature-login
```

```bash
# 1. Start all services locally (includes Redis + LocalStack)
docker compose up --build

# Build Docker image from inside service directory
docker build -f services/service-a/Dockerfile -t service-a .

# 2. Test service-a
curl http://localhost:8080/api/v1/items/health
t service-a ./services/service-a
# 3. Test service-b
curl http://localhost:8081/api/v1/notifications/health

# 4. Create an item (service-a)
curl -X POST http://localhost:8080/api/v1/items \
  -H "Content-Type: application/json" \
  -d '{"name": "test-item", "value": 42}'

# 5. Send a notification (service-b)
curl -X POST http://localhost:8081/api/v1/notifications/send \
  -H "Content-Type: application/json" \
  -d '{"message": "Hello from service-b", "recipient": "team"}'
```

---

## Building with Gradle

```bash
# Build all services
./gradlew build

# Build a specific service
./gradlew services:service-a:bootJar
./gradlew services:service-b:bootJar

# Run tests
./gradlew test

# Run tests for one service
./gradlew :service-a:test

# Run a service
./gradlew :services:service-a:bootRun
./gradlew :services:service-b:bootRun
```

---
## Infrastructure Deployment (Terraform)

### 1. Bootstrap S3 Backend (once)
```bash
aws s3 mb s3://your-tfstate-bucket-dev --region us-east-1
aws dynamodb create-table \
  --table-name terraform-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

### 2. Deploy Dev Environment
```bash
cd terraform/environments/dev
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

terraform init
terraform plan
terraform apply
```

Recommended enterprise workflow
```bash
# Create:
terraform init
terraform fmt -recursive 
terraform validate
terraform plan -out=tfplan
terraform apply tfplan

# Cleanup:
terraform destroy
```

Useful commands
```bash
# Validate syntax:
terraform validate

" Format files:
terraform fmt -recursive

#Show current state:
terraform state list

#Show outputs:
terraform output

# Refresh AWS state:
terraform refresh
```

### 3. Configure kubectl
```bash
aws eks update-kubeconfig --region us-east-1 --name monorepo-dev
kubectl get nodes
```

---

## GitOps with ArgoCD

### Initial Setup
```bash
# Get ArgoCD admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Port-forward ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8090:80

# Login via CLI
argocd login localhost:8090

# Apply the App-of-Apps (bootstraps everything)
kubectl apply -f argocd/apps/root-app.yaml
kubectl apply -f argocd/projects/monorepo-project.yaml
```

### How GitOps Works
1. CI pipeline builds Docker images and pushes to GHCR
2. CI updates `image.tag` in `helm/service-a/values.yaml` and `helm/service-b/values.yaml`
3. ArgoCD detects the git change and automatically syncs the Helm release to EKS
4. Rollback = `git revert` → ArgoCD auto-syncs the old tag

---

## GitHub Actions CI/CD

### Required GitHub Secrets

| Secret | Description |
|--------|-------------|
| `AWS_ACCESS_KEY_ID` | IAM user with EKS + ECR permissions |
| `AWS_SECRET_ACCESS_KEY` | IAM secret |
| `ACM_CERT_ARN` | ACM certificate ARN for HTTPS |

### Pipeline Stages

```
Push to branch
    │
    ├── build-and-test (matrix: service-a, service-b)
    │       └── Gradle test + bootJar
    │
    ├── docker (on push only)
    │       └── Build + push to GHCR (multi-arch amd64/arm64)
    │
    ├── security-scan
    │       └── Trivy vulnerability scan (CRITICAL + HIGH)
    │
    ├── terraform-plan (PRs only)
    │       └── Posts plan diff as PR comment
    │
    ├── terraform-apply (main only, requires approval)
    │       └── Applies infrastructure changes
    │
    └── update-gitops (main only)
            └── Updates image tags → triggers ArgoCD sync
```

---

## HTTPS / Domain Setup

1. **Request an ACM certificate** in AWS Console for your domain
2. **Add CNAME validation records** to your DNS provider
3. Set `acm_certificate_arn` in `terraform.tfvars`
4. Set `domain_name` to your domain (e.g. `dev.example.com`)
5. After `terraform apply`, get the ALB DNS name:
   ```bash
   kubectl get ingress -n default
   ```
6. Create a **CNAME record** in your DNS pointing your domain → ALB DNS name

---

## AWS Secrets Manager

Secrets are accessed via **IRSA** (IAM Roles for Service Accounts) — no static credentials needed in pods.

| Secret Name | Used By | Description |
|------------|---------|-------------|
| `app-secret-key` | service-a | Application signing key |
| `notification-api-key` | service-b | External notification API key |

To rotate a secret:
```bash
aws secretsmanager update-secret \
  --secret-id app-secret-key \
  --secret-string '{"value":"new-secret-value"}'
```

---
### AWS lib

| Service         | Dependency                              |
| --------------- | --------------------------------------- |
| S3              | `software.amazon.awssdk:s3`             |
| Secrets Manager | `software.amazon.awssdk:secretsmanager` |
| DynamoDB        | `software.amazon.awssdk:dynamodb`       |
| SQS             | `software.amazon.awssdk:sqs`            |
| SNS             | `software.amazon.awssdk:sns`            |
| STS             | `software.amazon.awssdk:sts`            |
| ECR             | `software.amazon.awssdk:ecr`            |
| CloudWatch      | `software.amazon.awssdk:cloudwatch`     |
| IAM             | `software.amazon.awssdk:iam`            |

## AWS command:
```bash
# List certificates
aws acm list-certificates --profile xxxx

aws s3 ls --profile xxxx
aws s3api list-buckets --profile xxxx

aws dynamodb describe-table --table-name terraform-lock --profile xxxx

```

---
## Customization Checklist
# First phase
- [ ] Request an ACM certificate** in AWS Console for your domain
- [ ] Add CNAME validation records** to your DNS provider
# 
- [ ] Replace `your-org` with your GitHub organization in all files 
      - Replace your-org in Helm values.yaml and ArgoCD apps/ with your GitHub org
- [ ] Replace `your-tfstate-bucket-dev/prod` with real S3 bucket names
- [ ] Set real `domain_name` values in `terraform.tfvars`
- [ ] Set real `acm_certificate_arn` after certificate validation
- 
- [ ] Update ArgoCD `repoURL` in `argocd/apps/` to your real repo URL
- [ ] Set strong secret values in Secrets Manager (not defaults)
- [ ] Review `public_access_cidrs` in EKS module for your IP allowlist


First steps after unzipping

Replace your-org in Helm values.yaml and ArgoCD apps/ with your GitHub org
Update terraform.tfvars with your ACM cert ARN and domain
Run docker-compose up --build to test locally


Here's the full process in plain language to accompany the diagram above. 


### Phase 1 — Create the GitHub repository
Create a new repo on GitHub (public or private). Set main as the default branch, then immediately enable 
branch protection: require at least one PR review and require all status checks to pass before merging. 
No one pushes directly to main — everything flows through pull requests.

### Phase 2 — Scaffold and push the structure
Clone the repo locally, create the full folder tree (services/service-a, services/service-b, 
terraform/, helm/, argocd/, .github/workflows/), add a root settings.gradle that includes both services as subprojects, 
then commit and push. Add a .gitignore covering build/, .gradle/, .terraform/, *.tfstate, and .DS_Store at minimum.

### Phase 3 — Configure GitHub Actions
Add .github/workflows/ci-cd.yml. The pipeline runs five jobs in sequence: Gradle tests, Docker build + push to GHCR, 
Trivy security scan, Terraform plan on PRs or apply on merges to main, and finally a commit that bumps the image 
tag in helm/service-a/values.yaml and helm/service-b/values.yaml. That last commit is the trigger for ArgoCD.
Go to Settings → Secrets and variables → Actions and add AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, and ACM_CERT_ARN. 
GITHUB_TOKEN is provided automatically.

### Phase 4 — Bootstrap AWS prerequisites (one-time)
Before any Terraform can run you need three things already in AWS: an S3 bucket and DynamoDB table for remote state 
(terraform init reads from these), an IAM user or GitHub OIDC role that CI can assume with permissions to manage EKS 
and Secrets Manager, and an ACM certificate for your domain validated via DNS.

### Phase 5 — Terraform apply → EKS + Helm
From terraform/environments/dev, run terraform init then terraform apply. Terraform provisions the VPC and subnets, 
the EKS cluster with private node groups and an OIDC provider, Secrets Manager secrets with IRSA policies, and then 
uses the Helm provider to install the ALB controller, both services, and the ALB ingress. After apply finishes, 
run aws eks update-kubeconfig to connect kubectl, then grab the ALB hostname from kubectl get ingress and 
add a CNAME record in your DNS provider.

### Phase 6 — Bootstrap ArgoCD (GitOps live)
ArgoCD was installed by Terraform via Helm. Retrieve the initial admin password, port-forward the UI, 
then apply two manifests: argocd/projects/monorepo-project.yaml and argocd/apps/root-app.yaml. 
The root app uses the App-of-Apps pattern — it watches argocd/apps/ and automatically creates 
the service-a and service-b Application objects. From this point the loop is closed: 
merge to main → CI builds and pushes the image → CI commits a new tag into helm/*/values.yaml → ArgoCD 
detects the change and rolls out the new version, with automatic rollback on failure.You said: Wh