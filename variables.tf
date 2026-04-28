###########################################
# Required Variables
###########################################

variable "tenx_api_key" {
  description = "Log10x API key for authentication"
  type        = string
  sensitive   = true
}

variable "oidc_provider_arn" {
  description = "ARN of the OIDC provider for the EKS cluster (required for IRSA). Example: arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE"
  type        = string
}

variable "oidc_provider" {
  description = "OIDC provider URL without https:// prefix (required for IRSA). Example: oidc.eks.us-east-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE"
  type        = string
}

###########################################
# Infrastructure Configuration
###########################################

variable "resource_prefix" {
  description = "Prefix for generated resource names (S3 buckets, SQS queues, IAM roles). Recommended to use cluster name or environment identifier."
  type        = string
  default     = "tenx-retriever"
}

variable "tenx_retriever_index_source_bucket_name" {
  description = "Name of S3 bucket for source files to be indexed. If empty, module will generate a name."
  type        = string
  default     = ""
}

variable "tenx_retriever_index_results_bucket_name" {
  description = "Name of S3 bucket for indexing results. If empty, uses same as source bucket."
  type        = string
  default     = ""
}

variable "tenx_retriever_index_queue_name" {
  description = "Name of the index SQS queue. If empty, module will generate a name."
  type        = string
  default     = ""
}

variable "tenx_retriever_query_queue_name" {
  description = "Name of the query SQS queue. If empty, module will generate a name."
  type        = string
  default     = ""
}

variable "tenx_retriever_subquery_queue_name" {
  description = "Name of the sub-query SQS queue. If empty, module will generate a name."
  type        = string
  default     = ""
}

variable "tenx_retriever_stream_queue_name" {
  description = "Name of the stream SQS queue. If empty, module will generate a name."
  type        = string
  default     = ""
}

variable "create_s3_buckets" {
  description = "Whether to create S3 buckets (true) or use existing ones (false)"
  type        = bool
  default     = true
}

variable "tenx_retriever_queue_message_retention" {
  description = "Message retention period in seconds for SQS queues (default: 4 days)"
  type        = number
  default     = 345600
}

variable "tenx_retriever_queue_visibility_timeout" {
  description = "Visibility timeout for SQS queues in seconds (default: 30)"
  type        = number
  default     = 30
}

variable "tenx_retriever_queue_max_message_size" {
  description = "Maximum message size for SQS queues in bytes (default: 256 KB)"
  type        = number
  default     = 262144
}

variable "tenx_retriever_queue_delay_seconds" {
  description = "Delivery delay for SQS queues in seconds (default: 0)"
  type        = number
  default     = 0
}

variable "tenx_retriever_queue_receive_wait_time" {
  description = "Receive wait time for SQS queues in seconds for long polling (default: 20)"
  type        = number
  default     = 20
}

variable "tenx_retriever_index_results_path" {
  description = "Path within the results bucket where indexing results will be stored (default: 'indexing-results/')"
  type        = string
  default     = "indexing-results/"
}

variable "tenx_retriever_index_trigger_prefix" {
  description = "S3 object prefix that triggers indexing (e.g., 'app/'). If empty, uses default 'app/'."
  type        = string
  default     = "app/"
}

variable "tenx_retriever_index_trigger_suffix" {
  description = "S3 object suffix that triggers indexing (e.g., '.log'). If empty, all objects trigger indexing."
  type        = string
  default     = ""
}

variable "tenx_retriever_query_log_group_name" {
  description = "Name of the CloudWatch Logs log group for query event logging. If empty, no log group is created and query event logging is disabled."
  type        = string
  default     = ""
}

variable "tenx_retriever_query_log_group_retention" {
  description = "Number of days to retain query event logs in CloudWatch Logs (default: 7)"
  type        = number
  default     = 7
}

variable "create_query_log_group" {
  description = "Whether the module should create the CloudWatch log group for query event logging. Set false to BYO an existing log group managed outside this module — still requires tenx_retriever_query_log_group_name to wire IAM/JVM."
  type        = bool
  default     = true
}

###########################################
# Observability — CloudWatch Metric Filters
###########################################
# Translates retriever JVM log lines (scan/worker/results stages,
# StackOverflowError, bloom blob counts) into queryable CloudWatch metrics.
# Consumers reference the canonical metric names via the
# `observability_metric_names` output to build alarms/dashboards.

variable "enable_observability_metrics" {
  description = "Whether to create CloudWatch metric filters that extract operational metrics from the query log group. Requires tenx_retriever_query_log_group_name to be set."
  type        = bool
  default     = true
}

variable "metric_namespace" {
  description = "CloudWatch namespace for retriever observability metrics."
  type        = string
  default     = "Log10x/Retriever"
}

variable "metric_filter_name_prefix" {
  description = "Prefix for CloudWatch metric filter names. Empty (default) derives from tenx_retriever_query_log_group_name. Override to maintain naming continuity across module upgrades."
  type        = string
  default     = ""
}

variable "metric_filter_dependencies" {
  description = "Optional list of resources the metric filters should wait for before being created. Required when `create_query_log_group = false` (BYO log group): pass the externally-managed log group resource so Terraform can sequence operations correctly."
  type        = list(any)
  default     = []
}

###########################################
# Kubernetes Configuration
###########################################

variable "namespace" {
  description = "Kubernetes namespace to deploy into"
  type        = string
  default     = "default"
}

variable "create_namespace" {
  description = "Whether to create the Kubernetes namespace"
  type        = bool
  default     = false
}

variable "service_account_name" {
  description = "Name of the Kubernetes service account (defaults to helm_release_name if empty)"
  type        = string
  default     = ""
}

###########################################
# Helm Chart Configuration
###########################################

variable "helm_release_name" {
  description = "Helm release name"
  type        = string
  default     = "tenx-retriever"
}

variable "helm_chart_version" {
  description = "Version of the retriever-10x Helm chart"
  type        = string
  default     = "1.0.9"
}

variable "helm_values_file" {
  description = "Path to custom Helm values YAML file for application configuration (replicas, scaling, resources, etc.)"
  type        = string
  default     = ""
}

###########################################
# IAM Configuration
###########################################

variable "iam_role_name" {
  description = "Name of the IAM role for IRSA (defaults to '{resource_prefix}-irsa' if empty)"
  type        = string
  default     = ""
}

variable "additional_iam_policies" {
  description = "Additional IAM policy statements to attach to the IRSA role"
  type = list(object({
    sid       = optional(string)
    effect    = string
    actions   = list(string)
    resources = list(string)
  }))
  default = []
}

###########################################
# Tagging
###########################################

variable "tags" {
  description = "Tags to apply to AWS resources"
  type        = map(string)
  default     = {}
}
