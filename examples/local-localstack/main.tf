# Local Testing with LocalStack
# Deploys Retriever to minikube using LocalStack for S3/SQS emulation.
# No AWS account required.
#
# Prerequisites:
#   - minikube running
#   - LocalStack deployed in minikube (see doc.log10x.com/apps/retriever/)
#   - LocalStack port-forward: kubectl port-forward -n localstack svc/localstack 4566:4566
#
# Usage:
#   terraform init
#   terraform apply -var="tenx_api_key=test-key"

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

# Configure AWS provider to use LocalStack
provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    s3  = "http://localhost:4566"
    sqs = "http://localhost:4566"
  }

  s3_use_path_style = true
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
  description = "Log10x API key (use any placeholder for local testing)"
  type        = string
  sensitive   = true
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

locals {
  localstack_external = "http://localhost:4566"
  localstack_internal = "http://localstack.localstack.svc.cluster.local:4566"
}

###########################################
# Infrastructure (S3/SQS via LocalStack)
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

  # Note: CloudWatch Logs (tenx_retriever_query_log_group_name) is not configured here
  # because LocalStack does not support CloudWatch Logs.
  # For real AWS deployments, see the local-aws example.
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

    indexQueueUrl    = replace(module.retriever_infra.index_queue_url, local.localstack_external, local.localstack_internal)
    queryQueueUrl    = replace(module.retriever_infra.query_queue_url, local.localstack_external, local.localstack_internal)
    subQueryQueueUrl = replace(module.retriever_infra.subquery_queue_url, local.localstack_external, local.localstack_internal)
    streamQueueUrl   = replace(module.retriever_infra.stream_queue_url, local.localstack_external, local.localstack_internal)

    clusters = [merge(
      {
        name                = "all-in-one"
        roles               = ["index", "query", "stream"]
        replicaCount        = 1
        maxParallelRequests = 5
        maxQueuedRequests   = 100

        extraEnv = [
          { name = "AWS_ENDPOINT_URL", value = local.localstack_internal },
          { name = "AWS_ACCESS_KEY_ID", value = "test" },
          { name = "AWS_SECRET_ACCESS_KEY", value = "test" },
          { name = "AWS_REGION", value = "us-east-1" },
          { name = "TENX_S3_PATH_STYLE", value = "true" },
          { name = "TENX_INVOKE_PIPELINE_SCAN_ENDPOINT", value = replace(module.retriever_infra.subquery_queue_url, local.localstack_external, local.localstack_internal) },
          { name = "TENX_INVOKE_PIPELINE_STREAM_ENDPOINT", value = replace(module.retriever_infra.stream_queue_url, local.localstack_external, local.localstack_internal) },
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
