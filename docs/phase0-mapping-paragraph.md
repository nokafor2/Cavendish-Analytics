# See docs/phase0-to-eks-mapping.md for the full mapping table.

After completing Phase 0, the manual k3s stack maps directly to the EKS production equivalent:

- **Nginx Ingress** → AWS Load Balancer Controller + ALB
- **Manual FreeDNS A record** → ExternalDNS + Route 53
- **cert-manager + Let's Encrypt** → ACM (certificate attached to ALB, never in Kubernetes)
- **HTTP-01 ACME challenge** → ACM internal DNS validation (hidden, but now understood)
- **TLS Secret in cluster** → ACM cert on ALB (simpler, but invisible without Phase 0)
- **nginx whitelist-source-range** → ALB inbound-cidrs annotation
- **Ingress delete = 404** → Identical on EKS; ArgoCD enforces GitOps decommission

Phase 0 is not optional — it is the conceptual foundation that makes every EKS automation explainable rather than magical.
