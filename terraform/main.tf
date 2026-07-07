terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
  }

  backend "s3" {
    bucket         = "cavendish-terraform-state"
    key            = "eks/terraform.tfstate"
    region         = "eu-west-2"
    dynamodb_table = "cavendish-terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "cavendish-analytics"
      ManagedBy   = "terraform"
      Environment = var.environment
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

# ── VPC ──────────────────────────────────────────────────────────────────────

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.project_name}-vpc"
  cidr = var.vpc_cidr

  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs

  enable_nat_gateway   = true
  single_nat_gateway   = var.environment == "staging"
  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}

# ── EKS Cluster ──────────────────────────────────────────────────────────────

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "${var.project_name}-${var.environment}"
  cluster_version = var.eks_cluster_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  enable_irsa = true

  # Grant the IAM identity running Terraform admin access to the cluster API.
  # Required for kubectl — without this, only node roles can authenticate.
  enable_cluster_creator_admin_permissions = true

  cluster_endpoint_public_access = true

  # metrics-server listens on 10251; the control plane must reach node/pod on this port.
  node_security_group_additional_rules = {
    ingress_cluster_to_metrics_server = {
      description                   = "Cluster API to metrics-server (port 10251)"
      protocol                      = "tcp"
      from_port                     = 10251
      to_port                       = 10251
      type                          = "ingress"
      source_cluster_security_group = true
    }
  }

  eks_managed_node_groups = {
    general = {
      min_size     = var.node_group_min_size
      max_size     = var.node_group_max_size
      desired_size = var.node_group_desired_size

      instance_types = var.node_instance_types
      capacity_type  = "ON_DEMAND"

      labels = {
        role = "general"
      }
    }
  }

  cluster_addons = {
    coredns    = { most_recent = true }
    kube-proxy = { most_recent = true }
    vpc-cni = {
      most_recent = true
      # Required for Kubernetes NetworkPolicy resources to be enforced (Week 2 D7).
      configuration_values = jsonencode({
        enableNetworkPolicy = "true"
      })
    }
    # HPA needs metrics-server to read Pod CPU utilisation (Week 2 D6).
    metrics-server = {
      most_recent                = true
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
      configuration_values = jsonencode({
        hostNetwork = {
          enabled = true
        }
      })
    }
    # aws-ebs-csi-driver + snapshot-controller → ebs-csi.tf (needs IRSA role first)
  }
}

# ── ECR Repositories ─────────────────────────────────────────────────────────

resource "aws_ecr_repository" "services" {
  for_each = toset(["analytics-api", "dashboard", "webhook-processor"])

  name                 = "${var.project_name}/${each.key}"
  image_tag_mutability = "MUTABLE"
  force_delete         = var.environment != "production"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# ── S3 Buckets ───────────────────────────────────────────────────────────────

resource "aws_s3_bucket" "pg_backups" {
  bucket = "${var.project_name}-${var.environment}-backups-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "velero" {
  bucket = "${var.project_name}-${var.environment}-velero-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_versioning" "pg_backups" {
  bucket = aws_s3_bucket.pg_backups.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "pg_backups" {
  bucket = aws_s3_bucket.pg_backups.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ── Route 53 ─────────────────────────────────────────────────────────────────

resource "aws_route53_zone" "main" {
  count = var.create_route53_zone ? 1 : 0
  name  = var.domain_name
}

# Delegate the child subdomain from an existing parent hosted zone.
# Looks up the parent zone (e.g. ayuadomain.com) and adds an NS record for
# domain_name (e.g. eks.ayuadomain.com) pointing at the new zone's nameservers,
# so the subdomain resolves without any manual Console step.
data "aws_route53_zone" "parent" {
  count        = var.create_route53_zone && var.parent_route53_zone_name != "" ? 1 : 0
  name         = var.parent_route53_zone_name
  private_zone = false
}

resource "aws_route53_record" "subdomain_delegation" {
  count   = var.create_route53_zone && var.parent_route53_zone_name != "" ? 1 : 0
  zone_id = data.aws_route53_zone.parent[0].zone_id
  name    = var.domain_name
  type    = "NS"
  ttl     = 300
  records = aws_route53_zone.main[0].name_servers
}

resource "aws_acm_certificate" "main" {
  domain_name               = var.domain_name
  subject_alternative_names = ["*.${var.domain_name}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# DNS validation — write the CNAME records ACM requires into our hosted zone,
# then wait for the certificate to be issued. Keyed by record name so the apex
# and wildcard (which share one validation record) do not collide.
resource "aws_route53_record" "acm_validation" {
  for_each = var.create_route53_zone ? {
    for dvo in aws_acm_certificate.main.domain_validation_options : dvo.resource_record_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }...
  } : {}

  zone_id         = aws_route53_zone.main[0].zone_id
  name            = each.key
  type            = each.value[0].type
  records         = [each.value[0].record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "main" {
  count                   = var.create_route53_zone ? 1 : 0
  certificate_arn         = aws_acm_certificate.main.arn
  validation_record_fqdns = [for r in aws_route53_record.acm_validation : r.fqdn]

  timeouts {
    create = "20m"
  }
}

# ── Secrets Manager ──────────────────────────────────────────────────────────

resource "aws_secretsmanager_secret" "postgres" {
  name = "${var.project_name}/${var.environment}/postgres"
}

resource "aws_secretsmanager_secret_version" "postgres" {
  secret_id = aws_secretsmanager_secret.postgres.id
  secret_string = jsonencode({
    username = var.postgres_username
    password = var.postgres_password
    host     = "postgres"
    database = var.postgres_database
  })
}
