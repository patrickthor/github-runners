resource "random_string" "storage_suffix" {
  length  = 8
  upper   = false
  lower   = true
  numeric = true
  special = false
}

resource "azurerm_resource_group" "demo" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_storage_account" "demo" {
  name                     = "${var.storage_account_name_prefix}${random_string.storage_suffix.result}"
  resource_group_name      = azurerm_resource_group.demo.name
  location                 = azurerm_resource_group.demo.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
  tags                     = var.tags
}
