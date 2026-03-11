output "resource_group_name" {
  description = "Name of the demo resource group"
  value       = azurerm_resource_group.demo.name
}

output "storage_account_name" {
  description = "Name of the demo storage account"
  value       = azurerm_storage_account.demo.name
}

output "subscription_id" {
  description = "Subscription used for demo deployment"
  value       = var.subscription_id
}
