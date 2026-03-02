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
  description = "The ID of the Storage Account"
  value       = azurerm_storage_account.storage.id
}

output "storage_account_primary_blob_endpoint" {
  description = "The primary blob endpoint of the Storage Account"
  value       = azurerm_storage_account.storage.primary_blob_endpoint
}

output "runner_identities" {
  description = "The principal IDs of the runner managed identities"
  value = {
    for idx, runner in azurerm_container_group.runner : idx => {
      system_assigned_principal_id = runner.identity[0].principal_id
      user_assigned_principal_id   = azurerm_user_assigned_identity.acr_pull[idx].principal_id
    }
  }
}

output "runner_names" {
  description = "The names of the deployed container groups"
  value       = [for runner in azurerm_container_group.runner : runner.name]
}

output "runner_ids" {
  description = "The IDs of the deployed container groups"
  value       = [for runner in azurerm_container_group.runner : runner.id]
}

output "automation_account_name" {
  description = "The name of the Automation Account for cleanup jobs"
  value       = azurerm_automation_account.cleanup.name
}

output "cleanup_runbook_name" {
  description = "The name of the cleanup runbook"
  value       = azurerm_automation_runbook.cleanup_runners.name
}
