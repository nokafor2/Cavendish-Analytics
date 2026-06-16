# Phase 0 → EKS Component Mapping

| Phase 0 (Manual k3s) | EKS Production Equivalent | What Phase 0 Teaches |
|----------------------|---------------------------|----------------------|
| Nginx Ingress Controller + IngressClass | AWS Load Balancer Controller + ALB | What an Ingress controller does — translates Ingress resources into load balancer routing rules |
| Afraid DNS A record (manual) | ExternalDNS + Route 53 | DNS must point to your load balancer; ExternalDNS automates by watching Ingress annotations |
| cert-manager + ClusterIssuer | AWS Certificate Manager (ACM) | Both manage TLS lifecycle; cert-manager shows the ACME protocol in action |
| Let's Encrypt HTTP-01 challenge | ACM internal validation | Proves domain ownership before certificate issuance |
| TLS Secret in Kubernetes | ACM cert attached to ALB | On EKS the cert never touches Kubernetes — attached directly to the ALB |
| nginx whitelist-source-range | ALB inbound-cidrs annotation | Both restrict by source IP at the reverse proxy layer |
| Ingress deleted = 404 | Same on EKS — ArgoCD enforces it | Removing an Ingress resource removes the routing rule |

## Key Interview Answers This Mapping Enables

- **HTTP-01 challenge:** Let's Encrypt serves a token at `/.well-known/acme-challenge/{token}`. Port 80 must be open. cert-manager creates a temporary Ingress rule automatically.
- **Why ExternalDNS exists:** Manual DNS (Phase 0 Day 1) must be repeated every time the load balancer IP changes. ExternalDNS watches Ingress annotations and calls Route 53 automatically.
- **Why ACM hides the challenge:** AWS validates domain ownership internally via Route 53 or email — no temporary Ingress needed.
- **Decommission pattern:** Delete the Ingress manifest → routing rule removed → subdomain returns 404. DNS record persists but is unreachable.
