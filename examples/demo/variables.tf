variable "subscription_id" {
  description = "Azure subscription ID where resources will be deployed"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group name for the demo resources"
  type        = string
  default     = "runner-demo"
}

variable "location" {
  description = "Azure region for the demo resources"
  type        = string
  default     = "westeurope"
}

variable "storage_account_name_prefix" {
  description = "Prefix for the storage account name. A random suffix is appended for global uniqueness"
  type        = string
  default     = "runnerdemo"

  validation {
    condition     = can(regex("^[a-z0-9]{3,16}$", var.storage_account_name_prefix))
    error_message = "storage_account_name_prefix must be 3-16 lowercase alphanumeric characters."
  }
}

variable "tags" {
  description = "Tags to apply to demo resources"
  type        = map(string)
  default = {
    Environment = "Demo"
    ManagedBy   = "Terraform"
    Project     = "GitHubRunners"
  }
}
