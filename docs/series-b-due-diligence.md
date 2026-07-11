# Cavendish Analytics — Series B Due Diligence Summary

**Platform:** EKS (`cavendish-staging`, eu-west-2)  
**GitOps:** Argo CD ApplicationSet → Helm chart  
**CI/CD:** GitHub Actions OIDC → ECR (no long-lived AWS keys)  
**Last DR exercise:** 2026-07-11 (see `docs/dr-runbook.md`)

## Investor questions → evidence

| Concern (from Q1–Q4 incidents) | Control | Where to verify |
|-------------------------------|---------|-----------------|
| Static cloud keys in Git / pods | IRSA + Secrets Manager CSI | SA annotations; no `AWS_ACCESS_KEY` in manifests |
| Unencrypted / ad-hoc TLS | ALB + ACM wildcard | `curl -I https://api.eks.ayuadomain.com` |
| Lateral movement / noisy neighbours | NetworkPolicy (restricted namespace) | `docs/hpa-load-test.md` + netpol tests |
| Over-privileged workloads | PSS `restricted` + named RBAC SAs | Privileged Pod rejected; no `default` SA |
| No observability / silent outages | Prometheus + Grafana + Alertmanager | Four-panel dashboard; D10 alert fire/clear |
| Untested recovery | Velero objects + pg_dump → S3 | `docs/dr-runbook.md` RTO table |
| Manual snowflake deploys | CI lint/build + CD tag bump → Argo CD | GitHub Actions CI + CD workflows |

## Deliverables map (D1–D14)

| Ref | Status signal |
|-----|----------------|
| D1–D5 | Terraform EKS + Helm/Argo + ALB/ACM + IRSA + Secrets CSI |
| D6–D7 | HPA under k6; NetworkPolicy allow/deny proven |
| D8–D10 | Metrics, Grafana, alert path |
| D11 | Push → CI → CD → Argo CD revision |
| D12 | Velero + pg_dump; RTO &lt; 60 min on staging exercise |
| D13–D14 | Named SAs/RBAC; PSS restricted enforced |

## Architecture one-liner

Git is the source of truth: **CI builds images with OIDC**, **CD pins the digest/tag in Git**, **Argo CD reconciles the cluster**. Data plane credentials never leave AWS (IRSA + Secrets Manager). Recovery splits **cluster objects (Velero)** from **database contents (pg_dump)**.

## Residual risks (honest)

- Staging runs **2× t3.medium** — pod density is tight; DR/monitoring may need temporary scale-downs.
- Volume snapshots disabled on staging; DB RPO depends on **pg_dump schedule** (every 6h).
- Production environment is scaffolded in chart/ApplicationSet but **not provisioned** until a separate Terraform workspace exists.
