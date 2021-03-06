output "github_webhook_invoke_url" {
  description = "API URL the github webhook will ping"
  value       = "${aws_api_gateway_deployment.this.invoke_url}${aws_api_gateway_stage.this.stage_name}${aws_api_gateway_resource.this.path}"
}

output "webhook_urls" {
  description = "Map of repo webhook URLs"
  value       = { for repo in github_repository_webhook.this : repo.repository => repo.url }
  sensitive   = true
}

output "webhook_ids" {
  description = "Map of repo webhook IDs"
  value       = { for repo in github_repository_webhook.this : repo.repository => element(split("/", repo.url), length(split("/", repo.url)) - 1) }
  sensitive   = true
}

output "function_arn" {
  description = "ARN of AWS Lambda Function used to validate Github webhook request"
  value       = module.lambda_function.lambda_function_arn
}

output "function_name" {
  description = "Name of the Lambda Function used to validate Github webhook request"
  value       = module.lambda_function.lambda_function_name
}

output "lambda_log_group_arn" {
  description = "ARN of the CloudWatch log group associated with the Lambda Function"
  value       = module.lambda_function.lambda_cloudwatch_log_group_arn
}

output "lambda_log_group_name" {
  description = "Name of the CloudWatch log group associated with the Lambda Function"
  value       = module.lambda_function.lambda_cloudwatch_log_group_name
}

output "api_stage_name" {
  description = "API stage name"
  value       = try(aws_api_gateway_stage.this.stage_name, null)
}

output "deployment_invoke_url" {
  description = "API stage's URL"
  value       = try(aws_api_gateway_deployment.this.invoke_url, null)
}

output "api_changes_sha" {
  description = "SHA value of file that contains API-related configurations. Can be used as a trigger for API deployments (see AWS resource: aws_api_gateway_deployment)"
  value       = filesha1("${path.module}/agw.tf")
}

output "api_id" {
  description = "SHA value of file that contains API-related configurations. Can be used as a trigger for API deployments (see AWS resource: aws_api_gateway_deployment)"
  value       = local.api_id
}

output "agw_log_group_arn" {
  description = "ARN of the CloudWatch log group associated with the API gateway"
  value       = try(aws_cloudwatch_log_group.agw[0].arn, null)
}

output "agw_log_group_name" {
  description = "Name of the CloudWatch log group associated with the API gateway"
  value       = try(aws_cloudwatch_log_group.agw[0].name, null)
}

output "github_token_ssm_arns" {
  description = "ARNs of the GitHub token AWS SSM Parameter Store resources"
  value       = try(aws_ssm_parameter.github_token[*].arn, [])
}