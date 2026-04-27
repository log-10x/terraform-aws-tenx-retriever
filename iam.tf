# IAM Role for Service Account (IRSA)
# This role allows Kubernetes service accounts to assume AWS permissions
resource "aws_iam_role" "tenx_retriever" {
  name = local.iam_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = local.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.oidc_provider}:sub" = "system:serviceaccount:${var.namespace}:${local.service_account_name}"
            "${local.oidc_provider}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = local.tags
}

# IAM Policy with S3 and SQS permissions
# Permissions are based on actual AWS operations performed by the application
# (analyzed from AWSIndexAccess.java and SqsConsumer.java)
resource "aws_iam_role_policy" "tenx_retriever" {
  role = aws_iam_role.tenx_retriever.id
  name = "tenx-retriever-permissions"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      # S3 Input Bucket - Read-only access
      # Used by: AWSIndexAccess.readObject() for reading source log files
      [
        {
          Sid    = "S3InputBucketRead"
          Effect = "Allow"
          Action = [
            "s3:GetObject",
            "s3:GetObjectTagging",
            "s3:GetObjectAcl"
          ]
          Resource = [
            "arn:aws:s3:::${module.tenx_retriever_infra.index_source_bucket_name}/*"
          ]
        }
      ],
      # S3 Index Bucket - List bucket access
      # Used by: AWSIndexAccess.iterateIndexObjects() for listing index files
      [
        {
          Sid    = "S3IndexBucketList"
          Effect = "Allow"
          Action = [
            "s3:ListBucket"
          ]
          Resource = [
            "arn:aws:s3:::${module.tenx_retriever_infra.index_results_bucket_name}"
          ]
        }
      ],
      # S3 Index Bucket - Object-level access
      # Used by: AWSIndexAccess for reading, writing, and deleting index objects
      [
        {
          Sid    = "S3IndexBucketObjectAccess"
          Effect = "Allow"
          Action = [
            "s3:GetObject",        # Read existing index files
            "s3:GetObjectTagging", # Read object tags
            "s3:GetObjectAcl",     # Read object ACLs
            "s3:PutObject",        # Write new index files
            "s3:PutObjectTagging", # Write object tags
            "s3:PutObjectAcl",     # Write object ACLs
            "s3:DeleteObject"      # Remove obsolete index files
          ]
          Resource = [
            "arn:aws:s3:::${module.tenx_retriever_infra.index_results_bucket_name}/*"
          ]
        }
      ],
      # SQS All Queues - Full message access
      # Used by: SqsConsumer for polling and processing messages
      [
        {
          Sid    = "SQSQueueAccess"
          Effect = "Allow"
          Action = [
            "sqs:ReceiveMessage",    # Poll for messages
            "sqs:DeleteMessage",     # Remove processed messages
            "sqs:SendMessage",       # Send messages (for pipeline invocation)
            "sqs:GetQueueAttributes" # Get queue metadata
          ]
          Resource = [
            "arn:aws:sqs:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:${local.index_queue_name}",
            "arn:aws:sqs:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:${local.query_queue_name}",
            "arn:aws:sqs:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:${local.subquery_queue_name}",
            "arn:aws:sqs:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:${local.stream_queue_name}"
          ]
        }
      ],
      # CloudWatch Logs - Query event logging
      # Used by: QueryEventLog for writing query progress and diagnostic events
      # Only granted when a log group is configured
      local.query_log_group_name != "" ? [
        {
          Sid    = "CloudWatchLogsQueryEvents"
          Effect = "Allow"
          Action = [
            "logs:CreateLogStream",
            "logs:PutLogEvents",
            "logs:DescribeLogStreams"
          ]
          Resource = [
            module.tenx_retriever_infra.query_log_group_arn,
            "${module.tenx_retriever_infra.query_log_group_arn}:*"
          ]
        }
      ] : [],
      # Additional custom policies provided by user
      [
        for policy in var.additional_iam_policies : {
          Sid      = try(policy.sid, null)
          Effect   = policy.effect
          Action   = policy.actions
          Resource = policy.resources
        }
      ]
    )
  })
}
