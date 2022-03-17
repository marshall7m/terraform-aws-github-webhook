resource "aws_api_gateway_rest_api" "this" {
  name        = var.api_name
  description = var.api_description
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_stage" "this" {
  deployment_id = aws_api_gateway_deployment.this.id
  rest_api_id   = aws_api_gateway_rest_api.this.id
  stage_name    = "prod"
}

resource "aws_api_gateway_request_validator" "this" {
  name                        = "request-validator"
  rest_api_id                 = aws_api_gateway_rest_api.this.id
  validate_request_body       = true
  validate_request_parameters = true
}

resource "aws_api_gateway_authorizer" "demo" {
  name                   = "request-authorizer"
  rest_api_id            = aws_api_gateway_rest_api.this.id
  authorizer_uri         = module.lambda.function_invoke_arn
  authorizer_credentials = module.api_role.role_arn
  type                   = "REQUEST"
  #TODO: Add once/if AWS allows for request.body paramters to be passed lambda authorizers
  identity_source = "method.request.header.X-GitHub-Event,method.request.header.X-Hub-Signature-256,method.request.body"
}

module "api_role" {
  source = "github.com/marshall7m/terraform-aws-iam/modules//iam-role"

  role_name        = "${var.api_name}-request-authorizer"
  trusted_services = ["apigateway.amazonaws.com"]
  statements = [
    {
      effect    = "Allow"
      actions   = ["lambda:InvokeFunction"]
      resources = [module.lambda.function_arn]
    }
  ]
}

resource "aws_api_gateway_resource" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "github"
}

resource "aws_api_gateway_method" "this" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.this.id
  http_method   = "POST"
  authorization = "NONE"
  request_parameters = {
    "method.request.header.X-GitHub-Event"      = true
    "method.request.header.X-Hub-Signature-256" = true
  }
}

resource "aws_api_gateway_integration" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id
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

  uri = module.lambda.function_invoke_arn
}

resource "aws_api_gateway_model" "this" {
  rest_api_id  = aws_api_gateway_rest_api.this.id
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
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.this.http_method
  status_code = "400"
  response_models = {
    "application/json" = aws_api_gateway_model.this.name
  }
}

resource "aws_api_gateway_integration_response" "status_400" {
  rest_api_id = aws_api_gateway_rest_api.this.id
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
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.this.http_method
  status_code = "500"
  response_models = {
    "application/json" = aws_api_gateway_model.this.name
  }
}

resource "aws_api_gateway_integration_response" "status_500" {
  rest_api_id = aws_api_gateway_rest_api.this.id
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
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.this.http_method
  status_code = "200"
}

resource "aws_api_gateway_integration_response" "status_200" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_integration.this.http_method
  status_code = "200"

  depends_on = [
    aws_api_gateway_method_response.status_200
  ]
}

resource "aws_api_gateway_deployment" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  lifecycle {
    create_before_destroy = true
  }
  triggers = {
    redeployment = filesha1("${path.module}/agw.tf")
  }
  depends_on = [
    aws_api_gateway_resource.this,
    aws_api_gateway_method.this,
    aws_api_gateway_integration.this
  ]
}