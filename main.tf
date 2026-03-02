# ==============================================================================
# Data Sources
# ==============================================================================

data "azurerm_client_config" "current" {}

# ==============================================================================
# Azure Container Registry
# ==============================================================================

resource "azurerm_container_registry" "acr" {
  name                          = var.acr_name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  sku                           = var.acr_sku
  admin_enabled                 = false
  public_network_access_enabled = var.enable_public_network_access
  anonymous_pull_enabled        = false

  identity {
    type = "SystemAssigned"
  }

  network_rule_bypass_option = "AzureServices"

  tags = var.tags
}

# ==============================================================================
# Azure Key Vault
# ==============================================================================

resource "azurerm_key_vault" "kv" {
  name                            = var.key_vault_name
  location                        = var.location
  resource_group_name             = var.resource_group_name
  tenant_id                       = data.azurerm_client_config.current.tenant_id
  sku_name                        = "standard"
  soft_delete_retention_days      = 90
  purge_protection_enabled        = true
  enabled_for_disk_encryption     = false
  enabled_for_deployment          = false
  enabled_for_template_deployment = false
  public_network_access_enabled   = var.enable_public_network_access
  rbac_authorization_enabled      = true

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
  }

  tags = var.tags
}

# ==============================================================================
# Azure Storage Account
# ==============================================================================

resource "azurerm_storage_account" "storage" {
  name                            = var.storage_account_name
  resource_group_name             = var.resource_group_name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = var.storage_account_replication_type
  account_kind                    = "StorageV2"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  public_network_access_enabled   = var.enable_public_network_access
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
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }

  tags = var.tags
}

# ==============================================================================
# Managed Identities
# ==============================================================================

# User Assigned Identity for ACR Pull (OIDC-based authentication)
resource "azurerm_user_assigned_identity" "acr_pull" {
  count               = var.instance_count
  name                = "${var.aci_name}-acr-pull-${count.index}"
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = merge(var.tags, {
    Purpose = "ACRPull"
  })
}

# ==============================================================================
# Azure Container Instances - GitHub Runners
# ==============================================================================

resource "azurerm_container_group" "runner" {
  count               = var.instance_count
  name                = "${var.aci_name}-${count.index}"
  location            = var.location
  resource_group_name = var.resource_group_name
  os_type             = "Linux"
  restart_policy      = "Always"

  identity {
    type = "SystemAssigned"
  }

  image_registry_credential {
    server                    = azurerm_container_registry.acr.login_server
    user_assigned_identity_id = azurerm_user_assigned_identity.acr_pull[count.index].id
  }

  container {
    name   = "github-runner"
    image  = "${azurerm_container_registry.acr.login_server}/${var.runner_image}"
    cpu    = var.cpu
    memory = var.memory

    environment_variables = {
      GITHUB_REPO        = var.github_repo
      GITHUB_ORG         = var.github_org
      GITHUB_ENVIRONMENT = var.github_environment
      RUNNER_NAME        = "${var.aci_name}-${count.index}"
      RUNNER_LABELS      = var.runner_labels
    }

    secure_environment_variables = {
      RUNNER_TOKEN = var.github_runner_token
    }

    liveness_probe {
      http_get {
        path   = "/health"
        port   = 8080
        scheme = "Http"
      }
      initial_delay_seconds = 30
      period_seconds        = 10
      failure_threshold     = 3
    }
  }

  tags = merge(var.tags, {
    Instance = tostring(count.index)
  })
}

# ==============================================================================
# RBAC Role Assignments
# ==============================================================================

# Grant AcrPull role to user-assigned identity
resource "azurerm_role_assignment" "acr_pull" {
  count                            = var.instance_count
  scope                            = azurerm_container_registry.acr.id
  role_definition_name             = "AcrPull"
  principal_id                     = azurerm_user_assigned_identity.acr_pull[count.index].principal_id
  skip_service_principal_aad_check = true
}

# Grant Key Vault Secrets User role to ACI system-assigned identity
resource "azurerm_role_assignment" "kv_access" {
  count                            = var.instance_count
  scope                            = azurerm_key_vault.kv.id
  role_definition_name             = "Key Vault Secrets User"
  principal_id                     = azurerm_container_group.runner[count.index].identity[0].principal_id
  skip_service_principal_aad_check = true
}

# Grant Storage Blob Data Contributor role to ACI system-assigned identity
resource "azurerm_role_assignment" "storage_access" {
  count                            = var.instance_count
  scope                            = azurerm_storage_account.storage.id
  role_definition_name             = "Storage Blob Data Contributor"
  principal_id                     = azurerm_container_group.runner[count.index].identity[0].principal_id
  skip_service_principal_aad_check = true
}

# ==============================================================================
# Azure Automation Account for Runner Cleanup
# ==============================================================================

resource "azurerm_automation_account" "cleanup" {
  name                = "${var.aci_name}-automation"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku_name            = "Basic"

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

# Grant Automation Account permissions to manage container instances
resource "azurerm_role_assignment" "automation_contributor" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${var.resource_group_name}"
  role_definition_name = "Contributor"
  principal_id         = azurerm_automation_account.cleanup.identity[0].principal_id
}

# PowerShell runbook to clean up stale runners
resource "azurerm_automation_runbook" "cleanup_runners" {
  name                    = "Cleanup-StaleRunners"
  location                = var.location
  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.cleanup.name
  log_verbose             = true
  log_progress            = true
  runbook_type            = "PowerShell"

  content = <<-POWERSHELL
    <#
    .SYNOPSIS
        Cleans up stale GitHub runner containers
    
    .DESCRIPTION
        Removes Azure Container Instances that are:
        - In failed or stopped state
        - Running longer than max threshold (stuck/zombie)
        - Restarting repeatedly (crash loop)
    #>

    param(
        [Parameter(Mandatory=$true)]
        [string]$ResourceGroupName,
        
        [Parameter(Mandatory=$true)]
        [string]$ContainerPrefix,
        
        [Parameter(Mandatory=$false)]
        [int]$MaxRuntimeHours = 8,
        
        [Parameter(Mandatory=$false)]
        [int]$MaxRestartCount = 10
    )

    # Authenticate using managed identity
    try {
        Connect-AzAccount -Identity
        Write-Output "Successfully authenticated with managed identity"
    }
    catch {
        Write-Error "Failed to authenticate: $_"
        exit 1
    }

    # Get all container instances with the prefix
    $containers = Get-AzContainerGroup -ResourceGroupName $ResourceGroupName | Where-Object { $_.Name -like "$ContainerPrefix*" }
    Write-Output "Found $($containers.Count) container instances with prefix '$ContainerPrefix'"

    $removedCount = 0
    $failedCount = 0
    $warningCount = 0

    foreach ($container in $containers) {
        $containerName = $container.Name
        $state = $container.InstanceViewState
        $shouldRemove = $false
        $reason = ""
        
        Write-Output "Checking container: $containerName (State: $state)"
        
        # Check 1: Remove if in failed or stopped state
        if ($state -eq "Failed" -or $state -eq "Stopped") {
            $shouldRemove = $true
            $reason = "Container in $state state"
        }
        
        # Check 2: Remove if running too long (likely stuck)
        if (-not $shouldRemove -and $container.InstanceViewStartTime) {
            $runningTime = (Get-Date) - $container.InstanceViewStartTime
            if ($runningTime.TotalHours -gt $MaxRuntimeHours) {
                $shouldRemove = $true
                $reason = "Running for $([math]::Round($runningTime.TotalHours, 1)) hours (max: $MaxRuntimeHours)"
            }
            elseif ($runningTime.TotalHours -gt ($MaxRuntimeHours * 0.75)) {
                Write-Warning "Container $containerName approaching max runtime: $([math]::Round($runningTime.TotalHours, 1)) hours"
                $warningCount++
            }
        }
        
        # Check 3: Remove if restarting too many times (crash loop)
        if (-not $shouldRemove -and $container.Containers) {
            $restartCount = $container.Containers[0].InstanceViewRestartCount
            if ($restartCount -gt $MaxRestartCount) {
                $shouldRemove = $true
                $reason = "Restart count ($restartCount) exceeds max ($MaxRestartCount)"
            }
        }
        
        # Remove container if any condition met
        if ($shouldRemove) {
            Write-Output "Removing $containerName - Reason: $reason"
            try {
                Remove-AzContainerGroup -ResourceGroupName $ResourceGroupName -Name $containerName -Force
                Write-Output "Successfully removed $containerName"
                $removedCount++
            }
            catch {
                Write-Error "Failed to remove $containerName: $_"
                $failedCount++
            }
        }
    }

    Write-Output "========================================="
    Write-Output "Cleanup Summary:"
    Write-Output "  Total containers checked: $($containers.Count)"
    Write-Output "  Removed: $removedCount"
    Write-Output "  Failed to remove: $failedCount"
    Write-Output "  Warnings: $warningCount"
    Write-Output "========================================="
    POWERSHELL

  tags = var.tags
}

# Schedule to run cleanup job
resource "azurerm_automation_schedule" "cleanup_schedule" {
  name                    = "cleanup-schedule"
  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.cleanup.name
  frequency               = "Hour"
  interval                = floor(24 / var.cleanup_frequency_hours)
  start_time              = timeadd(timestamp(), "1h")
  timezone                = "UTC"
  description             = "Run runner cleanup every ${floor(24 / var.cleanup_frequency_hours)} hours"

  lifecycle {
    ignore_changes = [start_time]
  }
}

# Link schedule to runbook
resource "azurerm_automation_job_schedule" "cleanup_job" {
  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.cleanup.name
  schedule_name           = azurerm_automation_schedule.cleanup_schedule.name
  runbook_name            = azurerm_automation_runbook.cleanup_runners.name

  parameters = {
    ResourceGroupName = var.resource_group_name
    ContainerPrefix   = var.aci_name
    MaxRuntimeHours   = var.max_runner_runtime_hours
  }
}

# ==============================================================================
# GitHub Runner Token Notes
# ==============================================================================
#
# GitHub runner registration tokens must be generated externally and passed
# as a variable. Tokens are short-lived (1 hour) and should be generated
# just before deployment.
#
# Generate token using GitHub CLI:
#   gh api repos/{owner}/{repo}/actions/runners/registration-token --jq .token
#
# Or using curl:
#   curl -X POST \
#     -H "Authorization: token ${GITHUB_TOKEN}" \
#     https://api.github.com/repos/{owner}/{repo}/actions/runners/registration-token
#
# ==============================================================================
