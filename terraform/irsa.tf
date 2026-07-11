# IRSA roles — Pod-level AWS permissions without access keys.
# Workload roles (run in var.irsa_namespace) live here; controller roles that
# run in kube-system are defined in controllers-irsa.tf.

data "aws_iam_policy_document" "eks_oidc_assume_role" {
  for_each = toset([
    "analytics-api",
    "pg-backup", # must match chart ServiceAccount name (chart/templates/serviceaccount.yaml)
  ])

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:${var.irsa_namespace}:${each.key}"]
    }
  }
}

# Velero runs in the velero namespace (not irsa_namespace) — separate trust document.
data "aws_iam_policy_document" "velero_oidc_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:velero:velero"]
    }
  }
}

# Analytics API — read Secrets Manager DB credentials
resource "aws_iam_role" "analytics_api" {
  name               = "${var.project_name}-analytics-api-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.eks_oidc_assume_role["analytics-api"].json
}

resource "aws_iam_role_policy" "analytics_api_secrets" {
  name = "secrets-read"
  role = aws_iam_role.analytics_api.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = [aws_secretsmanager_secret.postgres.arn]
    }]
  })
}

# Postgres backup CronJob — write to S3
resource "aws_iam_role" "postgres_backup" {
  name               = "${var.project_name}-postgres-backup-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.eks_oidc_assume_role["pg-backup"].json
}

resource "aws_iam_role_policy" "postgres_backup_s3" {
  name = "s3-write"
  role = aws_iam_role.postgres_backup.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutObject", "s3:GetObject", "s3:ListBucket"]
      Resource = [aws_s3_bucket.pg_backups.arn, "${aws_s3_bucket.pg_backups.arn}/*"]
    }]
  })
}

# Velero — backup cluster resources to S3 (SA lives in namespace velero)
resource "aws_iam_role" "velero" {
  name               = "${var.project_name}-velero-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.velero_oidc_assume_role.json
}

resource "aws_iam_role_policy" "velero_s3" {
  name = "velero-s3"
  role = aws_iam_role.velero.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:*"]
      Resource = [aws_s3_bucket.velero.arn, "${aws_s3_bucket.velero.arn}/*"]
    }]
  })
}

# ── GitHub Actions OIDC ───────────────────────────────────────────────────────
# Account-wide provider — use data source so apply succeeds if it already exists
# (common when another project or a prior run created it).

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "github_actions_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/${var.github_repo}:*"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "${var.project_name}-github-actions"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume.json
}

resource "aws_iam_role_policy" "github_actions_deploy" {
  name = "deploy"
  role = aws_iam_role.github_actions.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:CompleteLayerUpload",
          "ecr:GetDownloadUrlForLayer",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart",
          "ecr:DescribeRepositories",
        ]
        Resource = [for r in aws_ecr_repository.services : r.arn]
      },
      {
        Effect   = "Allow"
        Action   = ["eks:DescribeCluster"]
        Resource = [module.eks.cluster_arn]
      }
    ]
  })
}
