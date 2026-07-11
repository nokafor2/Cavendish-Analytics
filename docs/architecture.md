# Architecture & Resource Development Guide

This document specifies **how each resource in the Cavendish Analytics EKS platform is developed**, in dependency order.

---

## Layer 0 — Phase 0 Foundations (k3s)

Built manually before any AWS provisioning. No Terraform required.

| Resource | Location | How It Is Developed |
|----------|----------|---------------------|
| k3s cluster | EC2 instance | `curl -sfL https://get.k3s.io \| INSTALL_K3S_EXEC="--disable traefik" sh -` |
| Nginx Ingress Controller | Helm → `ingress-nginx` namespace | Helm install; registers `IngressClass: nginx` |
| http-echo placeholder | `phase0/manifests/` | Deployment + Service for routing verification |
| Ingress (HTTP) | `phase0/manifests/http-echo-ingress.yaml` | `ingressClassName: nginx`, Host rule, path routing |
| FreeDNS A record | Afraid.org (manual) | A record: `api.yourname.mooo.com` → EC2 public IP |
| cert-manager | Helm → `cert-manager` namespace | ClusterIssuer → Let's Encrypt production |
| TLS Ingress | `phase0/manifests/http-echo-ingress-tls.yaml` | `cert-manager.io/cluster-issuer` annotation + tls block |
| IP whitelist | `phase0/manifests/http-echo-ingress-whitelist.yaml` | `nginx.ingress.kubernetes.io/whitelist-source-range` |

**Verification:** P0-D1, P0-D2, P0-D3 deliverables in `docs/phase0-demo.txt`.

---

## Layer 1 — AWS Infrastructure (Terraform)

All resources declared in `terraform/`. State stored in S3 with DynamoDB locking. **No Console-created resources.**

### Development Order

```
1. S3 state bucket + DynamoDB lock table (bootstrap — one-time manual or separate bootstrap/)
2. VPC module          → main.tf
3. EKS cluster         → main.tf (depends on VPC)
4. Managed node groups → main.tf (depends on EKS)
5. ECR repositories    → main.tf
6. S3 backup buckets   → main.tf (pg_backups, velero)
7. Route 53 zone       → main.tf
8. ACM certificate     → main.tf (depends on Route 53 for DNS validation)
9. Secrets Manager     → main.tf (PostgreSQL credentials)
10. IRSA roles         → irsa.tf (depends on EKS OIDC provider)
11. GitHub OIDC        → irsa.tf
```

| Resource | Terraform File | Key Outputs |
|----------|---------------|-------------|
| VPC + subnets + NAT | `main.tf` | `module.vpc.vpc_id`, subnet IDs |
| EKS cluster | `main.tf` | `cluster_name`, `cluster_endpoint`, OIDC issuer |
| Managed node group | `main.tf` | ASG with min/max/desired |
| ECR repos | `main.tf` | `ecr_repository_urls` |
| S3 pg_backups | `main.tf` | `pg_backups_bucket` |
| S3 velero | `main.tf` | `velero_bucket` |
| Route 53 | `main.tf` | `route53_zone_id` |
| ACM cert | `main.tf` | `acm_certificate_arn` |
| Secrets Manager | `main.tf` | `postgres_secret_arn` |
| IRSA (5 roles) | `irsa.tf` | `irsa_*_role_arn` outputs |
| GitHub OIDC | `irsa.tf` | `github_actions_role_arn` |

**Verification:** D1 — `terraform show` confirms all resources; `kubectl get nodes` shows Ready.

---

## Layer 2 — EKS Cluster Add-ons

Installed via Helm after Terraform apply. Order matters — each add-on depends on IRSA roles from Terraform outputs.

| Add-on | Install Method | IRSA Role | Purpose |
|--------|---------------|-----------|---------|
| AWS Load Balancer Controller | Helm | `aws-load-balancer-controller` | Provisions ALB from Ingress resources |
| ExternalDNS | Helm | `external-dns` | Creates Route 53 records from Ingress annotations |
| EBS CSI Driver | EKS add-on (Terraform) | Built-in | Provisions EBS volumes for PVCs |
| Secrets Store CSI Driver | Helm | `secrets-store-csi` | Mounts Secrets Manager into Pods |
| Cluster Autoscaler | Helm | `cluster-autoscaler` | Scales node group based on pending Pods |
| kube-prometheus-stack | Helm | N/A | Prometheus + Grafana + AlertManager |
| Velero | Helm | `velero` | Cluster resource backup to S3 |
| ArgoCD | Helm | N/A | GitOps controller |

```bash
# Example: AWS Load Balancer Controller
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$(terraform output -raw cluster_name) \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=$(terraform output -raw irsa_alb_role_arn)
```

---

## Layer 3 — Application Helm Chart

All application resources in `chart/templates/`. Deployed via ArgoCD ApplicationSet to both namespaces.

### Template Development Order

| Template | Depends On | What It Creates |
|----------|-----------|-----------------|
| `namespace.yaml` | — | Namespace with Pod Security Standards labels |
| `serviceaccount.yaml` | IRSA roles (Terraform) | SA per service with `eks.amazonaws.com/role-arn` |
| `role.yaml` + `rolebinding.yaml` | namespace | Minimum-privilege RBAC per Pod |
| `deployment.yaml` | ECR images, SA, CSI secrets | Range loop — all services |
| `service.yaml` | deployment | ClusterIP per service + postgres headless |
| `statefulset.yaml` | EBS CSI, Secrets Manager | PostgreSQL + postgres-exporter sidecar |
| `ingress.yaml` | ALB Controller, ACM, ExternalDNS | HTTPS Ingress with ALB annotations |
| `networkpolicy.yaml` | All workloads running | Default-deny + 4 explicit allow rules |
| `hpa.yaml` | metrics-server, analytics-api | CPU-based autoscaling (production only) |
| `cronjob.yaml` | IRSA postgres-backup, S3 bucket | pg_dump every 6 hours |
| `servicemonitor.yaml` | kube-prometheus-stack | Scrape config for API + postgres-exporter |
| `prometheusrule.yaml` | Prometheus | API error rate + DB connection alerts |

### Values File Strategy

```
values.yaml           → base defaults (all services, structure)
values.staging.yaml   → staging overrides (lower replicas, HPA off)
values.production.yaml → production overrides (HPA on, monitoring on, larger PVC)
```

ArgoCD ApplicationSet generates one Application per environment from a single template — add an environment by adding one line to the generators list.

**Verification:** D2 — `helm list -A` shows both releases; all Pods Running.

---

## Layer 4 — Observability

| Resource | Location | How It Is Developed |
|----------|----------|---------------------|
| kube-prometheus-stack | `monitoring/prometheus-values.yaml` | Helm install with ServiceMonitor selector open |
| postgres-exporter sidecar | `chart/templates/statefulset.yaml` | Second container in postgres StatefulSet |
| ServiceMonitors | `chart/templates/servicemonitor.yaml` | Label `release: kube-prometheus-stack` |
| Grafana dashboard | `monitoring/grafana-dashboard.json` | Import JSON — 4 panels (request rate, CPU, HPA, DB connections) |
| PrometheusRules | `chart/templates/prometheusrule.yaml` | API error rate + pg_stat_activity_count alerts |

**Verification:** D8 (targets UP), D9 (dashboard live), D10 (alert fires and resolves).

---

## Layer 5 — Security & Resilience

| Resource | Location | How It Is Developed |
|----------|----------|---------------------|
| IRSA | `terraform/irsa.tf` + `chart/templates/serviceaccount.yaml` | OIDC trust policy → SA annotation → no access keys |
| Secrets Manager + CSI | Terraform secret + SecretProviderClass in chart | Credentials mounted as env vars, never in Git |
| NetworkPolicy | `chart/templates/networkpolicy.yaml` | Default-deny + dashboard→api, webhook→api, api→postgres |
| Pod Security Standards | `chart/templates/namespace.yaml` | `pod-security.kubernetes.io/enforce: restricted` |
| RBAC | `role.yaml` + `rolebinding.yaml` | Named SA per Pod — no `default` ServiceAccount |
| Velero BackupSchedule | `velero/backup-schedule.yaml` | Daily 02:00 UTC to S3 |
| pg_dump CronJob | `chart/templates/cronjob.yaml` | Every 6 hours via IRSA to S3 |

**Verification:** D4 (IRSA), D5 (Secrets Manager), D7 (NetworkPolicy), D12 (DR tested), D13 (RBAC), D14 (PSS).

---

## Layer 6 — CI/CD

| Pipeline | Location | Trigger | Actions |
|----------|----------|---------|---------|
| CI | `.github/workflows/ci.yml` | Push/PR to main | helm lint → docker build → ECR push (OIDC) |
| CD | `.github/workflows/deploy.yml` | CI success on main | helm upgrade --atomic (OIDC) |

GitHub Actions authenticates to AWS via OIDC federation — same principle as IRSA for Pods. No `AWS_ACCESS_KEY_ID` in GitHub Secrets.

**Verification:** D11 — push change → CI passes → CD bumps `chart/values.<env>.yaml` → ArgoCD Synced on new image SHA.

---

## Incident → Solution Mapping

| Incident | Root Cause | Resource That Fixes It |
|----------|-----------|----------------------|
| IAM key in Git | No IRSA | `terraform/irsa.tf` + SA annotations |
| Cluster config lost | No Terraform | `terraform/main.tf` |
| Staging/production drift | No Helm | `chart/` + ArgoCD ApplicationSet |
| API fell over at quarter-end | No HPA | `chart/templates/hpa.yaml` |
| PostgreSQL PVC unavailable | No backup/DR | `cronjob.yaml` + `velero/` + `docs/dr-runbook.md` |
| Compromised Pod → PostgreSQL | No NetworkPolicy | `chart/templates/networkpolicy.yaml` |
