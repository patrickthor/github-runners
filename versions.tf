terraform {
  required_version = ">= 1.3"

  # Partial backend — supply the remaining values with:
  #   terraform init -backend-config=backend.hcl
  # See backend.hcl.example for the required keys.
  backend "azurerm" {}

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.55"
    }

  }
}
