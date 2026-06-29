# EBS CSI driver requires an IRSA role before the addon can reach ACTIVE.
# Installing it inside module.eks cluster_addons without service_account_role_arn
# leaves the controller unable to call AWS APIs and the addon times out.

module "ebs_csi_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name             = "${var.project_name}-ebs-csi-${var.environment}"
  attach_ebs_csi_policy = true

  oidc_providers = {
    eks = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

data "aws_eks_addon_version" "ebs_csi" {
  addon_name         = "aws-ebs-csi-driver"
  kubernetes_version = module.eks.cluster_version
  most_recent        = true
}

data "aws_eks_addon_version" "snapshot_controller" {
  addon_name         = "snapshot-controller"
  kubernetes_version = module.eks.cluster_version
  most_recent        = true
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = data.aws_eks_addon_version.ebs_csi.version
  service_account_role_arn    = module.ebs_csi_irsa_role.iam_role_arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  timeouts {
    create = "30m"
  }

  depends_on = [
    module.eks,
    module.ebs_csi_irsa_role,
  ]
}

resource "aws_eks_addon" "snapshot_controller" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "snapshot-controller"
  addon_version               = data.aws_eks_addon_version.snapshot_controller.version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  depends_on = [aws_eks_addon.ebs_csi]
}
