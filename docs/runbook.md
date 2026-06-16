# Platform Operations Runbook

## Daily Checks

- [ ] All Pods Running in cavendish-staging and cavendish-production
- [ ] Prometheus targets UP (Grafana → Status → Targets)
- [ ] No firing alerts in AlertManager
- [ ] Latest pg_dump backup in S3 (< 6 hours old)
- [ ] Latest Velero backup succeeded (< 24 hours old)

## Common Operations

### Scale Analytics API manually (emergency)

```bash
kubectl scale deployment analytics-api -n cavendish-production --replicas=5
```

### Check IRSA identity from a Pod

```bash
kubectl exec -it deploy/analytics-api -n cavendish-production -- aws sts get-caller-identity
```

### Force ArgoCD sync

```bash
argocd app sync cavendish-production
```

### View HPA status

```bash
kubectl get hpa -n cavendish-production -w
```

### Trigger manual Velero backup

```bash
velero backup create cavendish-manual-$(date +%Y%m%d) \
  --include-namespaces cavendish-production
```

## Incident Response

1. Check Grafana dashboard for anomaly (request rate, CPU, DB connections)
2. Check AlertManager for firing rules
3. Check Pod logs: `kubectl logs -l app.kubernetes.io/name=analytics-api -n cavendish-production`
4. If database issue: check postgres-exporter metrics, verify PVC bound
5. If full namespace failure: follow `docs/dr-runbook.md`

## Escalation

| Severity | Response Time | Action |
|----------|--------------|--------|
| P1 — Client-facing outage | 15 min | Page on-call, initiate DR if needed |
| P2 — Degraded performance | 1 hour | Scale HPA, investigate metrics |
| P3 — Non-critical alert | Next business day | Review and resolve |
