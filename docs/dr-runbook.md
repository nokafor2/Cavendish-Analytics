# Disaster Recovery Runbook

> Populate after completing deliverable D12.

## Prerequisites

- Velero CLI installed and configured
- kubectl access to EKS cluster
- AWS CLI with IRSA or SSO credentials

## Procedure 1 — Velero Namespace Restore

```bash
# List available backups
velero backup get

# Delete namespace (test only)
kubectl delete namespace cavendish-production

# Restore from latest backup
velero restore create cavendish-prod-restore \
  --from-backup cavendish-daily-YYYYMMDD \
  --include-namespaces cavendish-production

# Verify
kubectl get pods -n cavendish-production
```

## Procedure 2 — PostgreSQL pg_dump Restore

```bash
# List S3 backups
aws s3 ls s3://cavendish-production-backups-ACCOUNT_ID/pg-dump/

# Download and restore
aws s3 cp s3://BUCKET/pg-dump/TIMESTAMP.sql.gz /tmp/
gunzip /tmp/TIMESTAMP.sql.gz
kubectl exec -it postgres-0 -n cavendish-production -- \
  psql -U cavendish -d cavendish -f /tmp/TIMESTAMP.sql
```

## DR Test Results

| Step | Start Time | End Time | Duration | Status |
|------|-----------|----------|----------|--------|
| Velero restore | | | | |
| pg_dump restore | | | | |
| Data verification | | | | |

**Total RTO:** _document here_
