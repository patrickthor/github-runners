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
  description = "The ID of the primary Storage Account"
  value       = azurerm_storage_account.storage.id
}

output "function_storage_account_id" {
  description = "The ID of the Function App storage account"
  value       = azurerm_storage_account.functions.id
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
  description = "Shared user-assigned identity used by dynamically created ACI runners for ACR pull"
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
