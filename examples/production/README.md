# Production Example

This example demonstrates a production-ready deployment with:

- **Separate clusters** for index, query, and stream roles
- **Horizontal pod autoscaling** based on CPU utilization
- **Resource limits** optimized for each workload type
- **High availability** configuration with pod anti-affinity
- **Existing S3 buckets** (not created by Terraform)

## Architecture

### Indexer Cluster
- 2-5 replicas (autoscaled)
- 4-8 GB memory per pod
- Lower parallelism (indexing is resource-intensive)
- Can be deployed on dedicated nodes

### Query Handler Cluster
- 3-10 replicas (autoscaled)
- 2-4 GB memory per pod
- Higher parallelism for concurrent queries
- Optimized for throughput

### Stream Worker Cluster
- 5-15 replicas (autoscaled)
- 2-4 GB memory per pod
- Spread across availability zones
- Balanced parallelism for stream execution

## Prerequisites

1. Existing EKS cluster with OIDC provider
2. Existing S3 buckets for source logs and indexed results
3. Kubernetes namespace (or set `create_namespace = true` in main.tf)

## Usage

1. Create a `terraform.tfvars` file:

```hcl
eks_cluster_name     = "production-eks-cluster"
tenx_api_key         = "your-api-key-here"
namespace            = "tenx-retriever"
source_bucket_name   = "prod-logs-source"
results_bucket_name  = "prod-logs-indexed"
```

2. Initialize and apply:

```bash
terraform init
terraform apply
```

## Application Configuration

All application settings are defined in [`values.yaml`](./values.yaml):

- Cluster roles and scaling policies
- Resource requests and limits per cluster
- Stream execution limits
- Autoscaling thresholds
- Pod anti-affinity rules

## Customization

### GitHub Integration

Uncomment the `github` section in `values.yaml` to enable fetching pipeline configuration and compiled symbols from GitHub repositories.

### Node Affinity

Uncomment `nodeSelector` sections to pin specific clusters to dedicated node pools:

```yaml
clusters:
  - name: indexer
    nodeSelector:
      workload-type: index
```

This requires node pools with matching labels.

### Autoscaling

Adjust autoscaling parameters based on your workload:

```yaml
autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 10
  targetCPUUtilizationPercentage: 75
```

See the [retriever-10x chart documentation](https://github.com/log-10x/helm-charts/tree/main/charts/retriever) for all available configuration options.
