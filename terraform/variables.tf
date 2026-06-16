variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "eu-west-2"
}

variable "environment" {
  description = "Deployment environment (staging | production)"
  type        = string
  default     = "staging"
}

variable "project_name" {
  description = "Project name prefix for all resources"
  type        = string
  default     = "cavendish"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "public_subnet_cids" {
  description = "Public subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
}

variable "eks_cluster_version" {
  description = "EKS Kubernetes version"
  type        = string
  default     = "1.29"
}

variable "node_group_min_size" {
  type    = number
  default = 2
}

variable "node_group_max_size" {
  type    = number
  default = 6
}

variable "node_group_desired_size" {
  type    = number
  default = 2
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "domain_name" {
  description = "Base domain for Cavendish services"
  type        = string
}

variable "create_route53_zone" {
  description = "Create a new Route 53 hosted zone"
  type        = bool
  default     = true
}

variable "postgres_username" {
  type      = string
  sensitive = true
}

variable "postgres_password" {
  type      = string
  sensitive = true
}

variable "postgres_database" {
  type    = string
  default = "cavendish"
}

variable "irsa_namespace" {
  description = "Kubernetes namespace for IRSA service accounts"
  type        = string
  default     = "cavendish-staging"
}

variable "github_org" {
  description = "GitHub organisation for OIDC trust"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository for OIDC trust"
  type        = string
  default     = "cavendish-analytics-eks"
}
