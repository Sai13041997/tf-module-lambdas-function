output "lambda_function_name" {
  value = one(concat(
    aws_lambda_function.placeholder[*].function_name,
    aws_lambda_function.from_source_file[*].function_name,
    aws_lambda_function.from_filename[*].function_name
  ))
}

output "lambda_function_arn" {
  value = one(concat(
    aws_lambda_function.placeholder[*].arn,
    aws_lambda_function.from_source_file[*].arn,
    aws_lambda_function.from_filename[*].arn
  ))
}

output "role_arn" {
  value = aws_iam_role.this.arn
}

output "security_group_id" {
  description = "Security group ID if module created one (null otherwise)."
  value       = length(aws_security_group.this) > 0 ? aws_security_group.this[0].id : null
}
