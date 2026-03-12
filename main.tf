# ==============================================================================
# Root module — thin wrapper that calls modules/runners
#
# This file is used by the deploy workflow. External consumers should reference
# the module directly:
#   source = "github.com/patrickthor/github-runners//modules/runners?ref=v1.0.0"
# ==============================================================================

module "runners" {
  source = "./modules/runners"

  # Core naming
  workload    = var.workload
  environment = var.environment
  instance    = var.instance
  location    = var.location

  # GitHub
  github_org                             = var.github_org
  github_repo                            = var.github_repo
  github_app_id_secret_name              = var.github_app_id_secret_name
  github_app_installation_id_secret_name = var.github_app_installation_id_secret_name
  github_app_private_key_secret_name     = var.github_app_private_key_secret_name
  webhook_secret_secret_name             = var.webhook_secret_secret_name

  # Resource name overrides (null = auto-generated)
  resource_group_name           = var.resource_group_name
  acr_name                      = var.acr_name
  aci_name                      = var.aci_name
  key_vault_name                = var.key_vault_name
  storage_account_name          = var.storage_account_name
  function_app_name             = var.function_app_name
  function_storage_account_name = var.function_storage_account_name
  servicebus_namespace_name     = var.servicebus_namespace_name

  # Resource group
  create_resource_group = var.create_resource_group

  # Observability
  create_log_analytics_workspace = var.create_log_analytics_workspace
  log_analytics_workspace_id     = var.log_analytics_workspace_id
  log_analytics_workspace_name   = var.log_analytics_workspace_name
  log_analytics_retention_days   = var.log_analytics_retention_days

  # Networking
  subnet_id                    = var.subnet_id
  enable_public_network_access = var.enable_public_network_access

  # Runner config
  cpu                          = var.cpu
  memory                       = var.memory
  runner_min_instances          = var.runner_min_instances
  runner_max_instances          = var.runner_max_instances
  runner_idle_timeout_minutes   = var.runner_idle_timeout_minutes
  runner_labels                 = var.runner_labels
  max_runner_runtime_hours      = var.max_runner_runtime_hours
  runner_completed_ttl_minutes  = var.runner_completed_ttl_minutes
  event_poll_interval_seconds   = var.event_poll_interval_seconds

  # Security
  runner_workload_roles = var.runner_workload_roles
  enable_resource_locks = var.enable_resource_locks

  # Service config
  github_environment           = var.github_environment
  servicebus_queue_name        = var.servicebus_queue_name
  function_runtime_version     = var.function_runtime_version
  acr_sku                      = var.acr_sku
  storage_account_replication_type = var.storage_account_replication_type
  github_webhook_ip_ranges     = var.github_webhook_ip_ranges
  deployment_ip_ranges         = var.deployment_ip_ranges
  tags                         = var.tags
}

# ==============================================================================
# State migration — moved blocks
#
# These map every resource from the old flat root layout to the new module
# structure, preventing Terraform from destroying and recreating resources.
# Safe to remove after all environments have applied once with these blocks.
# ==============================================================================

# Resource group
moved {
  from = azurerm_resource_group.this
  to   = module.runners.azurerm_resource_group.this
}

# Log Analytics
moved {
  from = azurerm_log_analytics_workspace.this
  to   = module.runners.azurerm_log_analytics_workspace.this
}

# Container Registry
moved {
  from = azurerm_container_registry.acr
  to   = module.runners.azurerm_container_registry.acr
}

# Key Vault
moved {
  from = azurerm_key_vault.kv
  to   = module.runners.azurerm_key_vault.kv
}

# Service Bus
moved {
  from = azurerm_servicebus_namespace.scaler
  to   = module.runners.azurerm_servicebus_namespace.scaler
}

moved {
  from = azurerm_servicebus_queue.scale_requests
  to   = module.runners.azurerm_servicebus_queue.scale_requests
}

# Identities
moved {
  from = azurerm_user_assigned_identity.runner_pull
  to   = module.runners.azurerm_user_assigned_identity.runner_pull
}

# Role assignments
moved {
  from = azurerm_role_assignment.runner_acr_pull
  to   = module.runners.azurerm_role_assignment.runner_acr_pull
}

moved {
  from = azurerm_role_assignment.runner_workload
  to   = module.runners.azurerm_role_assignment.runner_workload
}

# Function App storage
moved {
  from = azurerm_storage_account.functions
  to   = module.runners.azurerm_storage_account.functions
}

# Function App
moved {
  from = azurerm_service_plan.functions
  to   = module.runners.azurerm_service_plan.functions
}

moved {
  from = azurerm_application_insights.scaler
  to   = module.runners.azurerm_application_insights.scaler
}

moved {
  from = azurerm_linux_function_app.scaler
  to   = module.runners.azurerm_linux_function_app.scaler
}

# RBAC — Function App
moved {
  from = azurerm_role_assignment.func_storage_blob
  to   = module.runners.azurerm_role_assignment.func_storage_blob
}

moved {
  from = azurerm_role_assignment.func_storage_queue
  to   = module.runners.azurerm_role_assignment.func_storage_queue
}

moved {
  from = azurerm_role_assignment.func_storage_table
  to   = module.runners.azurerm_role_assignment.func_storage_table
}

moved {
  from = azurerm_role_assignment.scaler_servicebus_owner
  to   = module.runners.azurerm_role_assignment.scaler_servicebus_owner
}

moved {
  from = azurerm_role_assignment.scaler_contributor
  to   = module.runners.azurerm_role_assignment.scaler_contributor
}

moved {
  from = azurerm_role_assignment.scaler_uai_operator
  to   = module.runners.azurerm_role_assignment.scaler_uai_operator
}

moved {
  from = azurerm_role_assignment.scaler_keyvault_secrets_user
  to   = module.runners.azurerm_role_assignment.scaler_keyvault_secrets_user
}

# Diagnostic settings
moved {
  from = azurerm_monitor_diagnostic_setting.key_vault
  to   = module.runners.azurerm_monitor_diagnostic_setting.key_vault
}

moved {
  from = azurerm_monitor_diagnostic_setting.servicebus
  to   = module.runners.azurerm_monitor_diagnostic_setting.servicebus
}

moved {
  from = azurerm_monitor_diagnostic_setting.function_app
  to   = module.runners.azurerm_monitor_diagnostic_setting.function_app
}

# Resource locks
moved {
  from = azurerm_management_lock.key_vault
  to   = module.runners.azurerm_management_lock.key_vault
}

moved {
  from = azurerm_management_lock.state_storage
  to   = module.runners.azurerm_management_lock.state_storage
}
