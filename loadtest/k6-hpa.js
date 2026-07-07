// k6 load test for HPA (Week 2 Monday — D6).
// Drives CPU on /api/v1/analytics/compute so the analytics-api HPA scales out.
//
// Run from your laptop (hits the public ALB):
//   k6 run -e API_URL=https://api.eks.ayuadomain.com loadtest/k6-hpa.js
//
// Or port-forward and test in-cluster:
//   kubectl port-forward -n cavendish-staging svc/analytics-api 8000:8000
//   k6 run -e API_URL=http://localhost:8000 loadtest/k6-hpa.js

import http from 'k6/http';
import { check, sleep } from 'k6';

const API_URL = __ENV.API_URL || 'https://api.eks.ayuadomain.com';

export const options = {
  stages: [
    { duration: '30s', target: 20 },   // ramp up
    { duration: '3m', target: 60 },  // sustained load — target ≥5 replicas at 70% CPU
    { duration: '30s', target: 0 },  // ramp down
  ],
  thresholds: {
    http_req_failed: ['rate<0.05'],
    http_req_duration: ['p(95)<5000'],
  },
};

export default function () {
  const res = http.get(`${API_URL}/api/v1/analytics/compute?intensity=8`);
  check(res, {
    'status is 200': (r) => r.status === 200,
  });
  sleep(0.05);
}
