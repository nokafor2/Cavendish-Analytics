# Cavendish Analytics — Production EKS Platform

Production-grade AWS EKS platform for Cavendish Analytics Ltd — a fintech data analytics firm serving twelve mid-tier UK financial institutions.

## Repository Structure

```
cavendish-analytics-eks/
├── app/                    FastAPI Analytics API
├── chart/                  Helm chart (staging + production)
├── terraform/              AWS infrastructure as code
├── argocd/                 GitOps ApplicationSet
├── monitoring/             Prometheus + Grafana
├── velero/                 Cluster backup schedules
├── phase0/                 k3s reverse-proxy foundations (Phase 0)
├── docs/                   Architecture, DR, runbooks, chronology
└── .github/workflows/      CI/CD pipelines (OIDC)
```

## Phases

| Phase | Focus | Duration |
|-------|-------|----------|
| Phase 0 | k3s + Nginx Ingress + cert-manager + FreeDNS | 3 days |
| Week 1 | Terraform, EKS, Helm, ArgoCD, IRSA, TLS | 5 days |
| Week 2 | PostgreSQL, HPA, NetworkPolicy, observability, DR, CI/CD | 5 days |

## Deliverables

Seventeen verified deliverables — see [docs/chronology.html](docs/chronology.html) for the full execution timeline and [docs/architecture.md](docs/architecture.md) for resource development guide.

## Quick Start

```bash
# Phase 0 — k3s foundations (see phase0/README.md)
# Week 1 — Terraform
cd terraform && terraform init && terraform plan

# Week 1 — Helm
helm lint chart/
helm template cavendish chart/ -f chart/values.staging.yaml

# Week 2 — ArgoCD
kubectl apply -f argocd/applicationset.yaml
```

## Documentation

- [Execution Chronology](docs/chronology.html) — day-by-day project timeline
- [Architecture & Resource Development](docs/architecture.md)
- [Phase 0 → EKS Mapping](docs/phase0-to-eks-mapping.md)
- [Disaster Recovery Runbook](docs/dr-runbook.md) *(populate after D12)*
