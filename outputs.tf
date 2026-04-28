###########################################
# Infrastructure Outputs
###########################################

output "index_queue_url" {
  description = "URL of the index SQS queue"
  value       = module.tenx_retriever_infra.index_queue_url
}

output "query_queue_url" {
  description = "URL of the query SQS queue"
  value       = module.tenx_retriever_infra.query_queue_url
}

output "subquery_queue_url" {
  description = "URL of the sub-query SQS queue"
  value       = module.tenx_retriever_infra.subquery_queue_url
}

output "stream_queue_url" {
  description = "URL of the stream SQS queue"
  value       = module.tenx_retriever_infra.stream_queue_url
}

output "index_source_bucket_name" {
  description = "Name of the S3 bucket for source files to be indexed"
  value       = module.tenx_retriever_infra.index_source_bucket_name
}

output "index_results_bucket_name" {
  description = "Name of the S3 bucket for indexing results"
  value       = module.tenx_retriever_infra.index_results_bucket_name
}

output "index_write_container" {
  description = "S3 path for writing index results (bucket or bucket/prefix)"
  value       = module.tenx_retriever_infra.index_write_container
}

output "query_log_group_name" {
  description = "Name of the CloudWatch Logs log group for query event logging (empty if disabled)"
  value       = module.tenx_retriever_infra.query_log_group_name
}

output "query_log_group_arn" {
  description = "ARN of the CloudWatch Logs log group for query event logging (empty if disabled). Constructed from name + region + account when the consumer brings their own log group via create_query_log_group = false."
  value       = module.tenx_retriever_infra.query_log_group_arn
}

###########################################
# Observability Outputs
###########################################
# Surface canonical retriever metric names so consumers can wire alarms +
# dashboards without reaching into module.tenx_retriever_infra.

output "observability_metric_namespace" {
  description = "CloudWatch namespace where retriever observability metrics are published. Empty when observability metrics are disabled."
  value       = module.tenx_retriever_infra.observability_metric_namespace
}

output "observability_metric_names" {
  description = "Map of canonical retriever metric names (for consumer alarms/dashboards). Keys: stack_overflow, scan_complete, stream_worker_complete, stream_worker_skipped, results_writer_complete, launch_failed, bloom_blobs_scanned, bloom_blobs_matched. Empty values when observability metrics are disabled."
  value       = module.tenx_retriever_infra.observability_metric_names
}

###########################################
# IAM Outputs
###########################################

output "iam_role_arn" {
  description = "ARN of the IAM role for IRSA"
  value       = aws_iam_role.tenx_retriever.arn
}

output "iam_role_name" {
  description = "Name of the IAM role for IRSA"
  value       = aws_iam_role.tenx_retriever.name
}

###########################################
# Kubernetes Outputs
###########################################

output "namespace" {
  description = "Kubernetes namespace where retriever is deployed"
  value       = var.namespace
}

output "service_account_name" {
  description = "Name of the Kubernetes service account"
  value       = kubernetes_service_account_v1.tenx_retriever.metadata[0].name
}

###########################################
# Helm Outputs
###########################################

output "helm_release_name" {
  description = "Name of the Helm release"
  value       = helm_release.tenx_retriever.name
}

output "helm_release_status" {
  description = "Status of the Helm release"
  value       = helm_release.tenx_retriever.status
}

output "helm_release_version" {
  description = "Version of the deployed Helm chart"
  value       = helm_release.tenx_retriever.version
}

