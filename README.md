# tf-module-lambda-function
This repository contains a custom Terraform module for KFB AWS Lambda functions.

## New: Environment Variable Support
The module now supports passing Lambda environment variables through the `environment_variables` input.

Example:

```hcl
module "example_lambda" {
	source = "./tf-module-lambda-function"

	name        = "example-lambda"
	runtime     = "python3.13"
	handler     = "index.handler"
	source_file = "${path.module}/lambda/index.py"

	environment_variables = {
		LOG_LEVEL = "INFO"
		STAGE     = "dev"
	}
}
```

If `environment_variables` is omitted or empty, no Lambda `environment` block is set.
