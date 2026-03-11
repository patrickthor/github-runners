# ==============================================================================
# Outputs
# ==============================================================================

output "resource_group_name" {
  description = "The resource group name (created or referenced)"
  value       = local.resource_group_name
}

output "acr_login_server" {
  description = "The login server URL for the Azure Container Registry"
  value       = azurerm_container_registry.acr.login_server
}

output "acr_id" {
  description = "The ID of the Azure Container Registry"
  value       = azurerm_container_registry.acr.id
}

output "key_vault_uri" {
  description = "The URI of the Key Vault"
  value       = azurerm_key_vault.kv.vault_uri
}

output "key_vault_id" {
  description = "The ID of the Key Vault"
  value       = azurerm_key_vault.kv.id
}

output "storage_account_id" {
  description = "The ID of the Terraform-state storage account (managed by bootstrap)"
  value       = data.azurerm_storage_account.state.id
}

output "function_app_name" {
  description = "Event-driven scaler Function App name"
  value       = azurerm_linux_function_app.scaler.name
}

output "function_app_default_hostname" {
  description = "Default hostname of scaler Function App"
  value       = azurerm_linux_function_app.scaler.default_hostname
}

output "servicebus_namespace_name" {
  description = "Service Bus namespace name used for scale events"
  value       = azurerm_servicebus_namespace.scaler.name
}

output "servicebus_queue_name" {
  description = "Service Bus queue name used for scale requests"
  value       = azurerm_servicebus_queue.scale_requests.name
}

output "runner_pull_identity" {
  description = "User-assigned identity used by ACI runners for ACR pull"
  value = {
    id           = azurerm_user_assigned_identity.runner_pull.id
    client_id    = azurerm_user_assigned_identity.runner_pull.client_id
    principal_id = azurerm_user_assigned_identity.runner_pull.principal_id
  }
}

output "scaler_identity_principal_id" {
  description = "System-assigned principal ID for scaler Function App"
  value       = azurerm_linux_function_app.scaler.identity[0].principal_id
}

output "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID used for diagnostics"
  value       = local.log_analytics_workspace_id
}

output "application_insights_connection_string" {
  description = "Application Insights connection string"
  value       = azurerm_application_insights.scaler.connection_string
  sensitive   = true
}
