# Cavendish Analytics — Estimated AWS Costs

> Update with actual values after Terraform apply.

| Resource | Staging (monthly) | Production (monthly) |
|----------|-------------------|----------------------|
| EKS control plane | $73 | $73 |
| EC2 nodes (2× t3.medium) | ~$60 | ~$120 (4 nodes peak) |
| NAT Gateway | ~$32 | ~$32 |
| EBS volumes (10Gi / 50Gi) | ~$1 | ~$5 |
| S3 (backups + velero) | ~$2 | ~$5 |
| Route 53 hosted zone | $0.50 | $0.50 |
| ACM certificate | Free | Free |
| ECR storage | ~$1 | ~$2 |
| **Estimated total** | **~$170/mo** | **~$240/mo** |

## Cost Optimisation Notes

- Single NAT gateway in staging (Terraform variable)
- Cluster Autoscaler scales nodes down during off-peak
- Velero backup TTL: 30 days (720h)
- Consider Spot instances for non-production node groups
