# ---------------------------
# Validation: choose one code mode
# ---------------------------
resource "terraform_data" "validate_single_code_mode" {
  lifecycle {
    precondition {
      condition = (
        (var.code_managed_elsewhere ? 1 : 0) +
        ((var.source_file != null && var.source_file != "") ? 1 : 0) +
        ((var.filename != null && var.filename != "") ? 1 : 0)
      ) == 1
      error_message = "Choose exactly one: code_managed_elsewhere=true OR source_file OR filename."
    }
  }
}

# ---------------------------
# Packaging
# ---------------------------

# If caller provides a single source_file, zip it
data "archive_file" "zip_from_source_file" {
  count       = var.code_managed_elsewhere ? 0 : (var.source_file != null && var.source_file != "" ? 1 : 0)
  type        = "zip"
  output_path = coalesce(var.build_zip_path, "${path.module}/.build/${replace(var.name, "/", "-")}.zip")

  source {
    filename = basename(var.source_file)
    content  = file(var.source_file)
  }
}

# If code is managed elsewhere, deploy a placeholder hello-world zip.
# This is intentionally python code; set runtime=python3.13 and handler=index.handler in the caller.
data "archive_file" "placeholder_zip" {
  count       = var.code_managed_elsewhere ? 1 : 0
  type        = "zip"
  output_path = "${path.module}/.build/${replace(var.name, "/", "-")}-placeholder.zip"

  source {
    filename = "index.py"
    content  = <<-PY
def handler(event, context):
    return {
        "statusCode": 200,
        "headers": {"content-type": "application/json"},
        "body": "{\"message\": \"hello from placeholder lambda (code_managed_elsewhere=true)\"}"
    }
PY
  }
}

# ---------------------------
# IAM Role + Policies
# ---------------------------
resource "aws_iam_role" "this" {
  name = "${var.name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = var.tags
}

# Always: basic execution (CloudWatch Logs)
resource "aws_iam_role_policy_attachment" "basic_execution" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Only if VPC enabled: permissions for ENIs (minimal inline policy)
resource "aws_iam_role_policy" "vpc_networking" {
  count = var.vpc_enabled ? 1 : 0
  name  = "${var.name}-vpc-networking"
  role  = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ec2:CreateNetworkInterface",
        "ec2:DescribeNetworkInterfaces",
        "ec2:DeleteNetworkInterface",
        "ec2:AssignPrivateIpAddresses",
        "ec2:UnassignPrivateIpAddresses",
        "ec2:DescribeSubnets",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeVpcs"
      ]
      Resource = "*"
    }]
  })
}

# Optional: extra inline statements if provided
resource "aws_iam_role_policy" "extra" {
  count = length(var.extra_policy_statements) > 0 ? 1 : 0
  name  = "${var.name}-extra"
  role  = aws_iam_role.this.id

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = var.extra_policy_statements
  })
}

# ---------------------------
# VPC Security Group (optional)
# ---------------------------
resource "aws_security_group" "this" {
  count = (var.vpc_enabled && var.create_security_group && length(var.security_group_ids) == 0) ? 1 : 0

  name        = coalesce(var.security_group_name, "${var.name}-sg")
  description = "Security group for Lambda ${var.name} (no ingress; allow all egress)"
  vpc_id      = var.vpc_id

  ingress = []

  egress {
    description = "Allow all egress IPv4"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags

  lifecycle {
    precondition {
      condition     = (var.vpc_id != null && var.vpc_id != "")
      error_message = "When creating a security group, vpc_id must be set."
    }
  }
}

# Helper: SG ids to use for vpc_config
# (kept inline at usage sites to avoid extra locals)

# ---------------------------
# Lambda (3 clear cases)
# ---------------------------

# Case 1: code managed elsewhere (placeholder)
resource "aws_lambda_function" "placeholder" {
  count = var.code_managed_elsewhere ? 1 : 0

  function_name = var.name
  description   = var.description
  role          = aws_iam_role.this.arn

  runtime       = var.runtime
  handler       = coalesce(var.handler, "index.handler")
  timeout       = var.timeout
  memory_size   = var.memory_size
  architectures = var.architectures

  filename         = data.archive_file.placeholder_zip[0].output_path
  source_code_hash = data.archive_file.placeholder_zip[0].output_base64sha256

  dynamic "vpc_config" {
    for_each = var.vpc_enabled ? [1] : []
    content {
      subnet_ids = var.subnet_ids
      security_group_ids = (
        length(var.security_group_ids) > 0
        ? var.security_group_ids
        : [aws_security_group.this[0].id]
      )
    }
  }

  tags = var.tags

  # Key change: once created, Terraform will stop trying to update code-related fields
  # for the placeholder lambda.
  lifecycle {
    ignore_changes = [
      filename,
      source_code_hash,
      last_modified,
      qualified_arn,
      version,
    ]

    precondition {
      condition     = var.vpc_enabled ? (length(var.subnet_ids) > 0) : true
      error_message = "When vpc_enabled=true, subnet_ids must be non-empty."
    }

    precondition {
      condition     = var.vpc_enabled ? (length(var.security_group_ids) > 0 || length(aws_security_group.this) > 0) : true
      error_message = "When vpc_enabled=true, provide security_group_ids or enable create_security_group."
    }
  }
}

# Case 2: source_file provided (zip it)
resource "aws_lambda_function" "from_source_file" {
  count = (!var.code_managed_elsewhere && var.source_file != null && var.source_file != "") ? 1 : 0

  function_name = var.name
  description   = var.description
  role          = aws_iam_role.this.arn

  runtime       = var.runtime
  handler       = var.handler
  timeout       = var.timeout
  memory_size   = var.memory_size
  architectures = var.architectures

  filename         = data.archive_file.zip_from_source_file[0].output_path
  source_code_hash = data.archive_file.zip_from_source_file[0].output_base64sha256

  dynamic "vpc_config" {
    for_each = var.vpc_enabled ? [1] : []
    content {
      subnet_ids = var.subnet_ids
      security_group_ids = (
        length(var.security_group_ids) > 0
        ? var.security_group_ids
        : [aws_security_group.this[0].id]
      )
    }
  }

  tags = var.tags

  lifecycle {
    precondition {
      condition     = var.vpc_enabled ? (length(var.subnet_ids) > 0) : true
      error_message = "When vpc_enabled=true, subnet_ids must be non-empty."
    }

    precondition {
      condition     = var.vpc_enabled ? (length(var.security_group_ids) > 0 || length(aws_security_group.this) > 0) : true
      error_message = "When vpc_enabled=true, provide security_group_ids or enable create_security_group."
    }
  }
}

# Case 3: filename provided (prebuilt zip)
resource "aws_lambda_function" "from_filename" {
  count = (!var.code_managed_elsewhere && var.filename != null && var.filename != "") ? 1 : 0

  function_name = var.name
  description   = var.description
  role          = aws_iam_role.this.arn

  runtime       = var.runtime
  handler       = var.handler
  timeout       = var.timeout
  memory_size   = var.memory_size
  architectures = var.architectures

  filename         = var.filename
  source_code_hash = filebase64sha256(var.filename)

  dynamic "vpc_config" {
    for_each = var.vpc_enabled ? [1] : []
    content {
      subnet_ids = var.subnet_ids
      security_group_ids = (
        length(var.security_group_ids) > 0
        ? var.security_group_ids
        : [aws_security_group.this[0].id]
      )
    }
  }

  tags = var.tags

  lifecycle {
    precondition {
      condition     = var.vpc_enabled ? (length(var.subnet_ids) > 0) : true
      error_message = "When vpc_enabled=true, subnet_ids must be non-empty."
    }

    precondition {
      condition     = var.vpc_enabled ? (length(var.security_group_ids) > 0 || length(aws_security_group.this) > 0) : true
      error_message = "When vpc_enabled=true, provide security_group_ids or enable create_security_group."
    }
  }
}
