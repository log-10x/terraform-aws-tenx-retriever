# Data sources to lookup existing EKS cluster
data "aws_eks_cluster" "target" {
  name = var.eks_cluster_name
}

data "aws_eks_cluster_auth" "target" {
  name = var.eks_cluster_name
}

data "aws_region" "current" {}

# Kubernetes provider configuration
provider "kubernetes" {
  host                   = data.aws_eks_cluster.target.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.target.certificate_authority[0].data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", var.eks_cluster_name, "--region", data.aws_region.current.id]
  }
}

# Helm provider configuration
provider "helm" {
  kubernetes = {
    host                   = data.aws_eks_cluster.target.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.target.certificate_authority[0].data)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", var.eks_cluster_name, "--region", data.aws_region.current.id]
    }
  }
}

module "tenx_retriever" {
  source = "../../"

  # Required: API key
  tenx_api_key = var.tenx_api_key

  # Required: OIDC provider info for IRSA
  oidc_provider_arn = data.aws_eks_cluster.target.identity[0].oidc[0].issuer
  oidc_provider     = replace(data.aws_eks_cluster.target.identity[0].oidc[0].issuer, "https://", "")

  # Optional: Resource naming prefix
  resource_prefix = var.eks_cluster_name

  # Kubernetes configuration
  namespace = var.namespace

  # Custom Helm values
  helm_values_file = "${path.module}/values.yaml"

  # Use existing S3 buckets
  create_s3_buckets                        = false
  tenx_retriever_index_source_bucket_name  = var.source_bucket_name
  tenx_retriever_index_results_bucket_name = var.results_bucket_name

  # CloudWatch Logs for query event logging
  tenx_retriever_query_log_group_name      = "/tenx/prod/retriever/query"
  tenx_retriever_query_log_group_retention = 14

  # Tags
  tags = {
    Environment = "production"
    Project     = "log10x-retriever"
    Example     = "production"
    ManagedBy   = "terraform"
  }
}
