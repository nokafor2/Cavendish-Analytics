# HPA Load Test — Week 2 Monday (D6)

**Cluster:** `cavendish-staging`  
**Target:** `analytics-api` Deployment  
**HPA:** min 2 / max 10 / CPU 70%  
**Endpoint:** `GET /api/v1/analytics/compute?intensity=8`

## Prerequisites

- `metrics-server` EKS add-on ACTIVE
- HPA enabled in `chart/values.staging.yaml` (`hpa.enabled: true`)
- [k6](https://k6.io/docs/get-started/installation/) installed locally

## Commands run

```bash
# Terminal 1 — watch HPA + replicas during the test
kubectl get hpa analytics-api -n cavendish-staging -w

# Terminal 2 — run load test (replace URL if your domain differs)
k6 run -e API_URL=https://api.eks.ayuadomain.com loadtest/k6-hpa.js
```

## Results

| Time (UTC) | HPA replicas | CPU % (avg) | Notes |
|------------|--------------|-------------|-------|
| start      | 2            | ~5%         | baseline |
| +2m        |              |             | under load |
| +4m        |              |             | peak |
| +5m        |              |             | ramp-down |

**Pass criteria (D6):** replicas scale from **2 → ≥5** under sustained load, then scale back down after k6 finishes.

## k6 summary

```
(paste k6 end-of-run summary here)
```

## HPA describe snapshot (peak)

```
(paste: kubectl describe hpa analytics-api -n cavendish-staging)
```

## Notes

- If HPA stays at 2: confirm `metrics-server` pods are Running (`kubectl get pods -n kube-system -l app.kubernetes.io/name=metrics-server`) and that Pod CPU **requests** are set (HPA uses % of request, not limit).
- If k6 gets 403/timeout: confirm NetworkPolicy ALB rule uses the correct `networkPolicy.vpcCidr` (`10.0.0.0/16`).
