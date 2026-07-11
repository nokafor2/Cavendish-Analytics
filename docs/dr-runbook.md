# Disaster Recovery Runbook — Cavendish Analytics (D12)

**Cluster:** `cavendish-staging` (EKS, eu-west-2)  
**Velero bucket:** `cavendish-staging-velero-791778419317`  
**pg_dump bucket:** `cavendish-staging-backups-791778419317`  
**Last DR test:** 2026-07-11 (staging-safe restore → `cavendish-dr-test`)

## Prerequisites

- `kubectl` context set to the Cavendish EKS cluster
- Velero installed in namespace `velero` (see `docs/chronology.html` Week 2 Thursday)
- AWS CLI configured (list S3 objects)
- Optional: [Velero CLI](https://velero.io/docs/) — not on winget; use Chocolatey (`choco install velero`) or download the Windows binary from [GitHub releases](https://github.com/vmware-tanzu/velero/releases)

## Architecture split

| Layer | Tool | What it restores |
|-------|------|------------------|
| Kubernetes objects (Deployments, Services, Ingress, NetworkPolicies, …) | **Velero** | App topology / config |
| PostgreSQL data | **pg_dump → S3** | Database contents |

PVC volume snapshots are **disabled** on staging to save node capacity. Rely on pg_dump for data.

---

## Procedure 1 — Manual Velero backup

```powershell
# Option A — apply the Backup CR
kubectl apply -f velero/backup-manual.yaml

# Option B — Velero CLI
velero backup create cavendish-staging-manual --include-namespaces cavendish-staging --wait

# Watch status
kubectl get backup -n velero
# Expected: Phase=Completed

# Confirm object in S3
aws s3 ls s3://cavendish-staging-velero-791778419317/ --recursive | Select-Object -Last 20
```

---

## Procedure 2 — Namespace restore (staging-safe DR test)

Preferred on staging: restore into a **new** namespace so live staging stays up.

```powershell
# Pause ArgoCD automated sync via ApplicationSet (Application patches do not stick)
Set-Content -Path "$env:TEMP\pause-argo.json" -Value '[{"op":"remove","path":"/spec/template/spec/syncPolicy/automated"}]'
kubectl patch applicationset cavendish-environments -n argocd --type json --patch-file "$env:TEMP\pause-argo.json"

# Restore objects into cavendish-dr-test
velero restore create cavendish-dr-test-restore `
  --from-backup cavendish-staging-manual `
  --namespace-mappings cavendish-staging:cavendish-dr-test `
  --wait

# Or without Velero CLI:
# kubectl apply -f velero/restore-dr-test.yaml

kubectl get pods -n cavendish-dr-test
# Expected: analytics-api / postgres pods progressing to Running

# Cleanup when done
kubectl delete namespace cavendish-dr-test --wait=false
velero restore delete cavendish-dr-test-restore  # optional

# Re-enable ArgoCD
Set-Content -Path "$env:TEMP\resume-argo.json" -Value '[{"op":"add","path":"/spec/template/spec/syncPolicy/automated","value":{"prune":true,"selfHeal":true}}]'
kubectl patch applicationset cavendish-environments -n argocd --type json --patch-file "$env:TEMP\resume-argo.json"
# Or: kubectl apply -f argocd/applicationset.yaml
```

### Full delete/restore (production-style — use carefully)

Only when you accept downtime on staging:

```powershell
Set-Content -Path "$env:TEMP\pause-argo.json" -Value '[{"op":"remove","path":"/spec/template/spec/syncPolicy/automated"}]'
kubectl patch applicationset cavendish-environments -n argocd --type json --patch-file "$env:TEMP\pause-argo.json"
velero backup create pre-dr-staging --include-namespaces cavendish-staging --wait
kubectl delete namespace cavendish-staging
velero restore create staging-full-restore --from-backup pre-dr-staging --wait
# Then Procedure 3 (pg_dump) before declaring success
# Re-enable ArgoCD sync when healthy (resume-argo.json or kubectl apply -f argocd/applicationset.yaml)
```

---

## Procedure 3 — PostgreSQL pg_dump restore

```powershell
# List dumps
aws s3 ls s3://cavendish-staging-backups-791778419317/pg-dump/

# Download latest (replace TIMESTAMP)
aws s3 cp s3://cavendish-staging-backups-791778419317/pg-dump/TIMESTAMP.sql.gz $env:TEMP\cavendish.sql.gz

# Copy into postgres pod and restore
# Windows: avoid $env:TEMP (C:) with kubectl cp — use a relative path
$ns = "cavendish-dr-test"   # or cavendish-staging for live restore
Copy-Item "$env:TEMP\cavendish.sql.gz" .\cavendish.sql.gz -Force
kubectl cp ./cavendish.sql.gz "${ns}/postgres-0:/tmp/cavendish.sql.gz" -c postgres

kubectl exec -n $ns postgres-0 -c postgres -- sh -c "gunzip -f /tmp/cavendish.sql.gz && psql -U cavendish -d cavendish -f /tmp/cavendish.sql"
```

Verify:

```powershell
kubectl exec -n $ns postgres-0 -c postgres -- psql -U cavendish -d cavendish -c "\dt"
# Live staging API (not the DR namespace — DR has no Ingress / Secrets IRSA):
curl.exe -s https://api.eks.ayuadomain.com/api/v1/db/status
```

---

## DR Test Results

| Step | Start Time (UTC) | End Time (UTC) | Duration | Status |
|------|------------------|----------------|----------|--------|
| Velero backup (`cavendish-staging-manual`) | 2026-07-11T00:20:36Z | 2026-07-11T00:20:37Z | ~1s | **Completed** (79/79 items) |
| Velero restore (`cavendish-dr-test-restore`) | 2026-07-11T11:44:11Z | 2026-07-11T11:44:18Z | ~7s | **PartiallyFailed** (71/71 items; 1 error = TargetGroupBinding already bound to live staging — expected; 1 warning = kube-root-ca.crt) |
| pg_dump restore into `cavendish-dr-test` | ~2026-07-11T12:00Z (S3 download) | ~2026-07-11T12:20Z (`\dt` verify) | ~20 min (incl. Windows `kubectl cp` fix) | **Completed** — dump applied; schema matches source |
| Data / API verification | 2026-07-11T12:20Z | 2026-07-11T12:26Z | — | **OK for DR scope:** DR `postgres-0` Ready; `\dt` = no relations (same as staging + S3 dump ~370 B empty schema). DR `analytics-api` not Ready (Secrets Store IRSA is staging-only; no DR Ingress) |

**Total RTO (restore start → DB verified):** ~**42 minutes** (2026-07-11T11:44Z → ~12:26Z), including pod-capacity troubleshooting (`Too many pods` on 2× t3.medium).  
**Technical restore time (Velero object restore only):** ~**7 seconds**.  
**Target:** &lt; 60 minutes for staging DR exercise — **met**.

### Notes from this test
- Exclude `targetgroupbindings.elbv2.k8s.aws` / Ingress / Jobs on re-restore for a clean `Completed` (see `velero/restore-dr-test.yaml`).
- Staging DB currently has no application tables; empty `\dt` after restore is correct, not a failed pg_dump.
- Free pod slots before DR pods can schedule (scale `ebs-csi-controller` / staging API temporarily if needed).

## Notes / known issues

- Free a pod slot before installing Velero if nodes show `Too many pods` (scale `snapshot-controller` or `aws-load-balancer-controller` to 1).
- IAM trust for Velero must be `system:serviceaccount:velero:velero` (not `cavendish-staging:velero`).
- After a full namespace delete, re-enable ArgoCD automated sync only when the restore is verified.
