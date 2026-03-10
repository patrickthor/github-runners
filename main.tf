# ==============================================================================
# Data Sources and Locals
# ==============================================================================

data "azurerm_client_config" "current" {}

locals {
  has_github_app_id     = try(trimspace(var.github_app_id_secret_name), "") != ""
  has_github_app_inst   = try(trimspace(var.github_app_installation_id_secret_name), "") != ""
  has_github_app_key    = try(trimspace(var.github_app_private_key_secret_name), "") != ""
  has_complete_app_auth = local.has_github_app_id && local.has_github_app_inst && local.has_github_app_key
  has_webhook_secret    = try(trimspace(var.webhook_secret_secret_name), "") != ""

  github_app_id_secret_uri              = "${azurerm_key_vault.kv.vault_uri}secrets/${var.github_app_id_secret_name}"
  github_app_installation_id_secret_uri = "${azurerm_key_vault.kv.vault_uri}secrets/${var.github_app_installation_id_secret_name}"
  github_app_private_key_secret_uri     = "${azurerm_key_vault.kv.vault_uri}secrets/${var.github_app_private_key_secret_name}"
  webhook_secret_secret_uri             = local.has_webhook_secret ? "${azurerm_key_vault.kv.vault_uri}secrets/${var.webhook_secret_secret_name}" : null

  scaler_base_settings = {
    FUNCTIONS_WORKER_RUNTIME                 = "python"
    SERVICEBUS_QUEUE_NAME                          = var.servicebus_queue_name
    SERVICEBUS_NAMESPACE_FQDN                      = "${azurerm_servicebus_namespace.scaler.name}.servicebus.windows.net"
    SERVICEBUS_CONNECTION__fullyQualifiedNamespace = "${azurerm_servicebus_namespace.scaler.name}.servicebus.windows.net"

    RUNNER_RESOURCE_GROUP    = var.resource_group_name
    RUNNER_NAME_PREFIX       = var.aci_name
    RUNNER_IMAGE             = "${azurerm_container_registry.acr.login_server}/actions-runner:latest"
    RUNNER_LABELS            = var.runner_labels
    RUNNER_CPU               = tostring(var.cpu)
    RUNNER_MEMORY            = tostring(var.memory)
    RUNNER_MIN_INSTANCES     = tostring(var.runner_min_instances)
    RUNNER_MAX_INSTANCES     = tostring(var.runner_max_instances)
    RUNNER_IDLE_TIMEOUT_MIN  = tostring(var.runner_idle_timeout_minutes)
    MAX_RUNNER_RUNTIME_HOURS      = tostring(var.max_runner_runtime_hours)
    RUNNER_COMPLETED_TTL_MINUTES  = tostring(var.runner_completed_ttl_minutes)
    EVENT_POLL_INTERVAL_SEC       = tostring(var.event_poll_interval_seconds)
    RUNNER_PULL_IDENTITY_ID        = azurerm_user_assigned_identity.runner_pull.id
    RUNNER_PULL_IDENTITY_CLIENT_ID = azurerm_user_assigned_identity.runner_pull.client_id
    AZURE_SUBSCRIPTION_ID          = data.azurerm_client_config.current.subscription_id
    AZURE_LOCATION           = var.location
    GITHUB_REPO              = var.github_repo
    GITHUB_ORG               = var.github_org
    GITHUB_ENVIRONMENT       = var.github_environment
  }
}

# ==============================================================================
# Core Artifacts
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
    default_action = "Allow"
    bypass         = "AzureServices"
  }

  tags = var.tags
}

# The state storage account is provisioned by the bootstrap module.
# This data source lets the main module reference it (e.g. for outputs) without
# owning it.  If you are migrating an existing environment, run:
#   terraform state rm azurerm_storage_account.storage   (old resource name)
# before your first apply with this backend configuration.
data "azurerm_storage_account" "state" {
  name                = var.storage_account_name
  resource_group_name = var.resource_group_name
}

# ==============================================================================
# Event Bus
# ==============================================================================

resource "azurerm_servicebus_namespace" "scaler" {
  name                = var.servicebus_namespace_name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Basic"
  minimum_tls_version = "1.2"
  local_auth_enabled  = false

  tags = var.tags
}

resource "azurerm_servicebus_queue" "scale_requests" {
  name         = var.servicebus_queue_name
  namespace_id = azurerm_servicebus_namespace.scaler.id

  max_delivery_count  = 30
  lock_duration       = "PT2M"
  default_message_ttl = "P14D"
}

resource "azurerm_role_assignment" "scaler_servicebus_owner" {
  scope                = azurerm_servicebus_namespace.scaler.id
  role_definition_name = "Azure Service Bus Data Owner"
  principal_id         = azurerm_linux_function_app.scaler.identity[0].principal_id
}

# ==============================================================================
# Identities and Permissions for Dynamic Runner Creation
# ==============================================================================

resource "azurerm_user_assigned_identity" "runner_pull" {
  name                = "id-${trimprefix(var.aci_name, "ci-")}"
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = merge(var.tags, {
    Purpose = "DynamicRunnerACRPull"
  })
}

resource "azurerm_role_assignment" "runner_pull" {
  scope                            = azurerm_container_registry.acr.id
  role_definition_name             = "AcrPull"
  principal_id                     = azurerm_user_assigned_identity.runner_pull.principal_id
}

resource "azurerm_role_assignment" "runner_pull_workload" {
  for_each             = toset(var.runner_workload_roles)
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  role_definition_name = each.value
  principal_id         = azurerm_user_assigned_identity.runner_pull.principal_id
}

# ==============================================================================
# Event-Driven Scaler Function App
# ==============================================================================

resource "azurerm_storage_account" "functions" {
  name                            = var.function_storage_account_name
  resource_group_name             = var.resource_group_name
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

  tags = var.tags
}

resource "azurerm_service_plan" "functions" {
  name                = "asp-${trimprefix(var.aci_name, "ci-")}"
  location            = var.location
  resource_group_name = var.resource_group_name
  os_type             = "Linux"
  sku_name            = "Y1"

  tags = var.tags
}

resource "azurerm_application_insights" "scaler" {
  name                = "appi-${trimprefix(var.aci_name, "ci-")}"
  location            = var.location
  resource_group_name = var.resource_group_name
  application_type    = "web"

  tags = var.tags
}

resource "azurerm_linux_function_app" "scaler" {
  name                        = var.function_app_name
  location                    = var.location
  resource_group_name         = var.resource_group_name
  functions_extension_version = "~4"

  service_plan_id            = azurerm_service_plan.functions.id
  storage_account_name       = azurerm_storage_account.functions.name
  storage_account_access_key = azurerm_storage_account.functions.primary_access_key

  identity {
    type = "SystemAssigned"
  }

  site_config {
    application_insights_connection_string = azurerm_application_insights.scaler.connection_string
    application_insights_key               = azurerm_application_insights.scaler.instrumentation_key

    application_stack {
      python_version = var.function_runtime_version
    }

    ip_restriction_default_action = length(var.github_webhook_ip_ranges) > 0 ? "Deny" : "Allow"

    dynamic "ip_restriction" {
      for_each = var.github_webhook_ip_ranges
      content {
        name       = "github-webhook-${ip_restriction.key}"
        ip_address = ip_restriction.value
        action     = "Allow"
        priority   = 100 + ip_restriction.key
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
    {}
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
  }

  tags = var.tags
}

resource "azurerm_role_assignment" "scaler_contributor" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${var.resource_group_name}"
  role_definition_name = "Contributor"
  principal_id         = azurerm_linux_function_app.scaler.identity[0].principal_id
}

resource "azurerm_role_assignment" "scaler_uai_operator" {
  scope                = azurerm_user_assigned_identity.runner_pull.id
  role_definition_name = "Managed Identity Operator"
  principal_id         = azurerm_linux_function_app.scaler.identity[0].principal_id
}

resource "azurerm_role_assignment" "scaler_keyvault_secrets_user" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_function_app.scaler.identity[0].principal_id
}
