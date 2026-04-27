variable "eks_cluster_name" {
  description = "Name of the existing EKS cluster to deploy to"
  type        = string
}

variable "tenx_api_key" {
  description = "Log10x API key for authentication"
  type        = string
  sensitive   = true
}
