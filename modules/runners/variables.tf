# ==============================================================================
# Core Variables — the minimum needed to deploy
# ==============================================================================

variable "workload" {
  description = "Short workload identifier used to generate all resource names (e.g. 'runner')"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9]{2,12}$", var.workload))
    error_message = "workload must be 2-12 lowercase alphanumeric characters."
  }
}

variable "environment" {
  description = "Environment identifier (e.g. 'poc', 'dev', 'prod')"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9]{2,8}$", var.environment))
    error_message = "environment must be 2-8 lowercase alphanumeric characters."
  }
}

variable "instance" {
  description = "Instance identifier for uniqueness (e.g. 'bvt', '001')"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9]{2,8}$", var.instance))
    error_message = "instance must be 2-8 lowercase alphanumeric characters."
  }
}

variable "location" {
  description = "Azure region where resources will be deployed"
  type        = string
}

variable "github_org" {
  description = "GitHub organization name"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository in the format 'org/repo'"
  type        = string
}

# ==============================================================================
# GitHub App Secrets (Key Vault secret names) — required, no defaults
# ==============================================================================

variable "github_app_id_secret_name" {
  description = "Key Vault secret name containing GitHub App ID"
  type        = string
}

variable "github_app_installation_id_secret_name" {
  description = "Key Vault secret name containing GitHub App installation ID"
  type        = string
}

variable "github_app_private_key_secret_name" {
  description = "Key Vault secret name containing GitHub App private key PEM"
  type        = string
}

variable "webhook_secret_secret_name" {
  description = "Optional Key Vault secret name containing webhook secret for GitHub signature validation"
  type        = string
  default     = null
}

# ==============================================================================
# Resource Name Overrides — auto-generated from workload/environment/instance
# if not provided. Override any name that needs to differ from the convention.
# ==============================================================================

variable "resource_group_name" {
  description = "Override: resource group name. Default: rg-{workload}-{environment}-{instance}"
  type        = string
  default     = null
}

variable "acr_name" {
  description = "Override: Container Registry name (alphanumeric only, globally unique). Default: cr{workload}{environment}{instance}"
  type        = string
  default     = null
  validation {
    condition     = var.acr_name == null || can(regex("^[a-zA-Z0-9]{5,50}$", var.acr_name))
    error_message = "ACR name must be 5-50 alphanumeric characters."
  }
}

variable "aci_name" {
  description = "Override: ACI runner name prefix. Default: ci-{workload}-{environment}-{instance}"
  type        = string
  default     = null
}

variable "key_vault_name" {
  description = "Override: Key Vault name (globally unique). Default: kv-{workload}-{environment}-{instance}"
  type        = string
  default     = null
  validation {
    condition     = var.key_vault_name == null || can(regex("^[a-zA-Z0-9-]{3,24}$", var.key_vault_name))
    error_message = "Key Vault name must be 3-24 characters, alphanumeric and hyphens only."
  }
}

variable "storage_account_name" {
  description = "Override: storage account name used for resource locks (only relevant when enable_resource_locks = true). Default: st{workload}{environment}{instance}"
  type        = string
  default     = null
  validation {
    condition     = var.storage_account_name == null || can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "Storage account name must be 3-24 lowercase alphanumeric characters."
  }
}

variable "function_app_name" {
  description = "Override: Function App name (globally unique). Default: func-{workload}-{environment}-{instance}"
  type        = string
  default     = null
}

variable "function_storage_account_name" {
  description = "Override: Function App storage account name (globally unique). Default: stfn{workload}{environment}{instance}"
  type        = string
  default     = null
  validation {
    condition     = var.function_storage_account_name == null || can(regex("^[a-z0-9]{3,24}$", var.function_storage_account_name))
    error_message = "Function storage account name must be 3-24 lowercase alphanumeric characters."
  }
}

variable "servicebus_namespace_name" {
  description = "Override: Service Bus namespace name (globally unique). Default: sbns-{workload}-{environment}-{instance}"
  type        = string
  default     = null
  validation {
    condition     = var.servicebus_namespace_name == null || can(regex("^[a-z0-9-]{6,50}$", var.servicebus_namespace_name))
    error_message = "Service Bus namespace name must be 6-50 characters of lowercase letters, numbers, and hyphens."
  }
}

# ==============================================================================
# Resource Group
# ==============================================================================

variable "create_resource_group" {
  description = "Whether the module should create the resource group. Set to false if it already exists."
  type        = bool
  default     = true
}

# ==============================================================================
# Log Analytics & Observability
# ==============================================================================

variable "create_log_analytics_workspace" {
  description = "Whether to create a new Log Analytics workspace. Set to false and provide log_analytics_workspace_id to use an existing one."
  type        = bool
  default     = true
}

variable "log_analytics_workspace_id" {
  description = "ID of an existing Log Analytics workspace. Required when create_log_analytics_workspace = false."
  type        = string
  default     = null
}

variable "log_analytics_workspace_name" {
  description = "Override: Log Analytics workspace name. Default: log-{workload}-{environment}-{instance}"
  type        = string
  default     = null
}

variable "log_analytics_retention_days" {
  description = "Retention period in days for Log Analytics workspace"
  type        = number
  default     = 30
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Retention must be between 30 and 730 days."
  }
}

# ==============================================================================
# Networking
# ==============================================================================

variable "subnet_id" {
  description = "Optional subnet ID for VNet integration of the Function App. Leave null for public access."
  type        = string
  default     = null
}

variable "enable_public_network_access" {
  description = "Enable public network access for resources (set to false when using private endpoints/VNet)"
  type        = bool
  default     = true
}

# ==============================================================================
# Runner Configuration
# ==============================================================================

variable "cpu" {
  description = "CPU cores for dynamically spawned runner instances"
  type        = number
  default     = 2
  validation {
    condition     = var.cpu >= 1 && var.cpu <= 4
    error_message = "CPU must be between 1 and 4 cores."
  }
}

variable "memory" {
  description = "Memory (GB) for dynamically spawned runner instances"
  type        = number
  default     = 4
  validation {
    condition     = var.memory >= 1 && var.memory <= 16
    error_message = "Memory must be between 1 and 16 GB."
  }
}

variable "runner_min_instances" {
  description = "Minimum number of runner instances to keep available (set > 0 for always-ready warm runners)"
  type        = number
  default     = 0
  validation {
    condition     = var.runner_min_instances >= 0 && var.runner_min_instances <= 50
    error_message = "The runner_min_instances must be between 0 and 50."
  }
}

variable "runner_max_instances" {
  description = "Maximum number of runner instances that the scaler may create"
  type        = number
  default     = 5
  validation {
    condition     = var.runner_max_instances >= 1 && var.runner_max_instances <= 200
    error_message = "The runner_max_instances must be between 1 and 200."
  }
}

variable "runner_labels" {
  description = "Comma-separated labels for GitHub runners"
  type        = string
  default     = "azure,container-instance,self-hosted"
}

variable "max_runner_runtime_hours" {
  description = "Maximum hours a runner can run before scaler marks it stale"
  type        = number
  default     = 2
  validation {
    condition     = var.max_runner_runtime_hours >= 1 && var.max_runner_runtime_hours <= 24
    error_message = "Max runtime must be between 1 and 24 hours."
  }
}

variable "runner_completed_ttl_minutes" {
  description = "Minutes to keep a terminated runner container before deleting it"
  type        = number
  default     = 5
  validation {
    condition     = var.runner_completed_ttl_minutes >= 1 && var.runner_completed_ttl_minutes <= 60
    error_message = "Completed TTL must be between 1 and 60 minutes."
  }
}

# ==============================================================================
# RBAC & Security
# ==============================================================================

variable "runner_workload_roles" {
  description = "Azure built-in roles granted to the runner identity at subscription scope. Default is empty — explicitly choose what runners need."
  type        = list(string)
  default     = []
}

variable "enable_resource_locks" {
  description = "Enable CanNotDelete locks on Key Vault and state storage. Disable in dev/test environments."
  type        = bool
  default     = false
}

# ==============================================================================
# Service Configuration
# ==============================================================================

variable "github_environment" {
  description = "GitHub environment name"
  type        = string
  default     = "production"
}

variable "servicebus_queue_name" {
  description = "Queue name used to buffer scale requests"
  type        = string
  default     = "runner-scale-requests"
}

variable "cleanup_timer_schedule" {
  description = "NCRONTAB schedule for the cleanup timer function. Default: every 3 minutes."
  type        = string
  default     = "0 */3 * * * *"
}

variable "function_runtime_version" {
  description = "Python runtime version for the scaler Function App"
  type        = string
  default     = "3.11"
}

variable "acr_sku" {
  description = "SKU for Azure Container Registry (Premium required for private endpoints)"
  type        = string
  default     = "Basic"
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

variable "github_webhook_ip_ranges" {
  description = "GitHub webhook CIDR ranges allowed to reach the Function App. Set to [] to disable IP restriction."
  type        = list(string)
  default = [
    "192.30.252.0/22",
    "185.199.108.0/22",
    "140.82.112.0/20",
    "143.55.64.0/20",
  ]
}

variable "deployment_ip_ranges" {
  description = "Additional CIDR ranges to allow through the Function App IP restrictions (e.g. GitHub Actions runner IPs for deployment). These are added alongside the webhook IP ranges."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Common tags to apply to all resources. Merged with auto-generated tags."
  type        = map(string)
  default     = {}
}
