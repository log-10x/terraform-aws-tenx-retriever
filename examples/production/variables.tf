variable "eks_cluster_name" {
  description = "Name of the existing EKS cluster to deploy to"
  type        = string
}

variable "tenx_api_key" {
  description = "Log10x API key for authentication"
  type        = string
  sensitive   = true
}

variable "namespace" {
  description = "Kubernetes namespace for the deployment"
  type        = string
  default     = "tenx-retriever"
}

variable "source_bucket_name" {
  description = "Existing S3 bucket for source logs"
  type        = string
}

variable "results_bucket_name" {
  description = "Existing S3 bucket for indexed results"
  type        = string
}
