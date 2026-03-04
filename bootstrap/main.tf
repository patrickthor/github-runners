# ==============================================================================
# Bootstrap — Remote State Foundation
#
# This module is the first thing that runs in a fresh environment.
# It owns the storage account that holds every other module's Terraform state.
#
# Two modes:
#   use_existing_storage = false (default)   → create the storage account
#   use_existing_storage = true              → adopt an existing account
#
# In BOTH modes the blob container is created/ensured idempotently.
# ==============================================================================

locals {
  create_storage       = !var.use_existing_storage
  storage_account_id   = local.create_storage ? azurerm_storage_account.state[0].id : data.azurerm_storage_account.existing[0].id
  storage_account_name = local.create_storage ? azurerm_storage_account.state[0].name : data.azurerm_storage_account.existing[0].name
}

# ------------------------------------------------------------------
# Create path: provision a new hardened storage account
# ------------------------------------------------------------------
resource "azurerm_storage_account" "state" {
  count = local.create_storage ? 1 : 0

  name                            = var.state_storage_account_name
  resource_group_name             = var.resource_group_name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = var.storage_account_replication_type
  account_kind                    = "StorageV2"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  public_network_access_enabled   = true
  shared_access_key_enabled       = false
  allow_nested_items_to_be_public = false

  identity {
    type = "SystemAssigned"
  }

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 7
    }

    container_delete_retention_policy {
      days = 7
    }
  }

  network_rules {
    default_action = "Allow"
    bypass         = ["AzureServices"]
  }

  tags = merge(var.tags, {
    Purpose = "TerraformRemoteState"
  })
}

# ------------------------------------------------------------------
# Adopt path: reference an account that already exists
# ------------------------------------------------------------------
data "azurerm_storage_account" "existing" {
  count               = local.create_storage ? 0 : 1
  name                = var.state_storage_account_name
  resource_group_name = var.resource_group_name
}

# ------------------------------------------------------------------
# Blob container (idempotent in both paths)
# ------------------------------------------------------------------
resource "azurerm_storage_container" "tfstate" {
  name                  = var.state_container_name
  storage_account_id    = local.storage_account_id
  container_access_type = "private"
}
