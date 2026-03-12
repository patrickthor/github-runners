provider "azurerm" {
  features {}
  # subscription_id is optional - if not provided via var, it's read from ARM_SUBSCRIPTION_ID env var
  subscription_id = var.subscription_id != "" ? var.subscription_id : null
}

provider "random" {
}
