# terraform-aws-tenx-retriever

Terraform module that deploys the Log10x retriever application to Kubernetes with complete AWS integration.

## Overview

This module provides a complete deployment of the Log10x retriever, including:

- **Infrastructure Provisioning**: Automatically creates SQS queues and S3 buckets using the `terraform-aws-tenx-retriever-infra` module
- **IRSA Configuration**: Sets up IAM Roles for Service Accounts for secure, credential-free AWS access
- **Kubernetes Resources**: Creates namespaces and service accounts with proper annotations
- **Helm Deployment**: Deploys the `retriever-10x` Helm chart with all necessary configuration
- **CloudWatch Logs**: Optionally creates a log group for query event logging with automatic IAM permissions

## Architecture

```
Parent Terraform Module
    │
    ├─> Kubernetes Provider → This Module
    ├─> Helm Provider → This Module
    ├─> OIDC Provider Info → This Module
    │
    └─> This Module Creates:
            │
            ├─> IAM Role (IRSA)
            │       │
            │       └─> IAM Policy (S3 + SQS permissions)
            │
            ├─> Kubernetes Namespace
            │       │
            │       └─> Service Account (with IRSA annotation)
            │               │
            │               └─> Retriever Pods
            │                       │
            │                       ├─> S3 Buckets (source + index)
            │                       └─> SQS Queues (index + query + subquery + stream)
```

## Prerequisites

1. **Kubernetes Cluster** with:
   - Kubernetes version 1.21+
   - Sufficient capacity for retriever pods
   - For EKS: OIDC provider configured (standard for EKS clusters)

2. **Terraform Providers Configured** in your parent module:
   - AWS provider >= 5.0
   - Kubernetes provider >= 2.20 (configured to connect to your cluster)
   - Helm provider >= 2.9 (configured to connect to your cluster)

3. **Terraform** version 1.0 or higher

4. **For IRSA (EKS)**: OIDC provider ARN and URL from your cluster

## Quick Start

### Basic Usage (EKS)

```hcl
# Configure providers
provider "aws" {
  region = "us-east-1"
}

data "aws_eks_cluster" "main" {
  name = "my-eks-cluster"
}

data "aws_eks_cluster_auth" "main" {
  name = "my-eks-cluster"
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.main.token
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.main.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.main.token
  }
}

# Deploy retriever module
module "tenx_retriever" {
  source  = "log-10x/tenx-retriever/aws"
  version = "~> 0.9"

  # Required: API key
  tenx_api_key = var.tenx_api_key

  # Required: OIDC provider info for IRSA
  oidc_provider_arn = data.aws_eks_cluster.main.identity[0].oidc[0].issuer
  oidc_provider     = replace(data.aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")

  # Optional: Resource naming prefix (recommended: use cluster name)
  resource_prefix = "my-eks-cluster"

  # Providers are inherited automatically from parent module
}
```

This will create all infrastructure (SQS queues and S3 buckets) and deploy the retriever to the `default` namespace with default settings.

### Production Usage with Custom Configuration

```hcl
module "tenx_retriever" {
  source  = "log-10x/tenx-retriever/aws"
  version = "~> 0.9"

  # Required
  tenx_api_key      = var.tenx_api_key
  oidc_provider_arn = data.aws_eks_cluster.main.identity[0].oidc[0].issuer
  oidc_provider     = replace(data.aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")

  # Resource naming
  resource_prefix = "production-cluster"

  # Kubernetes configuration
  namespace        = "log10x-retriever"
  create_namespace = true

  # Infrastructure naming (optional - uses resource_prefix if not specified)
  tenx_retriever_index_source_bucket_name  = "my-logs-bucket"
  tenx_retriever_index_results_bucket_name = "my-index-bucket"
  tenx_retriever_index_queue_name          = "prod-index-queue"
  tenx_retriever_query_queue_name          = "prod-query-queue"
  tenx_retriever_subquery_queue_name       = "prod-subquery-queue"
  tenx_retriever_stream_queue_name         = "prod-stream-queue"

  # CloudWatch Logs for query event logging (optional)
  tenx_retriever_query_log_group_name      = "/tenx/prod/retriever/query"
  tenx_retriever_query_log_group_retention = 14

  # Helm configuration
  helm_chart_version = "1.0.12"
  helm_values_file   = "retriever-values.yaml"

  # Tagging
  tags = {
    Environment = "production"
    Project     = "log10x"
    ManagedBy   = "terraform"
  }
}
```

## IRSA (IAM Roles for Service Accounts)

This module sets up IRSA, which provides secure, credential-free AWS access to Kubernetes pods:

1. **OIDC Provider**: Uses the OIDC provider information you provide from your EKS cluster
2. **IAM Role Creation**: Creates an IAM role with a trust policy that allows the Kubernetes service account to assume it
3. **Service Account Annotation**: Annotates the Kubernetes service account with the IAM role ARN
4. **Automatic Credential Injection**: EKS automatically injects temporary AWS credentials into pods using this service account

### IAM Permissions

The module creates an IAM role with least-privilege permissions based on actual application requirements:

**S3 Input Bucket (Read-Only)**:
- `s3:GetObject` - Read source log files

**S3 Index Bucket (Full Access)**:
- `s3:ListBucket` - List index files
- `s3:GetObject` - Read existing index files
- `s3:PutObject` - Write new index files
- `s3:DeleteObject` - Remove obsolete index files

**SQS Queues (All Four Queues)**:
- `sqs:ReceiveMessage` - Poll for messages
- `sqs:DeleteMessage` - Remove processed messages
- `sqs:SendMessage` - Send messages (for pipeline invocation)
- `sqs:GetQueueAttributes` - Get queue metadata

**CloudWatch Logs (Conditional - only when `tenx_retriever_query_log_group_name` is set)**:
- `logs:CreateLogStream` - Create log streams for each query/worker
- `logs:PutLogEvents` - Write query progress and diagnostic events
- `logs:DescribeLogStreams` - List existing log streams

## Input Variables

### Required Variables

| Name | Description | Type |
|------|-------------|------|
| `tenx_api_key` | Log10x API key for authentication (sensitive) | `string` |
| `oidc_provider_arn` | ARN of the OIDC provider for IRSA (e.g., `arn:aws:iam::123456789012:oidc-provider/oidc.eks...`) | `string` |
| `oidc_provider` | OIDC provider URL without `https://` prefix (e.g., `oidc.eks.us-east-1.amazonaws.com/id/...`) | `string` |

### Infrastructure Configuration

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `resource_prefix` | Prefix for generated resource names. Recommended to use cluster name. | `string` | `"tenx-retriever"` |
| `tenx_retriever_index_source_bucket_name` | S3 bucket for source files. Auto-generated if empty. | `string` | `""` |
| `tenx_retriever_index_results_bucket_name` | S3 bucket for index results. Uses source bucket if empty. | `string` | `""` |
| `tenx_retriever_index_queue_name` | Index SQS queue name. Auto-generated if empty. | `string` | `""` |
| `tenx_retriever_query_queue_name` | Query SQS queue name. Auto-generated if empty. | `string` | `""` |
| `tenx_retriever_subquery_queue_name` | Sub-query SQS queue name. Auto-generated if empty. | `string` | `""` |
| `tenx_retriever_stream_queue_name` | Stream SQS queue name. Auto-generated if empty. | `string` | `""` |
| `create_s3_buckets` | Whether to create S3 buckets or use existing ones | `bool` | `true` |
| `tenx_retriever_queue_message_retention` | SQS message retention period in seconds | `number` | `345600` (4 days) |
| `tenx_retriever_index_trigger_suffix` | S3 suffix that triggers indexing (e.g., '.log') | `string` | `""` (all objects) |
| `tenx_retriever_query_log_group_name` | CloudWatch Logs log group for query event logging. If empty, disabled. | `string` | `""` |
| `tenx_retriever_query_log_group_retention` | Days to retain query event logs in CloudWatch Logs | `number` | `7` |
| `create_query_log_group` | Whether the module creates the CloudWatch log group. Set `false` to use an existing log group managed outside this module (still requires `tenx_retriever_query_log_group_name`). | `bool` | `true` |

### Observability Configuration

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `enable_observability_metrics` | Whether to create CloudWatch metric filters that extract operational metrics from the query log group. Requires `tenx_retriever_query_log_group_name`. | `bool` | `true` |
| `metric_namespace` | CloudWatch namespace for retriever observability metrics. | `string` | `"Log10x/Retriever"` |
| `metric_filter_name_prefix` | Prefix for metric filter resource names. Empty default derives from `tenx_retriever_query_log_group_name`. | `string` | `""` |

### Kubernetes Configuration

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `namespace` | Kubernetes namespace to deploy into | `string` | `"default"` |
| `create_namespace` | Whether to create the Kubernetes namespace | `bool` | `false` |
| `service_account_name` | Kubernetes service account name. Defaults to helm_release_name. | `string` | `""` |

### Helm Configuration

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `helm_release_name` | Helm release name | `string` | `"tenx-retriever"` |
| `helm_chart_version` | Version of the retriever-10x Helm chart | `string` | `"1.0.12"` |
| `helm_values_file` | Path to custom Helm values YAML file | `string` | `""` |
| `helm_values` | Additional Helm values as a map | `any` | `{}` |

### Application Configuration

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `replica_count` | Number of replicas (when autoscaling disabled) | `number` | `1` |
| `enable_autoscaling` | Enable horizontal pod autoscaling | `bool` | `false` |
| `autoscaling_min_replicas` | Minimum replicas for autoscaling | `number` | `1` |
| `autoscaling_max_replicas` | Maximum replicas for autoscaling | `number` | `5` |
| `autoscaling_target_cpu_percentage` | Target CPU utilization for autoscaling | `number` | `80` |
| `max_parallel_requests` | Max parallel pipeline executions per pod | `number` | `10` |
| `max_queued_requests` | Max queued pipeline requests per pod | `number` | `1000` |
| `readiness_threshold_percent` | Readiness threshold percentage (0-100) | `number` | `90` |

### IAM Configuration

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `iam_role_name` | IAM role name. Auto-generated if empty. | `string` | `""` |
| `additional_iam_policies` | Additional IAM policy statements | `list(object)` | `[]` |

### Tagging

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `tags` | Tags to apply to AWS resources | `map(string)` | `{}` |

## Outputs

### Infrastructure Outputs

- `index_queue_url` - URL of the index SQS queue
- `query_queue_url` - URL of the query SQS queue
- `subquery_queue_url` - URL of the sub-query SQS queue
- `stream_queue_url` - URL of the stream SQS queue
- `index_source_bucket_name` - Name of the source S3 bucket
- `index_results_bucket_name` - Name of the index results S3 bucket
- `index_write_container` - S3 path for writing index results
- `query_log_group_name` - Name of the CloudWatch Logs log group for query events (empty if disabled)
- `query_log_group_arn` - ARN of the CloudWatch Logs log group for query events (empty if disabled). Constructed from name + region + account when the consumer brings their own log group via `create_query_log_group = false`.

### Observability Outputs

- `observability_metric_namespace` - CloudWatch namespace where retriever observability metrics are published (empty when metrics are disabled)
- `observability_metric_names` - Map of canonical metric names. Keys: `stack_overflow`, `scan_complete`, `stream_worker_complete`, `stream_worker_skipped`, `results_writer_complete`, `launch_failed`, `bloom_blobs_scanned`, `bloom_blobs_matched`. Empty values when metrics are disabled.

### IAM Outputs

- `iam_role_arn` - ARN of the IAM role for IRSA
- `iam_role_name` - Name of the IAM role for IRSA

### Kubernetes Outputs

- `namespace` - Kubernetes namespace where retriever is deployed
- `service_account_name` - Name of the Kubernetes service account

### Helm Outputs

- `helm_release_name` - Name of the Helm release
- `helm_release_status` - Status of the Helm release
- `helm_release_version` - Version of the deployed Helm chart

## Advanced Usage

### Using Existing Infrastructure

If you already have SQS queues and S3 buckets:

```hcl
module "tenx_retriever" {
  source  = "log-10x/tenx-retriever/aws"
  version = "~> 0.9"

  tenx_api_key      = var.tenx_api_key
  oidc_provider_arn = var.oidc_provider_arn
  oidc_provider     = var.oidc_provider

  # Use existing infrastructure
  create_s3_buckets                        = false
  tenx_retriever_index_source_bucket_name   = "existing-logs-bucket"
  tenx_retriever_index_results_bucket_name  = "existing-index-bucket"
  tenx_retriever_index_queue_name           = "existing-index-queue"
  tenx_retriever_query_queue_name           = "existing-query-queue"
  tenx_retriever_subquery_queue_name        = "existing-subquery-queue"
  tenx_retriever_stream_queue_name          = "existing-stream-queue"
}
```

### Adding Custom IAM Policies

If your application needs additional AWS permissions:

```hcl
module "tenx_retriever" {
  source  = "log-10x/tenx-retriever/aws"
  version = "~> 0.9"

  tenx_api_key      = var.tenx_api_key
  oidc_provider_arn = var.oidc_provider_arn
  oidc_provider     = var.oidc_provider

  additional_iam_policies = [
    {
      sid       = "SNSNotifications"
      effect    = "Allow"
      actions   = ["sns:Publish"]
      resources = ["arn:aws:sns:us-east-1:123456789012:my-topic"]
    }
  ]
}
```

### Custom Helm Values

Use a custom values file for Helm configuration:

```hcl
module "tenx_retriever" {
  source  = "log-10x/tenx-retriever/aws"
  version = "~> 0.9"

  tenx_api_key      = var.tenx_api_key
  oidc_provider_arn = var.oidc_provider_arn
  oidc_provider     = var.oidc_provider

  helm_values_file = "${path.module}/custom-retriever-values.yaml"
}
```

### Observability Metrics

When the query log group is configured (`tenx_retriever_query_log_group_name` is set), the module also creates CloudWatch metric filters that translate retriever log lines into queryable metrics — without any engine changes. Toggle the entire block via `enable_observability_metrics` (default `true`).

Metrics published (namespace defaults to `Log10x/Retriever`):

| Metric | Source log line | Use |
|---|---|---|
| `StackOverflowCount` | `StackOverflowError` | Crash detection — alarm on any occurrence |
| `ScanCompleteCount` | `scan complete:` | Per-query throughput |
| `StreamWorkerCompleteCount` | `stream worker complete:` | Successful stream-worker completions |
| `StreamWorkerSkippedCount` | `stream worker skipped:` | Workers that exceeded `processingTimeLimit` — alarm on a sustained surge |
| `ResultsWriterCompleteCount` | `results writer complete:` | Result-write throughput |
| `LaunchFailedCount` | `could not launch pipeline` | Pipeline configuration / override mismatch — alarm on any occurrence |
| `BloomBlobsScanned` | `scan complete:` (JSON `$.fields.scanned`) | Numerator + denominator for the bloom false-positive ratio |
| `BloomBlobsMatched` | `scan complete:` (JSON `$.fields.matched`) | Use metric math `(matched / scanned) * 100` to track effective bloom hit rate |

Reference the metrics in your own alarms via the module outputs:

```hcl
resource "aws_cloudwatch_metric_alarm" "retriever_stack_overflow" {
  alarm_name          = "retriever-stack-overflow"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 0
  period              = 60
  statistic           = "Sum"
  metric_name         = module.tenx_retriever.observability_metric_names.stack_overflow
  namespace           = module.tenx_retriever.observability_metric_namespace
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.oncall_sns_topic_arn]
}
```

Alarms and dashboards are intentionally NOT created by this module — they're environment-specific (alarm thresholds, SNS action ARNs, Grafana workspace, etc.).

### Bring Your Own Log Group

If the CloudWatch log group is managed elsewhere (e.g., a separate observability terraform stack tagged differently), pass `create_query_log_group = false`:

```hcl
resource "aws_cloudwatch_log_group" "retriever_query" {
  name              = "/tenx/prod/retriever/query"
  retention_in_days = 14
  tags              = local.our_tags
}

module "tenx_retriever" {
  source  = "log-10x/tenx-retriever/aws"
  version = "~> 0.9"

  # ... other config ...

  tenx_retriever_query_log_group_name = aws_cloudwatch_log_group.retriever_query.name
  create_query_log_group              = false
}
```

The module wires IAM and the JVM to use the existing log group. The `query_log_group_arn` output is computed from name + region + account in this case, so downstream IAM policies still resolve correctly.

## Troubleshooting

### Pods Cannot Access S3/SQS

**Symptoms**: Pods fail with AWS authentication errors

**Possible Causes**:
1. OIDC provider not configured on EKS cluster
2. Service account annotation missing or incorrect
3. IAM role trust policy doesn't match service account

**Solutions**:
```bash
# Verify OIDC provider exists
aws eks describe-cluster --name <cluster-name> --query "cluster.identity.oidc.issuer"

# Verify service account annotation
kubectl get sa <service-account-name> -n <namespace> -o yaml

# Check pod has correct service account
kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.spec.serviceAccountName}'

# Check AWS credentials are injected
kubectl exec <pod-name> -n <namespace> -- env | grep AWS
```

### Helm Release Fails to Deploy

**Symptoms**: `terraform apply` fails during Helm release creation

**Possible Causes**:
1. Insufficient permissions to create Kubernetes resources
2. Invalid Helm values
3. Chart version doesn't exist

**Solutions**:
```bash
# Verify AWS credentials can access cluster
aws eks update-kubeconfig --name <cluster-name>
kubectl auth can-i create deployments -n <namespace>

# Test Helm chart locally
helm repo add log-10x https://log-10x.github.io/helm-charts
helm repo update
helm search repo log10x/retriever-10x --versions

# Validate custom values file
helm template test log10x/retriever-10x -f <your-values-file>
```

### Resource Name Conflicts

**Symptoms**: Terraform fails with "already exists" errors

**Possible Causes**:
1. Resources from previous deployment not cleaned up
2. Multiple modules deploying to same cluster without unique names

**Solutions**:
```hcl
# Use unique resource names per deployment
module "tenx_retriever" {
  source = "..."

  helm_release_name                      = "tenx-retriever-prod"
  iam_role_name                          = "prod-tenx-retriever-irsa"
  service_account_name                   = "tenx-retriever-prod"
  tenx_retriever_index_queue_name         = "prod-index-queue"
  tenx_retriever_query_queue_name         = "prod-query-queue"
  tenx_retriever_subquery_queue_name      = "prod-subquery-queue"
  tenx_retriever_stream_queue_name        = "prod-stream-queue"
}
```

### OIDC Provider ARN Not Found

**Symptoms**: IAM role creation fails with "invalid principal" error

**Possible Causes**:
1. EKS cluster doesn't have OIDC provider configured
2. OIDC provider was deleted

**Solutions**:
```bash
# Check if OIDC provider exists
aws iam list-open-id-connect-providers

# Create OIDC provider for cluster
eksctl utils associate-iam-oidc-provider --cluster <cluster-name> --approve
```

## Examples

See the [examples/](examples/) directory for complete working examples:

- [Basic](examples/basic/) - Minimal configuration with defaults
- [Production](examples/production/) - Production-ready configuration with autoscaling

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.0 |
| aws | >= 5.0 |
| kubernetes | >= 2.20 |
| helm | >= 2.9 |

## Providers

| Name | Version |
|------|---------|
| aws | >= 5.0 |
| kubernetes | >= 2.20 |
| helm | >= 2.9 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| tenx_retriever_infra | log-10x/tenx-retriever-infra/aws | >= 0.9.1 |

## Resources

| Name | Type |
|------|------|
| aws_iam_role.tenx_retriever | resource |
| aws_iam_role_policy.tenx_retriever | resource |
| kubernetes_namespace.tenx_retriever | resource |
| kubernetes_service_account.tenx_retriever | resource |
| helm_release.tenx_retriever | resource |
| aws_region.current | data source |
| aws_caller_identity.current | data source |

## License

This repository is licensed under the [Apache License 2.0](LICENSE).

### Important: Log10x Product License Required

This repository contains deployment tooling for Log10x Retriever. While the Terraform module
itself is open source, **using Log10x requires a commercial license**.

| Component | License |
|-----------|---------|
| This repository (Terraform module) | Apache 2.0 (open source) |
| Log10x engine and runtime | Commercial license required |

**What this means:**
- You can freely use, modify, and distribute this Terraform module
- The Log10x software that this module deploys requires a paid subscription
- A valid Log10x API key is required to run the deployed software

**Get Started:**
- [Log10x Pricing](https://log10x.com/pricing)
- [Documentation](https://doc.log10x.com)
- [Contact Sales](mailto:sales@log10x.com)

## Support

For issues and questions:
- GitHub Issues: https://github.com/log-10x/terraform-aws-tenx-retriever/issues
- Documentation: https://doc.log10x.com
