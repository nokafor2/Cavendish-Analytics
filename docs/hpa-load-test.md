# HPA Load Test — Week 2 Monday (D6)

**Cluster:** `cavendish-staging`  
**Target:** `analytics-api` Deployment  
**HPA:** min 2 / max 10 / CPU 70%  
**Endpoint:** `GET /api/v1/analytics/compute?intensity=8`  
**Date run:** 2026-07-07 (UTC)

## Prerequisites

- `metrics-server` EKS add-on ACTIVE
- HPA enabled in `chart/values.staging.yaml` (`hpa.enabled: true`)
- [k6](https://k6.io/docs/get-started/installation/) installed locally
- ALB targets healthy (`curl https://api.eks.ayuadomain.com/health` → 200)

## Commands run

```bash
# Terminal 1 — watch HPA + replicas during the test
kubectl get hpa analytics-api -n cavendish-staging -w

# Terminal 2 — run load test (Windows: reopen PowerShell after winget install, or use full path)
k6 run -e API_URL=https://api.eks.ayuadomain.com loadtest/k6-hpa.js
# Or: & "C:\Program Files\k6\k6.exe" run -e API_URL=https://api.eks.ayuadomain.com loadtest/k6-hpa.js
```

## Results

| Time (approx) | HPA replicas | CPU % (avg) | Notes |
|---------------|--------------|-------------|-------|
| start         | 2            | ~2–5%       | baseline |
| +30s          | 4            | rising      | ramp to 20 VUs; first scale-out |
| +1–2m         | 8            | above 70%   | sustained load (60 VUs) |
| peak (~+2m)   | **10**       | above 70%   | hit `maxReplicas`; some 504/timeouts under overload |
| +4m           | 4            | falling     | k6 ramp-down begins |
| +5m (post)    | 2            | ~2%         | scaled back to `minReplicas` |

**D6 pass criteria:** replicas scale from **2 → ≥5** under sustained load, then scale back down after k6 finishes.

**Verdict: PASS (HPA scaling).** HPA scaled **2 → 4 → 8 → 10** (max) during the sustained stage and returned to **2** after load ended. k6 latency/error thresholds were **not** met (see below) — likely due to ALB/backend saturation while scaling up.

## k6 summary

```
     scenarios: (100.00%) 1 scenario, 60 max VUs, 4m30s max duration (incl. graceful stop):
              * default: Up to 60 looping VUs for 4m0s over 3 stages (gracefulRampDown: 30s, gracefulStop: 30s)

  █ THRESHOLDS

    http_req_duration
    ✗ 'p(95)<5000' p(95)=12.03s

    http_req_failed
    ✗ 'rate<0.05' rate=33.23%

  █ TOTAL RESULTS

    checks_total.......: 3683   15.320399/s
    checks_succeeded...: 66.76% 2459 out of 3683
    checks_failed......: 33.23% 1224 out of 3683

    ✗ status is 200
      ↳  66% — ✓ 2459 / ✗ 1224

    HTTP
    http_req_duration..............: avg=2.26s min=12.11ms med=956.34ms max=34.31s p(90)=4.02s p(95)=12.03s
      { expected_response:true }...: avg=3.25s min=97.71ms med=1.78s    max=34.31s p(90)=6.43s p(95)=14.63s
    http_req_failed................: 33.23% 1224 out of 3683
    http_reqs......................: 3683   15.320399/s

    EXECUTION
    iteration_duration.............: avg=2.32s min=63.05ms med=1.01s    max=34.36s p(90)=4.07s p(95)=12.08s
    iterations.....................: 3683   15.320399/s
    vus............................: 3      min=1            max=60
    vus_max........................: 60     min=60           max=60

    NETWORK
    data_received..................: 1.0 MB 4.3 kB/s
    data_sent......................: 272 kB 1.1 kB/s
```

**k6 threshold verdict: FAIL.** 33% of requests failed (likely 504 Gateway Timeout while backends were scaling). Successful requests had high tail latency (p95 12s). HPA behaviour is still valid evidence for D6; tighten load or raise `maxReplicas`/pod CPU requests if you need k6 thresholds green on a re-run.

## HPA describe snapshot (post-test)

```
Name:                                                  analytics-api
Namespace:                                             cavendish-staging
Reference:                                             Deployment/analytics-api
Metrics:                                               ( current / target )
  resource cpu on pods  (as a percentage of request):  2% (2m) / 70%
Min replicas:                                          2
Max replicas:                                          10
Deployment pods:                                       2 current / 2 desired
Conditions:
  Type            Status  Reason
  ----            ------  ------
  AbleToScale     True    ReadyForNewScale
  ScalingActive   True    ValidMetricFound
  ScalingLimited  True    TooFewReplicas
Events:
  Normal   SuccessfulRescale   New size: 10; reason: cpu resource utilization above target
  Normal   SuccessfulRescale   New size: 8;  reason: cpu resource utilization above target
  Normal   SuccessfulRescale   New size: 4;  reason: cpu resource utilization above target
  Normal   SuccessfulRescale   New size: 8;  reason: All metrics below target
  Normal   SuccessfulRescale   New size: 4;  reason: All metrics below target
  Normal   SuccessfulRescale   New size: 2;  reason: All metrics below target
```

## Troubleshooting

- **`cpu: <unknown>/70%`** — Metrics API not working. Run `kubectl top pods -n cavendish-staging`. If it fails, apply Terraform (metrics-server `hostNetwork` + node SG port 10251) and wait ~1 min.
- **HPA stays at 2** — CPU must exceed 70% of **requests** (100m), not limits. Increase k6 `intensity` or VUs in `loadtest/k6-hpa.js`.
- **100% k6 failures / 504** — ALB targets unhealthy. Check NetworkPolicy (`allow-alb-ingress` must match `analytics-api` pods) and ingress annotation `alb.ingress.kubernetes.io/healthcheck-path: /health`.
- **HPA scales but k6 errors remain** — Normal during aggressive ramp; pods need time to become ready. Consider a longer ramp stage or lower peak VUs for a clean threshold pass.
