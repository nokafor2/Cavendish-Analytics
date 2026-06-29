output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL for IRSA"
  value       = module.eks.cluster_oidc_issuer_url
}

output "vpc_id" {
  description = "VPC ID (needed for the AWS Load Balancer Controller Helm install)"
  value       = module.vpc.vpc_id
}

output "ecr_repository_urls" {
  description = "ECR repository URLs for all services"
  value       = { for k, v in aws_ecr_repository.services : k => v.repository_url }
}

output "pg_backups_bucket" {
  description = "S3 bucket for PostgreSQL pg_dump backups"
  value       = aws_s3_bucket.pg_backups.id
}

output "velero_bucket" {
  description = "S3 bucket for Velero cluster backups"
  value       = aws_s3_bucket.velero.id
}

output "acm_certificate_arn" {
  description = "ACM certificate ARN for ALB Ingress"
  value       = aws_acm_certificate.main.arn
}

output "route53_zone_id" {
  description = "Route 53 hosted zone ID"
  value       = var.create_route53_zone ? aws_route53_zone.main[0].zone_id : null
}

output "route53_zone_name_servers" {
  description = "Nameservers for the created hosted zone (delegated automatically when parent_route53_zone_name is set)"
  value       = var.create_route53_zone ? aws_route53_zone.main[0].name_servers : null
}

output "irsa_analytics_api_role_arn" {
  description = "IRSA role ARN for analytics-api ServiceAccount"
  value       = aws_iam_role.analytics_api.arn
}

output "irsa_postgres_backup_role_arn" {
  description = "IRSA role ARN for pg-backup CronJob"
  value       = aws_iam_role.postgres_backup.arn
}

output "irsa_velero_role_arn" {
  description = "IRSA role ARN for Velero"
  value       = aws_iam_role.velero.arn
}

output "irsa_alb_controller_role_arn" {
  description = "IRSA role ARN for the AWS Load Balancer Controller ServiceAccount"
  value       = module.alb_controller_irsa.iam_role_arn
}

output "irsa_external_dns_role_arn" {
  description = "IRSA role ARN for the ExternalDNS ServiceAccount"
  value       = module.external_dns_irsa.iam_role_arn
}

output "irsa_cluster_autoscaler_role_arn" {
  description = "IRSA role ARN for the Cluster Autoscaler ServiceAccount"
  value       = module.cluster_autoscaler_irsa.iam_role_arn
}

output "github_actions_role_arn" {
  description = "IAM role ARN for GitHub Actions OIDC"
  value       = aws_iam_role.github_actions.arn
}

output "postgres_secret_arn" {
  description = "Secrets Manager ARN for PostgreSQL credentials"
  value       = aws_secretsmanager_secret.postgres.arn
  sensitive   = true
}
