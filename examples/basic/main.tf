# ==============================================================================
# Basic example — minimal module usage for consuming projects
#
# All values are driven by variables (set via GitHub repo variables + the
# workflow's "Generate terraform.tfvars" step). Edit defaults in variables.tf
# or override via tfvars.
# ==============================================================================

module "runners" {
  source = "github.com/patrickthor/github-runners//modules/runners?ref=v2.0.0"

  # Core naming — generates all resource names automatically
  workload    = var.workload
  environment = var.environment
  instance    = var.instance
  location    = var.location

  # GitHub configuration
  github_org  = var.github_org
  github_repo = var.github_repo

  # Key Vault secret names
  github_app_id_secret_name              = var.github_app_id_secret_name
  github_app_installation_id_secret_name = var.github_app_installation_id_secret_name
  github_app_private_key_secret_name     = var.github_app_private_key_secret_name

  # Runner identity roles (empty = least privilege)
  runner_workload_roles = var.runner_workload_roles
}

# ==============================================================================
# Outputs — useful for webhook setup and debugging
# ==============================================================================

output "function_app_name" {
  description = "Function App name (needed by the deploy workflow)"
  value       = module.runners.function_app_name
}

output "function_app_hostname" {
  description = "Use this hostname to configure the GitHub webhook"
  value       = module.runners.function_app_default_hostname
}

output "resource_group_name" {
  value = module.runners.resource_group_name
}

output "acr_login_server" {
  description = "Push your runner image here"
  value       = module.runners.acr_login_server
}

output "key_vault_uri" {
  description = "Store GitHub App secrets here"
  value       = module.runners.key_vault_uri
}
