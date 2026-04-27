# Basic Example

This example shows a minimal deployment of the Log10x retriever to an existing EKS cluster.

## Architecture

- Single all-in-one cluster handling all roles (index, query, stream)
- 1 replica (no autoscaling)
- Basic resource limits suitable for development

## Usage

1. Create a `terraform.tfvars` file:

```hcl
eks_cluster_name = "my-eks-cluster"
tenx_api_key     = "your-api-key-here"
```

2. Initialize and apply:

```bash
terraform init
terraform apply
```

## Application Configuration

All application settings are defined in [`values.yaml`](./values.yaml):

- Cluster roles and replica count
- Stream execution limits
- Resource requests and limits
- Readiness thresholds

## Customization

To customize the deployment, edit `values.yaml` to adjust:

- Number of replicas
- CPU/memory resources
- Stream execution limits
- Health probe settings

See the [retriever-10x chart documentation](https://github.com/log-10x/helm-charts/tree/main/charts/retriever) for all available configuration options.
