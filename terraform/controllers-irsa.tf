# Tuesday — IRSA roles for cluster add-ons that run in the kube-system namespace.
# Uses the community iam-role-for-service-accounts-eks module, which ships the
# maintained IAM policies for each controller (no hand-written JSON to drift).
# NOTE: these controllers live in kube-system, not the workload namespace —
# that is why they are defined here and not in irsa.tf.

module "alb_controller_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name                              = "${var.project_name}-alb-controller-${var.environment}"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    eks = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

module "external_dns_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name                  = "${var.project_name}-external-dns-${var.environment}"
  attach_external_dns_policy = true
  # Scope ExternalDNS to the project hosted zone only (least privilege).
  external_dns_hosted_zone_arns = var.create_route53_zone ? [aws_route53_zone.main[0].arn] : ["arn:aws:route53:::hostedzone/*"]

  oidc_providers = {
    eks = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:external-dns"]
    }
  }
}

module "cluster_autoscaler_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name                        = "${var.project_name}-cluster-autoscaler-${var.environment}"
  attach_cluster_autoscaler_policy = true
  cluster_autoscaler_cluster_names = [module.eks.cluster_name]

  oidc_providers = {
    eks = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:cluster-autoscaler"]
    }
  }
}

# Secrets Store CSI Driver: the driver itself needs no AWS permissions.
# Workloads (e.g. analytics-api) fetch secrets using their own IRSA role
# defined in irsa.tf — no dedicated controller role required here.
