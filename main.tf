# ==============================================================================
# Root module — thin wrapper that calls modules/runners
#
# This file is used by the deploy workflow. External consumers should reference
# the module directly:
#   source = "github.com/patrickthor/github-runners//modules/runners?ref=v3.0.0"
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
  runner_labels                 = var.runner_labels
  max_runner_runtime_hours      = var.max_runner_runtime_hours
  runner_completed_ttl_minutes  = var.runner_completed_ttl_minutes

  # Security
  runner_workload_roles = var.runner_workload_roles
  enable_resource_locks = var.enable_resource_locks

  # Service config
  cleanup_timer_schedule       = var.cleanup_timer_schedule
  servicebus_queue_name        = var.servicebus_queue_name
  function_runtime_version     = var.function_runtime_version
  acr_sku                      = var.acr_sku
  storage_account_replication_type = var.storage_account_replication_type
  github_webhook_ip_ranges     = var.github_webhook_ip_ranges
  deployment_ip_ranges         = var.deployment_ip_ranges
  tags                         = var.tags
}
