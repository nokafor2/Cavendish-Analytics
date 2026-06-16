# HPA Load Test Evidence

> Populate after completing deliverable D6.

## k6 Load Test Command

```bash
k6 run --vus 50 --duration 5m load-test.js
```

## HPA Scale Observation

```
# Replace with kubectl get hpa -w output showing scale 2 → ≥5:
# kubectl get hpa analytics-api -n cavendish-production -w
```

## Results

| Metric | Before Load | Peak Load | After Scale |
|--------|------------|-----------|-------------|
| Replicas | 2 | | ≥5 |
| CPU Utilisation | | | |
| Request Rate | | | |
