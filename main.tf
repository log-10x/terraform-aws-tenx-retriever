# Local variables for resource naming and configuration
locals {
  # Merge tags with module defaults
  tags = merge(
    var.tags,
    {
      terraform-module         = "tenx-retriever"
      terraform-module-version = "v0.9.2"
      managed-by               = "terraform"
    }
  )

  # Use resource prefix for generated resource names
  resource_prefix = var.resource_prefix

  # Generate S3 bucket names with defaults
  index_source_bucket_name = coalesce(
    var.tenx_retriever_index_source_bucket_name,
    "${local.resource_prefix}-${data.aws_caller_identity.current.account_id}"
  )

  index_results_bucket_name = coalesce(
    var.tenx_retriever_index_results_bucket_name,
    local.index_source_bucket_name # Default to same bucket
  )

  # Generate SQS queue names with defaults
  index_queue_name = coalesce(
    var.tenx_retriever_index_queue_name,
    "${local.resource_prefix}-index-queue"
  )

  query_queue_name = coalesce(
    var.tenx_retriever_query_queue_name,
    "${local.resource_prefix}-query-queue"
  )

  subquery_queue_name = coalesce(
    var.tenx_retriever_subquery_queue_name,
    "${local.resource_prefix}-subquery-queue"
  )

  stream_queue_name = coalesce(
    var.tenx_retriever_stream_queue_name,
    "${local.resource_prefix}-stream-queue"
  )

  # Generate Kubernetes service account name
  service_account_name = coalesce(
    var.service_account_name,
    var.helm_release_name
  )

  # Generate IAM role name
  iam_role_name = coalesce(
    var.iam_role_name,
    "${local.resource_prefix}-irsa"
  )

  # CloudWatch Logs log group name (empty = disabled)
  query_log_group_name = var.tenx_retriever_query_log_group_name

  # OIDC provider for IRSA (IAM Roles for Service Accounts)
  # Passed in from parent module
  oidc_provider     = var.oidc_provider
  oidc_provider_arn = var.oidc_provider_arn
}

###########################################
# Data Sources
###########################################

# Get current AWS region and account information
data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

###########################################
# Infrastructure (SQS Queues and S3 Buckets)
###########################################

# Provision infrastructure (SQS queues and S3 buckets)
module "tenx_retriever_infra" {
  source  = "log-10x/tenx-retriever-infra/aws"
  version = ">= 0.9.2"

  # SQS Queue names
  tenx_retriever_index_queue_name    = local.index_queue_name
  tenx_retriever_query_queue_name    = local.query_queue_name
  tenx_retriever_subquery_queue_name = local.subquery_queue_name
  tenx_retriever_stream_queue_name   = local.stream_queue_name

  # SQS Queue configuration
  tenx_retriever_queue_message_retention  = var.tenx_retriever_queue_message_retention
  tenx_retriever_queue_visibility_timeout = var.tenx_retriever_queue_visibility_timeout
  tenx_retriever_queue_max_message_size   = var.tenx_retriever_queue_max_message_size
  tenx_retriever_queue_delay_seconds      = var.tenx_retriever_queue_delay_seconds
  tenx_retriever_queue_receive_wait_time  = var.tenx_retriever_queue_receive_wait_time

  # S3 Bucket configuration
  tenx_retriever_create_index_source_bucket  = var.create_s3_buckets
  tenx_retriever_index_source_bucket_name    = local.index_source_bucket_name
  tenx_retriever_create_index_results_bucket = var.create_s3_buckets
  tenx_retriever_index_results_bucket_name   = local.index_results_bucket_name
  tenx_retriever_index_results_path          = var.tenx_retriever_index_results_path

  # S3 trigger configuration
  tenx_retriever_index_trigger_prefix = var.tenx_retriever_index_trigger_prefix
  tenx_retriever_index_trigger_suffix = var.tenx_retriever_index_trigger_suffix

  # CloudWatch Logs configuration
  tenx_retriever_query_log_group_name      = local.query_log_group_name
  tenx_retriever_query_log_group_retention = var.tenx_retriever_query_log_group_retention
  tenx_retriever_create_query_log_group    = var.create_query_log_group

  # Observability — CloudWatch metric filters from retriever JVM log lines
  tenx_retriever_enable_observability_metrics = var.enable_observability_metrics
  tenx_retriever_metric_namespace             = var.metric_namespace
  tenx_retriever_metric_filter_name_prefix    = var.metric_filter_name_prefix
  tenx_retriever_metric_filter_dependencies   = var.metric_filter_dependencies

  tenx_retriever_user_supplied_tags = local.tags
}

###########################################
# Kubernetes Resources
###########################################

# Optionally create the Kubernetes namespace
# Controlled by var.create_namespace (default: false)
resource "kubernetes_namespace_v1" "tenx_retriever" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name = var.namespace
  }
}

# Create Kubernetes service account with IRSA annotation
# This service account will be used by retriever pods to assume the IAM role
# The IRSA annotation (eks.amazonaws.com/role-arn) links the service account to the IAM role created in iam.tf
# EKS automatically injects temporary AWS credentials into pods using this service account
resource "kubernetes_service_account_v1" "tenx_retriever" {
  metadata {
    name      = local.service_account_name
    namespace = var.namespace

    # IRSA annotation - this is the critical link between Kubernetes and AWS IAM
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.tenx_retriever.arn
    }
  }

  # Ensure the IAM role exists before creating the service account
  depends_on = [aws_iam_role.tenx_retriever]
}

###########################################
# Helm Release
###########################################

# Deploy retriever-10x Helm chart
resource "helm_release" "tenx_retriever" {
  name       = var.helm_release_name
  repository = "https://log-10x.github.io/helm-charts"
  chart      = "retriever-10x"
  namespace  = var.namespace
  version    = var.helm_chart_version

  # Two-layer values merging strategy:
  # 1. User-provided values file (application configuration) - replicas, scaling, resources, etc.
  # 2. Infrastructure overrides (from Terraform) - S3 buckets, SQS queues, service account
  values = concat(
    # Layer 1: User values file with application configuration
    var.helm_values_file != "" ? [file(var.helm_values_file)] : [],

    # Layer 2: Infrastructure overrides (S3, SQS, service account)
    [yamlencode({
      # Use Terraform-created service account instead of Helm-created one
      serviceAccount = {
        create = false
        name   = kubernetes_service_account_v1.tenx_retriever.metadata[0].name
      }

      # S3 bucket configuration (root-level values)
      inputBucket = module.tenx_retriever_infra.index_source_bucket_name
      indexBucket = module.tenx_retriever_infra.index_write_container

      # SQS queue configuration (root-level values)
      indexQueueUrl    = module.tenx_retriever_infra.index_queue_url
      queryQueueUrl    = module.tenx_retriever_infra.query_queue_url
      subQueryQueueUrl = module.tenx_retriever_infra.subquery_queue_url
      streamQueueUrl   = module.tenx_retriever_infra.stream_queue_url

      # CloudWatch Logs configuration
      queryLogGroup = module.tenx_retriever_infra.query_log_group_name
    })]
  )

  # Set sensitive API key separately to avoid showing in Terraform state
  set_sensitive = [{
    name  = "log10xApiKey"
    value = var.tenx_api_key
  }]

  # Ensure infrastructure and service account exist before deploying
  depends_on = [
    module.tenx_retriever_infra,
    kubernetes_service_account_v1.tenx_retriever
  ]
}
