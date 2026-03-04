variable "resource_group_name" {
  description = "Name of the Azure resource group"
  type        = string
}

variable "location" {
  description = "Azure region where resources will be deployed"
  type        = string
}

variable "subscription_id" {
  description = "Azure subscription ID to deploy resources into"
  type        = string
  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.subscription_id))
    error_message = "subscription_id must be a valid UUID."
  }
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
  description = "Base name for dynamically created Azure Container Instance runners (follows ci-{workload}-{env}-{instance} convention). Also used to derive the managed identity, App Service plan, and Application Insights names."
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
  description = "Default CPU cores for dynamically spawned runner instances"
  type        = number
  default     = 2
  validation {
    condition     = var.cpu >= 1 && var.cpu <= 4
    error_message = "CPU must be between 1 and 4 cores."
  }
}

variable "memory" {
  description = "Default memory (GB) for dynamically spawned runner instances"
  type        = number
  default     = 4
  validation {
    condition     = var.memory >= 1 && var.memory <= 16
    error_message = "Memory must be between 1 and 16 GB."
  }
}

variable "runner_min_instances" {
  description = "Minimum number of runner instances to keep available"
  type        = number
  default     = 0
  validation {
    condition     = var.runner_min_instances >= 0 && var.runner_min_instances <= 50
    error_message = "runner_min_instances must be between 0 and 50."
  }
}

variable "runner_max_instances" {
  description = "Maximum number of runner instances that the scaler may create"
  type        = number
  default     = 10
  validation {
    condition     = var.runner_max_instances >= 1 && var.runner_max_instances <= 200
    error_message = "runner_max_instances must be between 1 and 200."
  }
}

variable "runner_idle_timeout_minutes" {
  description = "Idle timeout in minutes before scaler should terminate unused runners"
  type        = number
  default     = 15
  validation {
    condition     = var.runner_idle_timeout_minutes >= 1 && var.runner_idle_timeout_minutes <= 240
    error_message = "runner_idle_timeout_minutes must be between 1 and 240."
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

variable "github_app_id_secret_name" {
  description = "Key Vault secret name containing GitHub App ID."
  type        = string
  default     = "runnerpocbouvet-github-app-id"
}

variable "github_app_installation_id_secret_name" {
  description = "Key Vault secret name containing GitHub App installation ID."
  type        = string
  default     = "runnerpocbouvet-github-app-installation-id"
}

variable "github_app_private_key_secret_name" {
  description = "Key Vault secret name containing GitHub App private key PEM."
  type        = string
  default     = "runnerpocbouvet-github-app-private-key"
}

variable "webhook_secret_secret_name" {
  description = "Optional Key Vault secret name containing webhook secret for GitHub signature validation."
  type        = string
  default     = null
}

variable "servicebus_namespace_name" {
  description = "Name of Service Bus namespace for runner scale events (must be globally unique)"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9-]{6,50}$", var.servicebus_namespace_name))
    error_message = "Service Bus namespace name must be 6-50 characters of lowercase letters, numbers, and hyphens."
  }
}

variable "servicebus_queue_name" {
  description = "Queue name used to buffer scale requests"
  type        = string
  default     = "runner-scale-requests"
}

variable "function_app_name" {
  description = "Name of Function App that ingests events and scales runners (must be globally unique)"
  type        = string
}

variable "function_storage_account_name" {
  description = "Storage account name for Azure Functions runtime (must be globally unique)"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.function_storage_account_name))
    error_message = "Function storage account name must be 3-24 lowercase alphanumeric characters."
  }
}

variable "function_runtime_version" {
  description = "Python runtime version for the scaler Function App"
  type        = string
  default     = "3.11"
}

variable "event_poll_interval_seconds" {
  description = "Polling cadence used by scaler worker when processing queue messages"
  type        = number
  default     = 5
  validation {
    condition     = var.event_poll_interval_seconds >= 1 && var.event_poll_interval_seconds <= 60
    error_message = "event_poll_interval_seconds must be between 1 and 60."
  }
}

variable "max_runner_runtime_hours" {
  description = "Maximum hours a dynamically spawned runner can run before scaler marks it stale"
  type        = number
  default     = 2
  validation {
    condition     = var.max_runner_runtime_hours >= 1 && var.max_runner_runtime_hours <= 24
    error_message = "Max runtime must be between 1 and 24 hours."
  }
}

variable "runner_completed_ttl_minutes" {
  description = "Minutes to keep a terminated/succeeded runner container before deleting it"
  type        = number
  default     = 5
  validation {
    condition     = var.runner_completed_ttl_minutes >= 1 && var.runner_completed_ttl_minutes <= 60
    error_message = "Completed TTL must be between 1 and 60 minutes."
  }
}
