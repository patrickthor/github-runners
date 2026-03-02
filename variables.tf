variable "resource_group_name" {
  description = "Name of the Azure resource group"
  type        = string
}

variable "location" {
  description = "Azure region where resources will be deployed"
  type        = string
}

variable "acr_name" {
  description = "Name of the Azure Container Registry (must be globally unique)"
  type        = string
  validation {
    condition     = can(regex("^[a-zA-Z0-9]{5,50}$", var.acr_name))
    error_message = "ACR name must be 5-50 alphanumeric characters."
  }
}

variable "aci_name" {
  description = "Name prefix for Azure Container Instances"
  type        = string
}

variable "key_vault_name" {
  description = "Name of the Azure Key Vault (must be globally unique)"
  type        = string
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{3,24}$", var.key_vault_name))
    error_message = "Key Vault name must be 3-24 characters, alphanumeric and hyphens only."
  }
}

variable "storage_account_name" {
  description = "Name of the Azure Storage Account (must be globally unique)"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "Storage account name must be 3-24 lowercase alphanumeric characters."
  }
}

variable "github_org" {
  description = "GitHub organization name"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository in the format 'org/repo'"
  type        = string
}

variable "github_environment" {
  description = "GitHub environment name"
  type        = string
  default     = "production"
}

variable "cpu" {
  description = "Number of CPU cores per runner instance"
  type        = number
  default     = 2
  validation {
    condition     = var.cpu >= 1 && var.cpu <= 4
    error_message = "CPU must be between 1 and 4 cores."
  }
}

variable "memory" {
  description = "Memory in GB per runner instance"
  type        = number
  default     = 4
  validation {
    condition     = var.memory >= 1 && var.memory <= 16
    error_message = "Memory must be between 1 and 16 GB."
  }
}

variable "instance_count" {
  description = "Number of runner instances to deploy"
  type        = number
  default     = 1
  validation {
    condition     = var.instance_count >= 1 && var.instance_count <= 10
    error_message = "Instance count must be between 1 and 10."
  }
}

variable "runner_labels" {
  description = "Comma-separated labels for GitHub runners"
  type        = string
  default     = "azure,container-instance,self-hosted"
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "Production"
    ManagedBy   = "Terraform"
    Purpose     = "GitHubRunners"
  }
}

variable "enable_public_network_access" {
  description = "Enable public network access for resources (set to false for private endpoints)"
  type        = bool
  default     = true
}

variable "acr_sku" {
  description = "SKU for Azure Container Registry"
  type        = string
  default     = "Standard"
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.acr_sku)
    error_message = "ACR SKU must be Basic, Standard, or Premium."
  }
}

variable "storage_account_replication_type" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS"
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Invalid replication type."
  }
}

variable "github_runner_token" {
  description = "GitHub runner registration token (generate using: gh api repos/{owner}/{repo}/actions/runners/registration-token --jq .token)"
  type        = string
  sensitive   = true
}

variable "cleanup_frequency_hours" {
  description = "How many times per day to run cleanup job (e.g., 4 = every 6 hours)"
  type        = number
  default     = 4
  validation {
    condition     = var.cleanup_frequency_hours >= 1 && var.cleanup_frequency_hours <= 24
    error_message = "Cleanup frequency must be between 1 and 24 times per day."
  }
}

variable "max_runner_runtime_hours" {
  description = "Maximum hours a runner can run before being considered stuck and removed"
  type        = number
  default     = 8
  validation {
    condition     = var.max_runner_runtime_hours >= 1 && var.max_runner_runtime_hours <= 24
    error_message = "Max runtime must be between 1 and 24 hours."
  }
}

variable "runner_image" {
  description = "Container image for GitHub runners (should be pushed to the ACR first)"
  type        = string
  default     = "actions-runner:latest"
}
