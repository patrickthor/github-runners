# ==============================================================================
# Data Sources and Locals
# ==============================================================================

data "azurerm_client_config" "current" {}

locals {
  # ---------------------------------------------------------------------------
  # CAF naming: auto-generate all resource names from workload/environment/instance.
  # Every name can be overridden via the corresponding variable.
  # ---------------------------------------------------------------------------
  name_slug     = "${var.workload}-${var.environment}-${var.instance}"   # e.g. runner-poc-bvt
  name_compact  = "${var.workload}${var.environment}${var.instance}"     # e.g. runnerpocbvt

  resource_group_name           = coalesce(var.resource_group_name, "rg-${local.name_slug}")
  acr_name                      = coalesce(var.acr_name, "cr${local.name_compact}")
  aci_name                      = coalesce(var.aci_name, "ci-${local.name_slug}")
  key_vault_name                = coalesce(var.key_vault_name, "kv-${local.name_slug}")
  storage_account_name          = coalesce(var.storage_account_name, "st${local.name_compact}")
  function_app_name             = coalesce(var.function_app_name, "func-${local.name_slug}")
  function_storage_account_name = coalesce(var.function_storage_account_name, "stfn${local.name_compact}")
  servicebus_namespace_name     = coalesce(var.servicebus_namespace_name, "sbns-${local.name_slug}")

  # Suffix for resources derived from the ACI prefix (asp, appi, id, log)
  name_suffix = trimprefix(local.aci_name, "ci-")

  # ---------------------------------------------------------------------------
  # Auth helpers
  # ---------------------------------------------------------------------------
  has_github_app_id     = try(trimspace(var.github_app_id_secret_name), "") != ""
  has_github_app_inst   = try(trimspace(var.github_app_installation_id_secret_name), "") != ""
  has_github_app_key    = try(trimspace(var.github_app_private_key_secret_name), "") != ""
  has_complete_app_auth = local.has_github_app_id && local.has_github_app_inst && local.has_github_app_key
  has_webhook_secret    = try(trimspace(var.webhook_secret_secret_name), "") != ""

  github_app_id_secret_uri              = "${azurerm_key_vault.kv.vault_uri}secrets/${var.github_app_id_secret_name}"
  github_app_installation_id_secret_uri = "${azurerm_key_vault.kv.vault_uri}secrets/${var.github_app_installation_id_secret_name}"
  github_app_private_key_secret_uri     = "${azurerm_key_vault.kv.vault_uri}secrets/${var.github_app_private_key_secret_name}"
  webhook_secret_secret_uri             = local.has_webhook_secret ? "${azurerm_key_vault.kv.vault_uri}secrets/${var.webhook_secret_secret_name}" : null

  # Resolve Log Analytics workspace ID — either created or provided
  log_analytics_workspace_id = var.create_log_analytics_workspace ? azurerm_log_analytics_workspace.this[0].id : var.log_analytics_workspace_id

  # Default tags merged with user-provided tags
  default_tags = merge({
    ManagedBy   = "Terraform"
    Purpose     = "GitHubRunners"
    Environment = var.environment
    Workload    = var.workload
  }, var.tags)

  scaler_base_settings = {
    SERVICEBUS_QUEUE_NAME                          = var.servicebus_queue_name
    SERVICEBUS_NAMESPACE_FQDN                      = "${azurerm_servicebus_namespace.scaler.name}.servicebus.windows.net"
    SERVICEBUS_CONNECTION__fullyQualifiedNamespace  = "${azurerm_servicebus_namespace.scaler.name}.servicebus.windows.net"

    RUNNER_RESOURCE_GROUP         = local.resource_group_name
    RUNNER_NAME_PREFIX            = local.aci_name
    RUNNER_IMAGE                  = "${azurerm_container_registry.acr.login_server}/actions-runner:latest"
    RUNNER_LABELS                 = var.runner_labels
    RUNNER_CPU                    = tostring(var.cpu)
    RUNNER_MEMORY                 = tostring(var.memory)
    RUNNER_MIN_INSTANCES          = tostring(var.runner_min_instances)
    RUNNER_MAX_INSTANCES          = tostring(var.runner_max_instances)
    RUNNER_IDLE_TIMEOUT_MIN       = tostring(var.runner_idle_timeout_minutes)
    MAX_RUNNER_RUNTIME_HOURS      = tostring(var.max_runner_runtime_hours)
    RUNNER_COMPLETED_TTL_MINUTES  = tostring(var.runner_completed_ttl_minutes)
    EVENT_POLL_INTERVAL_SEC       = tostring(var.event_poll_interval_seconds)
    RUNNER_PULL_IDENTITY_ID        = azurerm_user_assigned_identity.runner_pull.id
    RUNNER_PULL_IDENTITY_CLIENT_ID = azurerm_user_assigned_identity.runner_pull.client_id
    AZURE_SUBSCRIPTION_ID          = data.azurerm_client_config.current.subscription_id
    AZURE_LOCATION                 = var.location
    GITHUB_REPO                    = var.github_repo
    GITHUB_ORG                     = var.github_org
    GITHUB_ENVIRONMENT             = var.github_environment
  }
}

# ==============================================================================
# Resource Group (conditional)
# ==============================================================================

resource "azurerm_resource_group" "this" {
  count    = var.create_resource_group ? 1 : 0
  name     = local.resource_group_name
  location = var.location
  tags     = local.default_tags
}

# ==============================================================================
# Log Analytics Workspace (conditional)
# ==============================================================================

resource "azurerm_log_analytics_workspace" "this" {
  count               = var.create_log_analytics_workspace ? 1 : 0
  name                = coalesce(var.log_analytics_workspace_name, "log-${local.name_suffix}")
  location            = var.location
  resource_group_name = local.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_retention_days
  tags                = local.default_tags

  depends_on = [azurerm_resource_group.this]
}

# ==============================================================================
# Container Registry
# ==============================================================================

resource "azurerm_container_registry" "acr" {
  name                          = local.acr_name
  resource_group_name           = local.resource_group_name
  location                      = var.location
  sku                           = var.acr_sku
  admin_enabled                 = false
  public_network_access_enabled = var.enable_public_network_access
  anonymous_pull_enabled        = false

  identity {
    type = "SystemAssigned"
  }

  network_rule_bypass_option = "AzureServices"
  tags                       = local.default_tags

  depends_on = [azurerm_resource_group.this]
}

# ==============================================================================
# Key Vault
# ==============================================================================

resource "azurerm_key_vault" "kv" {
  name                            = local.key_vault_name
  location                        = var.location
  resource_group_name             = local.resource_group_name
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
    default_action = "Allow"
    bypass         = "AzureServices"
  }

  tags       = local.default_tags
  depends_on = [azurerm_resource_group.this]
}

# State storage is provisioned by the bootstrap module — reference only.
data "azurerm_storage_account" "state" {
  name                = local.storage_account_name
  resource_group_name = local.resource_group_name

  depends_on = [azurerm_resource_group.this]
}

# ==============================================================================
# Service Bus
# ==============================================================================

resource "azurerm_servicebus_namespace" "scaler" {
  name                = local.servicebus_namespace_name
  location            = var.location
  resource_group_name = local.resource_group_name
  sku                 = "Basic"
  minimum_tls_version = "1.2"
  local_auth_enabled  = false
  tags                = local.default_tags

  depends_on = [azurerm_resource_group.this]
}

resource "azurerm_servicebus_queue" "scale_requests" {
  name         = var.servicebus_queue_name
  namespace_id = azurerm_servicebus_namespace.scaler.id

  max_delivery_count  = 30
  lock_duration       = "PT2M"
  default_message_ttl = "P14D"
}

# ==============================================================================
# Identities and Permissions for Dynamic Runner Creation
# ==============================================================================

resource "azurerm_user_assigned_identity" "runner_pull" {
  name                = "id-${local.name_suffix}"
  location            = var.location
  resource_group_name = local.resource_group_name
  tags                = merge(local.default_tags, { Purpose = "DynamicRunnerACRPull" })

  depends_on = [azurerm_resource_group.this]
}

resource "azurerm_role_assignment" "runner_acr_pull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.runner_pull.principal_id
}

# Runner workload roles — default is empty (least privilege).
# Callers must explicitly grant what their workflows need.
resource "azurerm_role_assignment" "runner_workload" {
  for_each             = toset(var.runner_workload_roles)
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  role_definition_name = each.value
  principal_id         = azurerm_user_assigned_identity.runner_pull.principal_id
}

# ==============================================================================
# Function App Storage (managed identity — no access keys)
# ==============================================================================

resource "azurerm_storage_account" "functions" {
  name                            = local.function_storage_account_name
  resource_group_name             = local.resource_group_name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  account_kind                    = "StorageV2"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  public_network_access_enabled   = var.enable_public_network_access
  allow_nested_items_to_be_public = false

  network_rules {
    default_action = "Allow"
    bypass         = ["AzureServices", "Logging", "Metrics"]
  }

  tags       = local.default_tags
  depends_on = [azurerm_resource_group.this]
}

# ==============================================================================
# Function App — Flex Consumption (FC1)
# ==============================================================================

resource "azurerm_service_plan" "functions" {
  name                = "asp-${local.name_suffix}"
  location            = var.location
  resource_group_name = local.resource_group_name
  os_type             = "Linux"
  sku_name            = "FC1"
  tags                = local.default_tags

  depends_on = [azurerm_resource_group.this]
}

resource "azurerm_application_insights" "scaler" {
  name                = "appi-${local.name_suffix}"
  location            = var.location
  resource_group_name = local.resource_group_name
  application_type    = "web"
  workspace_id        = local.log_analytics_workspace_id
  tags                = local.default_tags

  depends_on = [azurerm_resource_group.this]
}

resource "azurerm_storage_container" "function_deploy" {
  name                  = "function-deployments"
  storage_account_id    = azurerm_storage_account.functions.id
  container_access_type = "private"
}

resource "azurerm_function_app_flex_consumption" "scaler" {
  name                = local.function_app_name
  location            = var.location
  resource_group_name = local.resource_group_name

  service_plan_id = azurerm_service_plan.functions.id

  # Flex Consumption storage config (deployment artifacts)
  # NOTE: SystemAssignedIdentity causes "Failed to fetch host key" during deployment.
  # Using StorageAccountConnectionString until Azure fully supports MSI for FC1 deployments.
  # See: https://github.com/hashicorp/terraform-provider-azurerm/issues/29993
  storage_container_type      = "blobContainer"
  storage_container_endpoint  = "${azurerm_storage_account.functions.primary_blob_endpoint}${azurerm_storage_container.function_deploy.name}"
  storage_authentication_type = "StorageAccountConnectionString"
  storage_access_key          = azurerm_storage_account.functions.primary_access_key

  runtime_name    = "python"
  runtime_version = var.function_runtime_version

  # VNet integration (optional)
  virtual_network_subnet_id = var.subnet_id

  identity {
    type = "SystemAssigned"
  }

  site_config {
    # Connection string only — instrumentation key is deprecated since March 2025
    application_insights_connection_string = azurerm_application_insights.scaler.connection_string

    ip_restriction_default_action = length(var.github_webhook_ip_ranges) > 0 || length(var.deployment_ip_ranges) > 0 ? "Deny" : "Allow"

    dynamic "ip_restriction" {
      for_each = var.github_webhook_ip_ranges
      content {
        name       = "github-webhook-${ip_restriction.key}"
        ip_address = ip_restriction.value
        action     = "Allow"
        priority   = 100 + ip_restriction.key
      }
    }

    dynamic "ip_restriction" {
      for_each = var.deployment_ip_ranges
      content {
        name       = "deploy-${ip_restriction.key}"
        ip_address = ip_restriction.value
        action     = "Allow"
        priority   = 200 + ip_restriction.key
      }
    }
  }

  app_settings = merge(
    local.scaler_base_settings,
    local.has_complete_app_auth ? {
      GITHUB_APP_ID              = "@Microsoft.KeyVault(SecretUri=${local.github_app_id_secret_uri})"
      GITHUB_APP_INSTALLATION_ID = "@Microsoft.KeyVault(SecretUri=${local.github_app_installation_id_secret_uri})"
      GITHUB_APP_PRIVATE_KEY     = "@Microsoft.KeyVault(SecretUri=${local.github_app_private_key_secret_uri})"
    } : {},
    local.has_webhook_secret ? {
      WEBHOOK_SECRET = "@Microsoft.KeyVault(SecretUri=${local.webhook_secret_secret_uri})"
    } : {},
  )

  lifecycle {
    precondition {
      condition     = local.has_complete_app_auth
      error_message = "GitHub App auth is required. Set github_app_id_secret_name, github_app_installation_id_secret_name, and github_app_private_key_secret_name."
    }
    precondition {
      condition = (
        (!local.has_github_app_id && !local.has_github_app_inst && !local.has_github_app_key) ||
        local.has_complete_app_auth
      )
      error_message = "GitHub App auth requires all three values: github_app_id_secret_name, github_app_installation_id_secret_name, and github_app_private_key_secret_name."
    }
    precondition {
      condition     = var.runner_min_instances <= var.runner_max_instances
      error_message = "runner_min_instances must be less than or equal to runner_max_instances."
    }
    precondition {
      condition     = var.create_log_analytics_workspace || var.log_analytics_workspace_id != null
      error_message = "Either create_log_analytics_workspace must be true, or log_analytics_workspace_id must be provided."
    }
  }

  tags = local.default_tags
}

# ==============================================================================
# RBAC — Function App managed identity
# ==============================================================================

# Storage RBAC for identity-based connection (replaces access key)
resource "azurerm_role_assignment" "func_storage_blob" {
  scope                = azurerm_storage_account.functions.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_function_app_flex_consumption.scaler.identity[0].principal_id
}

resource "azurerm_role_assignment" "func_storage_queue" {
  scope                = azurerm_storage_account.functions.id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = azurerm_function_app_flex_consumption.scaler.identity[0].principal_id
}

resource "azurerm_role_assignment" "func_storage_table" {
  scope                = azurerm_storage_account.functions.id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = azurerm_function_app_flex_consumption.scaler.identity[0].principal_id
}

# Service Bus — send/receive for scale events
resource "azurerm_role_assignment" "scaler_servicebus_owner" {
  scope                = azurerm_servicebus_namespace.scaler.id
  role_definition_name = "Azure Service Bus Data Owner"
  principal_id         = azurerm_function_app_flex_consumption.scaler.identity[0].principal_id
}

# ACI management — scoped to resource group (not subscription)
resource "azurerm_role_assignment" "scaler_contributor" {
  scope                = var.create_resource_group ? azurerm_resource_group.this[0].id : "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${local.resource_group_name}"
  role_definition_name = "Contributor"
  principal_id         = azurerm_function_app_flex_consumption.scaler.identity[0].principal_id
}

# Managed Identity Operator — needed to assign runner_pull identity to ACI
resource "azurerm_role_assignment" "scaler_uai_operator" {
  scope                = azurerm_user_assigned_identity.runner_pull.id
  role_definition_name = "Managed Identity Operator"
  principal_id         = azurerm_function_app_flex_consumption.scaler.identity[0].principal_id
}

# Key Vault secrets access
resource "azurerm_role_assignment" "scaler_keyvault_secrets_user" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_function_app_flex_consumption.scaler.identity[0].principal_id
}

# ==============================================================================
# Diagnostic Settings — Key Vault, Service Bus, Function App
# ==============================================================================

resource "azurerm_monitor_diagnostic_setting" "key_vault" {
  name                       = "diag-${local.key_vault_name}"
  target_resource_id         = azurerm_key_vault.kv.id
  log_analytics_workspace_id = local.log_analytics_workspace_id

  enabled_log {
    category = "AuditEvent"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "servicebus" {
  name                       = "diag-${local.servicebus_namespace_name}"
  target_resource_id         = azurerm_servicebus_namespace.scaler.id
  log_analytics_workspace_id = local.log_analytics_workspace_id

  enabled_log {
    category = "OperationalLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "function_app" {
  name                       = "diag-${local.function_app_name}"
  target_resource_id         = azurerm_function_app_flex_consumption.scaler.id
  log_analytics_workspace_id = local.log_analytics_workspace_id

  enabled_log {
    category = "FunctionAppLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

# ==============================================================================
# Resource Locks (conditional — disable in dev/test)
# ==============================================================================

resource "azurerm_management_lock" "key_vault" {
  count      = var.enable_resource_locks ? 1 : 0
  name       = "lock-${local.key_vault_name}"
  scope      = azurerm_key_vault.kv.id
  lock_level = "CanNotDelete"
  notes      = "Protects Key Vault containing GitHub App credentials"
}

resource "azurerm_management_lock" "state_storage" {
  count      = var.enable_resource_locks ? 1 : 0
  name       = "lock-${local.storage_account_name}"
  scope      = data.azurerm_storage_account.state.id
  lock_level = "CanNotDelete"
  notes      = "Protects Terraform state storage account"
}

# ==============================================================================
# State migration — resource type change from linux_function_app to flex_consumption
# Safe to remove after all environments have applied once with this block.
# ==============================================================================

moved {
  from = azurerm_linux_function_app.scaler
  to   = azurerm_function_app_flex_consumption.scaler
}
