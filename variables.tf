variable "name" {
  description = "Lambda function name (full name, not a prefix)."
  type        = string
}

variable "description" {
  description = "Lambda description."
  type        = string
  default     = null
}

variable "runtime" {
  description = "Lambda runtime, e.g., python3.13, nodejs20.x, etc."
  type        = string
}

variable "handler" {
  description = "Handler, e.g., index.handler. Optional when code_managed_elsewhere=true (defaults to index.handler)."
  type        = string
  default     = null
}

variable "timeout" {
  description = "Timeout in seconds."
  type        = number
  default     = 10
}

variable "memory_size" {
  description = "Memory size in MB."
  type        = number
  default     = 128
}

variable "architectures" {
  description = "Lambda architectures, e.g., [\"x86_64\"] or [\"arm64\"]."
  type        = list(string)
  default     = ["x86_64"]
}

variable "code_managed_elsewhere" {
  description = "If true, module deploys a built-in hello-world package so infra can be managed without providing code artifacts."
  type        = bool
  default     = false
}

# --- Packaging (simple single-file zip, like your current setup) ---
variable "source_file" {
  description = "Path to a single source file to zip (module will create a zip). Mutually exclusive with filename and code_managed_elsewhere."
  type        = string
  default     = null
}

variable "filename" {
  description = "Path to an already-built deployment package zip. Mutually exclusive with source_file and code_managed_elsewhere."
  type        = string
  default     = null
}

variable "build_zip_path" {
  description = "Where to write the zip if using source_file."
  type        = string
  default     = null
}

# --- VPC ---
variable "vpc_enabled" {
  description = "Whether to attach Lambda to a VPC."
  type        = bool
  default     = false
}

variable "vpc_id" {
  description = "VPC ID (required if vpc_enabled = true AND module creates a security group)."
  type        = string
  default     = null
}

variable "subnet_ids" {
  description = "Subnet IDs for Lambda ENIs (required if vpc_enabled = true)."
  type        = list(string)
  default     = []
}

variable "security_group_ids" {
  description = "If set and vpc_enabled=true, module will use these instead of creating its own SG."
  type        = list(string)
  default     = []
}

variable "create_security_group" {
  description = "Whether module creates a SG when vpc_enabled=true and security_group_ids is empty."
  type        = bool
  default     = true
}

variable "security_group_name" {
  description = "Optional SG name override (only used if module creates SG)."
  type        = string
  default     = null
}

# --- IAM / Policies ---


variable "extra_policy_statements" {
  description = <<EOT
Additional IAM policy statements to attach inline to the Lambda role.
Example:
[
  {
    Effect = "Allow"
    Action = ["s3:GetObject"]
    Resource = ["arn:aws:s3:::my-bucket/*"]
  }
]
EOT
  type        = list(any)
  default     = []
}

variable "tags" {
  description = "Tags to apply to created resources."
  type        = map(string)
  default     = {}
}
