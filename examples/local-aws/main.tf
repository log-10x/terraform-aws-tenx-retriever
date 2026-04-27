# Local Testing with Real AWS
# Deploys Retriever to minikube using real AWS S3/SQS.
# Requires AWS credentials with permissions for S3 and SQS.
#
# Prerequisites:
#   - minikube running
#   - AWS credentials configured (env vars or profile)
#
# Usage:
#   terraform init
#   terraform apply \
#     -var="tenx_api_key=YOUR_API_KEY" \
#     -var="aws_access_key_id=$AWS_ACCESS_KEY_ID" \
#     -var="aws_secret_access_key=$AWS_SECRET_ACCESS_KEY"

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.0"
    }
  }
}

# Configure AWS provider - uses your credentials (env vars, profile, or instance role)
provider "aws" {
  region = var.aws_region
}

# Kubernetes provider - uses current kubectl context
provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "minikube"
}

# Helm provider
provider "helm" {
  kubernetes = {
    config_path    = "~/.kube/config"
    config_context = "minikube"
  }
}

###########################################
# Variables
###########################################

variable "tenx_api_key" {
  description = "Log10x API key (get at console.log10x.com)"
  type        = string
  sensitive   = true
}

variable "aws_access_key_id" {
  description = "AWS access key ID (passed to pods in minikube)"
  type        = string
  sensitive   = true
}

variable "aws_secret_access_key" {
  description = "AWS secret access key (passed to pods in minikube)"
  type        = string
  sensitive   = true
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "namespace" {
  description = "Kubernetes namespace for retriever"
  type        = string
  default     = "log10x-retriever"
}

variable "resource_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "retriever"
}

variable "local_config_path" {
  description = "Path to a local config directory mounted into minikube (e.g. /mnt/tenx-config). When set, overrides the built-in /etc/tenx/config in retriever pods. Use with: minikube mount <host-path>:<this-path>"
  type        = string
  default     = ""
}

###########################################
# Infrastructure (S3/SQS via real AWS)
###########################################

module "retriever_infra" {
  source = "log-10x/tenx-retriever-infra/aws"

  tenx_retriever_index_queue_name    = "${var.resource_prefix}-index-queue"
  tenx_retriever_query_queue_name    = "${var.resource_prefix}-query-queue"
  tenx_retriever_subquery_queue_name = "${var.resource_prefix}-subquery-queue"
  tenx_retriever_stream_queue_name   = "${var.resource_prefix}-stream-queue"

  tenx_retriever_create_index_source_bucket  = true
  tenx_retriever_index_source_bucket_name    = "${var.resource_prefix}-logs"
  tenx_retriever_create_index_results_bucket = true
  tenx_retriever_index_results_bucket_name   = "${var.resource_prefix}-index"
  tenx_retriever_index_results_path          = "indexed/"

  tenx_retriever_index_trigger_prefix = ""
  tenx_retriever_index_trigger_suffix = ".log"

  # CloudWatch Logs for query event logging
  tenx_retriever_query_log_group_name      = "/tenx/${var.resource_prefix}/query"
  tenx_retriever_query_log_group_retention = 1
}

###########################################
# Kubernetes Resources
###########################################

resource "kubernetes_namespace_v1" "retriever" {
  metadata {
    name = var.namespace
  }
}

###########################################
# Helm Release
###########################################

resource "helm_release" "retriever" {
  name       = "retriever"
  repository = "https://log-10x.github.io/helm-charts"
  chart      = "retriever-10x"
  namespace  = kubernetes_namespace_v1.retriever.metadata[0].name

  wait    = true
  timeout = 300

  values = [yamlencode({
    log10xApiKey = var.tenx_api_key

    inputBucket = module.retriever_infra.index_source_bucket_name
    indexBucket = module.retriever_infra.index_write_container

    indexQueueUrl    = module.retriever_infra.index_queue_url
    queryQueueUrl    = module.retriever_infra.query_queue_url
    subQueryQueueUrl = module.retriever_infra.subquery_queue_url
    streamQueueUrl   = module.retriever_infra.stream_queue_url

    queryLogGroup = module.retriever_infra.query_log_group_name

    clusters = [merge(
      {
        name                = "all-in-one"
        roles               = ["index", "query", "stream"]
        replicaCount        = 1
        maxParallelRequests = 5
        maxQueuedRequests   = 100

        # AWS credentials for pods running in minikube
        extraEnv = [
          { name = "AWS_ACCESS_KEY_ID", value = var.aws_access_key_id },
          { name = "AWS_SECRET_ACCESS_KEY", value = var.aws_secret_access_key },
          { name = "AWS_REGION", value = var.aws_region },
        ]

        resources = {
          requests = { cpu = "500m", memory = "1Gi" }
          limits   = { cpu = "1000m", memory = "2Gi" }
        }
      },
      # When local_config_path is set, mount it over /etc/tenx/config
      var.local_config_path != "" ? {
        extraVolumes = [{
          name = "local-config"
          hostPath = {
            path = var.local_config_path
            type = "Directory"
          }
        }]
        extraVolumeMounts = [{
          name      = "local-config"
          mountPath = "/etc/tenx/config"
          readOnly  = true
        }]
        } : {
        extraVolumes      = []
        extraVolumeMounts = []
      }
    )]

    fluentBit = {
      output = { type = "stdout" }
    }

    scheduledQueries = { enabled = false }
    defaultIngress   = { enabled = false }
  })]

  depends_on = [module.retriever_infra]
}

###########################################
# Outputs
###########################################

output "namespace" {
  value = kubernetes_namespace_v1.retriever.metadata[0].name
}

output "input_bucket" {
  value = module.retriever_infra.index_source_bucket_name
}

output "index_bucket" {
  value = module.retriever_infra.index_write_container
}

output "port_forward_command" {
  value = "kubectl port-forward -n ${var.namespace} svc/retriever-retriever-10x-all-in-one 8080:80"
}
