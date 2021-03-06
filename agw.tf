locals {
  api_id        = var.create_api ? aws_api_gateway_rest_api.this[0].id : var.api_id
  execution_arn = var.execution_arn == null ? aws_api_gateway_rest_api.this[0].execution_arn : var.execution_arn
}

resource "aws_api_gateway_rest_api" "this" {
  count       = var.create_api ? 1 : 0
  name        = var.api_name
  description = var.api_description
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_stage" "this" {
  deployment_id = aws_api_gateway_deployment.this.id
  rest_api_id   = local.api_id
  #implicit way of creating a conditional depends_on without having to create a separate api stage resource
  stage_name = try(basename(aws_cloudwatch_log_group.agw[0].name), var.stage_name)
}

resource "aws_cloudwatch_log_group" "agw" {
  count             = var.enable_api_cw_logs ? 1 : 0
  name              = "API-Gateway-Execution-Logs_${local.api_id}/${var.stage_name}"
  retention_in_days = 3
}

resource "aws_api_gateway_resource" "this" {
  rest_api_id = local.api_id
  parent_id   = var.create_api ? aws_api_gateway_rest_api.this[0].root_resource_id : var.root_resource_id
  path_part   = var.api_resource_path
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_method" "this" {
  rest_api_id   = local.api_id
  resource_id   = aws_api_gateway_resource.this.id
  http_method   = "POST"
  authorization = "NONE"
  request_parameters = {
    "method.request.header.X-GitHub-Event"      = true
    "method.request.header.X-Hub-Signature-256" = true
  }
}

resource "aws_api_gateway_integration" "this" {
  rest_api_id = local.api_id
  resource_id = aws_api_gateway_method.this.resource_id
  http_method = aws_api_gateway_method.this.http_method

  integration_http_method = "POST"
  type                    = "AWS"
  request_parameters = var.async_lambda_invocation ? {
    "integration.request.header.X-Amz-Invocation-Type" = "'Event'"
  } : null
  request_templates = { "application/json" = jsonencode({
    "headers" = {
      "X-GitHub-Event"      = "$input.params('X-GitHub-Event')"
      "X-Hub-Signature-256" = "$input.params('X-Hub-Signature-256')"
    }
    "body" = "$util.escapeJavaScript($input.json('$'))"
  }) }

  uri = module.lambda_function.lambda_function_invoke_arn
}

resource "aws_api_gateway_model" "this" {
  rest_api_id  = local.api_id
  name         = "CustomErrorModel"
  content_type = "application/json"

  schema = <<EOF
{
  "type": "object",
  "title": "${var.function_name}-ErrorModel",
  "properties": {
    "isError": {
        "type": "boolean"
    },
    "message": {
      "type": "string"
    },
    "type": {
      "type": "string"
    }
  },
  "required": [
    "isError",
    "type"
  ]
}
EOF
}

resource "aws_api_gateway_method_response" "status_400" {
  rest_api_id = local.api_id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.this.http_method
  status_code = "400"
  response_models = {
    "application/json" = aws_api_gateway_model.this.name
  }
}

resource "aws_api_gateway_integration_response" "status_400" {
  rest_api_id = local.api_id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_integration.this.http_method
  status_code = "400"

  response_templates = {
    "application/json" = <<EOF
    #set($inputRoot = $input.path('$'))
    #set ($errorMessageObj = $util.parseJson($input.path('$.errorMessage')))
    {
        "isError" : true,
        "message" : "$errorMessageObj.message",
        "type": "$errorMessageObj.type"
    }
  EOF
  }

  selection_pattern = ".*\"type\"\\s*:\\s*\"ClientException\".*"
  depends_on = [
    aws_api_gateway_method_response.status_400
  ]
}
resource "aws_api_gateway_method_response" "status_500" {
  rest_api_id = local.api_id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.this.http_method
  status_code = "500"
  response_models = {
    "application/json" = aws_api_gateway_model.this.name
  }
}

resource "aws_api_gateway_integration_response" "status_500" {
  rest_api_id = local.api_id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_integration.this.http_method
  status_code = "500"

  response_templates = {
    "application/json" = <<EOF
    #set($inputRoot = $input.path('$'))
    #set ($errorMessageObj = $util.parseJson($input.path('$.errorMessage')))
    {
        "isError" : true,
        "message" : "$errorMessageObj.message",
        "type": "$errorMessageObj.type"
    }
  EOF
  }

  selection_pattern = ".*\"type\"\\s*:\\s*\"ServerException\".*"
  depends_on = [
    aws_api_gateway_method_response.status_500
  ]
}

resource "aws_api_gateway_method_response" "status_200" {
  rest_api_id = local.api_id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.this.http_method
  status_code = "200"
}

resource "aws_api_gateway_integration_response" "status_200" {
  rest_api_id = local.api_id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_integration.this.http_method
  status_code = "200"

  depends_on = [
    aws_api_gateway_method_response.status_200
  ]
}

resource "aws_api_gateway_method_settings" "this" {
  count       = var.enable_api_cw_logs ? 1 : 0
  rest_api_id = local.api_id
  stage_name  = aws_api_gateway_stage.this.stage_name
  method_path = "${aws_api_gateway_resource.this.path_part}/${aws_api_gateway_method.this.http_method}"

  settings {
    logging_level          = "ERROR"
    data_trace_enabled     = true
    throttling_rate_limit  = 30
    throttling_burst_limit = 10
  }
}

resource "aws_api_gateway_deployment" "this" {
  rest_api_id = local.api_id
  lifecycle {
    create_before_destroy = true
  }
  triggers = merge({ github_webhook = filesha1("${path.module}/agw.tf") }, var.deployment_triggers)
  depends_on = [
    aws_api_gateway_resource.this,
    aws_api_gateway_method.this,
    aws_api_gateway_integration.this
  ]
}