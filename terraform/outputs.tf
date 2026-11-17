output "primary_cluster_name" { value = module.eks_primary.cluster_name }
output "secondary_cluster_name" { value = module.eks_secondary.cluster_name }
output "failover_lambda_name" { value = aws_lambda_function.failover.function_name }
output "failover_sns_topic_arn" { value = aws_sns_topic.failover.arn }
output "application_hostname" { value = var.app_fqdn }
