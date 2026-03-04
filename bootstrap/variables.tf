# ==============================================================================
# Bootstrap Variables
# ==============================================================================

variable "resource_group_name" {
  description = "Resource group that will contain (or already contains) the state storage account."
  type        = string
}

variable "location" {
  description = "Azure region for the state storage account."
  type        = string
}

variable "subscription_id" {
  description = "Azure subscription ID to deploy resources into."
  type        = string
  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.subscription_id))
    error_message = "subscription_id must be a valid UUID."
  }
}

variable "state_storage_account_name" {
  description = "Name for the Terraform-state storage account (must be globally unique, 3-24 lowercase alphanumeric)."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.state_storage_account_name))
    error_message = "Storage account name must be 3-24 lowercase alphanumeric characters."
  }
}

variable "use_existing_storage" {
  description = <<-EOT
    When true, skip creating the storage account and adopt the one that already
    exists (e.g. a previous bootstrap run, or an account provisioned outside
    Terraform).  The bootstrap will still create/ensure the blob container.
    When false (default), the storage account is created from scratch.
  EOT
  type        = bool
  default     = false
}

variable "state_container_name" {
  description = "Blob container used to store Terraform state files."
  type        = string
  default     = "tfstate"
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.state_container_name))
    error_message = "Container name must be 3-63 lowercase alphanumeric characters or hyphens, starting and ending with alphanumeric."
  }
}

variable "storage_account_replication_type" {
  description = "Replication strategy for the state storage account."
  type        = string
  default     = "LRS"
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Invalid replication type."
  }
}

variable "tags" {
  description = "Tags applied to all created resources."
  type        = map(string)
  default     = {}
}
