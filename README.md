# Self-Healing Multi-Region Web App

A portfolio-ready reference implementation of a stateless web application deployed to two AWS regions, managed with Terraform and Argo CD, with CloudWatch-triggered Lambda failover through Route 53.

> **Important:** This repository is infrastructure/application code, not a live deployment. The Terraform creates billable AWS resources (including two EKS clusters and worker nodes). Review costs and quotas before applying. The recovery-time figure in a resume should be reported only after you run and record the chaos/failover test described below.

## Architecture

```text
                       Users
                         |
                    Route 53 DNS
               weighted records (same name)
                  /              \
          Region A (primary)   Region B (standby)
          EKS + app pods       EKS + app pods
          ALB ingress          ALB ingress
                  \              /
                   CloudWatch alarms
                           |
                     SNS notifications
                           |
                  Failover Lambda (Region A)
                           |
                 Route 53 weighted records
                   A: 100 / B: 0  <->  A: 0 / B: 100

Git repository -> Argo CD in each cluster -> Kubernetes Deployments/Services
Terraform -> VPC, EKS, node groups, IAM, Route 53, alarms, Lambda, SNS
```

The two regional clusters are provisioned independently. Argo CD is installed into each cluster and watches this repository's `k8s/` directory. Route 53 weighted records make the regional switch explicit and reversible. The Lambda is idempotent and handles alarm state transitions.

## Repository layout

- `app/` – minimal stateless Node.js application with `/`, `/health`, and `/ready`.
- `Dockerfile` – non-root container image.
- `k8s/` – Deployment, Service, namespace, and Argo CD Application.
- `terraform/` – two-region EKS, networking, Route 53, CloudWatch/SNS, Lambda, and IAM.
- `lambda/` – Python failover function.
- `.github/workflows/` – container build workflow (configure repository secrets first).
- `scripts/` – helper scripts for kubeconfig and failover testing.

## Prerequisites

- AWS account with permissions to create VPC, EKS, EC2, IAM, Lambda, SNS, CloudWatch, Route 53 and related resources.
- Terraform >= 1.6, AWS CLI v2, kubectl, Docker, Helm, Git.
- A registered domain hosted in Route 53 (or an existing hosted-zone ID).
- GitHub repository and GitHub Actions secrets for image publishing.
- Sufficient regional EKS/EC2 quotas.

## 1. Configure Terraform

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:
- `domain_name`: a domain you control, e.g. `example.com`.
- `hosted_zone_id`: Route 53 public hosted-zone ID for that domain.
- `app_fqdn`: hostname such as `app.example.com`.
- `image`: published image URI, e.g. `123456789012.dkr.ecr.ap-south-1.amazonaws.com/multiregion-webapp:latest`.
- `primary_lb_dns`, `secondary_lb_dns`, `primary_lb_dimension`, and `primary_target_group_dimension`: these are obtained after the clusters and public LoadBalancer Services exist; see the two-phase bootstrap below. The current Terraform configuration expects these values.
- `primary_region` and `secondary_region`: two supported AWS regions.

Initialize and inspect the plan:

```bash
terraform init
terraform fmt -recursive
terraform validate
terraform plan
```

The Route 53/Lambda layer needs the public load-balancer DNS names and CloudWatch ALB dimensions, which are only known after the Kubernetes Services have been created. Bootstrap in two phases: temporarily comment out the `aws_route53_record` resources in `main.tf` and the resources in `failover.tf`, then apply the VPC/EKS modules. Deploy the app to both clusters as described below, wait for each `Service` of type `LoadBalancer` to receive an AWS load-balancer hostname, and collect its ALB dimensions. Restore the DNS/failover resources, fill in the four values in `terraform.tfvars`, then run `terraform plan` and `terraform apply` again.

Apply only after reviewing the plan and expected costs:

```bash
terraform apply
```

The EKS clusters use managed node groups. This can incur material hourly charges even when idle. To remove the lab:

```bash
terraform destroy
```

The hosted zone itself is supplied by you and is not created or destroyed by this project.

## 2. Build and publish the application

Create an ECR repository in each region (or use an existing cross-region image strategy), then push the same immutable image tag to both registries. Example for one region:

```bash
aws ecr get-login-password --region ap-south-1 | docker login --username AWS --password-stdin ACCOUNT_ID.dkr.ecr.ap-south-1.amazonaws.com
docker build -t multiregion-webapp:latest .
docker tag multiregion-webapp:latest ACCOUNT_ID.dkr.ecr.ap-south-1.amazonaws.com/multiregion-webapp:latest
docker push ACCOUNT_ID.dkr.ecr.ap-south-1.amazonaws.com/multiregion-webapp:latest
```

Repeat for the second region, or configure ECR replication. Update `image` in Terraform and `k8s/deployment.yaml` to the same image URI/tag.

## 3. Connect Argo CD to both clusters

Get credentials (replace regions/account details as needed):

```bash
aws eks update-kubeconfig --region ap-south-1 --name shmr-primary
kubectl create namespace argocd
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm install argocd argo/argo-cd -n argocd --set server.service.type=LoadBalancer
```

Repeat in the secondary region using `--region us-east-1 --name shmr-secondary`.

For each cluster, install Argo CD and register the Git repository. The `webapp` Service is type `LoadBalancer`; wait for its external hostname before configuring the Route 53/Lambda Terraform layer. If the repo is public, the Application manifest can sync directly. For a private repo, add repository credentials securely with `argocd repo add` or a Kubernetes Secret; do not commit credentials.

Edit `k8s/argocd/application.yaml` and replace `YOUR_GITHUB_REPOSITORY_URL`. Apply it to each cluster:

```bash
kubectl apply -f k8s/argocd/application.yaml
```

The Application uses automated sync, pruning, and self-healing. Argo CD continuously reconciles drift; automated rollback of a failed sync is not enabled by this manifest. For production, add progressive delivery/health gates (for example Argo Rollouts) and a tested rollback policy.

## 4. Configure regional DNS targets

Terraform creates two weighted Route 53 A-alias records for the same hostname, pointing at the regional load balancers. The Lambda switches their weights in response to CloudWatch alarm state. DNS caching means clients may continue using an old answer until their resolver cache expires; DNS failover is not instantaneous.

## 5. Test health and failover

1. Verify both regional app endpoints return HTTP 200 from `/health`.
2. Verify the Route 53 record set initially has primary weight 100 and secondary weight 0.
3. In a non-production test window, publish an ALARM state to the SNS topic or trigger the primary alarm by making the primary target unhealthy.
4. Confirm the Lambda logs show the switch and Route 53 record weights become primary 0 / secondary 100.
5. Query DNS repeatedly and test the app through the hostname. Record alarm detection, Lambda execution, DNS propagation, and end-to-end recovery separately.
6. Restore the primary and confirm the OK transition returns weights to primary 100 / secondary 0.

Use the included script:

```bash
scripts/check-endpoints.sh https://app.example.com
```

Do not deliberately break a production workload. The Lambda supports ALARM => secondary and OK => primary. Test `INSUFFICIENT_DATA` behavior and operational runbooks before production use.

## Resume wording

Use only claims you have personally verified. A defensible version before measurement:

- Built a stateless multi-region web application on AWS using Terraform, EKS, Kubernetes, and Argo CD GitOps.
- Automated Route 53 weighted-DNS failover with CloudWatch alarms and an AWS Lambda handler; documented and tested regional recovery.

After measuring repeatable tests, add your observed median/p95 recovery time and test conditions. Do not claim “45 minutes to under 5 minutes” unless your test evidence supports it.

## Security and production hardening

- Use remote Terraform state with encryption, versioning, and state locking.
- Restrict IAM policies, SNS publishing, Lambda invocation, and EKS access to least privilege.
- Use private subnets for worker nodes, private EKS endpoints where practical, TLS certificates, WAF, secrets management, image scanning, and log retention.
- Configure Route 53 health checks and alerting for both regions; test split-brain and partial-failure cases.
- Configure ECR replication or a reliable image promotion pipeline.
- Add PodDisruptionBudgets, autoscaling, resource requests/limits, network policies, and backup/restore procedures.
- Review the Lambda IAM policy and Route 53 record identifiers before production use.
