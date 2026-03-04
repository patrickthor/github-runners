terraform {
  required_version = ">= 1.0"

  # Bootstrap deliberately uses local state.
  # It is a tiny, stable, single-purpose module; its own state does not need
  # to be stored remotely.  Never add a backend block here.
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.55"
    }
  }
}

provider "azurerm" {
  features {}
  storage_use_azuread = true
  subscription_id     = var.subscription_id
}
