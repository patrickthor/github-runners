# Event-Driven Ephemeral Runners on Azure

Terraform module for an event-driven autoscaling runner platform on Azure.

## Architecture

This module provisions:

- Azure Container Registry (runner image source)
- Shared user-assigned identity for dynamic runner pulls from ACR
- Service Bus namespace + queue for scale requests
- Azure Function App (scaler/controller) that consumes queue messages and manages runner lifecycle
- Supporting storage, Key Vault, and RBAC

The Function App is the control plane. It receives job events (direct webhook ingestion or queue push), decides desired capacity, and creates/deletes ephemeral ACI runners on demand.

## What changed

This module is now **event-driven only**:

- No statically declared `azurerm_container_group.runner` fleet in Terraform
- No Azure Automation runbook cleanup path
- Runner lifecycle is delegated to the scaler Function App

## Authentication

Runner containers use only one auth model:

- on-demand registration tokens minted by GitHub App credentials

For control-plane self-refresh, configure GitHub App auth:

- `github_app_id_secret_name` + `github_app_installation_id_secret_name` + `github_app_private_key_secret_name`

The scaler requests a fresh registration token from GitHub automatically before creating runners.

### Key Vault wiring (recommended)

This module uses Key Vault references in Function App settings for sensitive auth values.

Provide existing secret names:

- `github_app_id_secret_name`
- `github_app_installation_id_secret_name`
- `github_app_private_key_secret_name`
- `webhook_secret_secret_name` (optional)

Key Vault reference URIs are built automatically from your module Key Vault (`key_vault_name`) and these secret names.

Default secret names used by this setup:

- `runnerpocbouvet-github-app-id` (GitHub App ID)
- `runnerpocbouvet-github-app-installation-id` (GitHub App Installation ID)
- `runnerpocbouvet-github-app-private-key` (GitHub App private key)
- `runnerpocbouvet-webhook-secret` (optional webhook secret)

The Function App is granted `Key Vault Secrets User` role on the module Key Vault.

## Required variables

- `resource_group_name`
- `location`
- `acr_name`
- `aci_name`
- `key_vault_name`
- `storage_account_name`
- `function_storage_account_name`
- `function_app_name`
- `servicebus_namespace_name`
- `github_org`
- `github_repo`
- `github_app_id_secret_name`
- `github_app_installation_id_secret_name`
- `github_app_private_key_secret_name`
- `webhook_secret_secret_name` (optional)

Sensitive values are expected from Key Vault secret names.

## Core autoscaling variables

- `runner_min_instances`
- `runner_max_instances`
- `runner_idle_timeout_minutes`
- `cpu`
- `memory`
- `runner_labels`

Default behavior uses `runner_min_instances = 0` so a single queued event scales to a single new runner.

## Quick start

### 1) Configure auth

Recommended (self-refresh):

```bash
export TF_VAR_github_app_id_secret_name="runnerpocbouvet-github-app-id"
export TF_VAR_github_app_installation_id_secret_name="runnerpocbouvet-github-app-installation-id"
export TF_VAR_github_app_private_key_secret_name="runnerpocbouvet-github-app-private-key"
export TF_VAR_webhook_secret_secret_name="runnerpocbouvet-webhook-secret" # optional
```

Grant yourself permission to add secrets to Key Vault (required once):

```bash
az role assignment create \
	--assignee $(az ad signed-in-user show --query id -o tsv) \
	--role "Key Vault Secrets Officer" \
	--scope $(az keyvault show --name <key_vault_name> --query id -o tsv)
```

If your tenant does not allow `signed-in-user`, use your user object id directly in `--assignee`.

Create those secrets manually in Key Vault (example):

```bash
az keyvault secret set --vault-name <key_vault_name> --name runnerpocbouvet-github-app-id --value "<github_app_id>"
az keyvault secret set --vault-name <key_vault_name> --name runnerpocbouvet-github-app-installation-id --value "<github_app_installation_id>"
az keyvault secret set --vault-name <key_vault_name> --name runnerpocbouvet-github-app-private-key --file <path/to/github-app-private-key.pem>
az keyvault secret set --vault-name <key_vault_name> --name runnerpocbouvet-webhook-secret --value "<webhook_secret>" # optional
```

#### Create the GitHub App

If you do not see where to create one, use these direct links:

- Personal account app page: `https://github.com/settings/apps/new`
- Organization app page: `https://github.com/organizations/<org>/settings/apps/new`

UI path:

- Profile photo -> `Settings` -> `Developer settings` -> `GitHub Apps` -> `New GitHub App`

Recommended form values:

- **GitHub App name**: `azure-ephemeral-runner-scaler` (or similar)
- **Homepage URL**: your repo URL
- **Webhook**:
	- disable if this app is only used for token minting
	- enable only if you plan to consume GitHub App webhooks separately

Minimum permissions for this runner scaler:

- Repository permissions:
	- `Administration: Read and write` (required to mint runner registration tokens)
	- `Actions: Read` (recommended)

Installation scope best practice:

- Install only on the repositories that need ephemeral runners (least privilege)

After creating and installing the app, collect:

- `App ID`
- `Installation ID`
- generated private key PEM file

Quick ways to find `Installation ID`:

- From app install URL in GitHub UI
- CLI: `gh api /repos/<org>/<repo>/installation --jq .id`

If the create page is missing in an organization, an org owner (or delegated app manager) must create/install the app and share those values.

Quick verification before Terraform apply:

```bash
gh api /repos/<org>/<repo>/installation --jq .id
```

If this returns an installation id, the app is installed correctly on that repo.

### 2) Configure terraform.tfvars

Example:

```hcl
resource_group_name           = "rg-github-runners"
location                      = "westeurope"
acr_name                      = "runneracr001"
aci_name                      = "runner"
key_vault_name                = "kv-runner-001"
storage_account_name          = "strunnerstate001"
function_storage_account_name = "strunnerscaler001"
function_app_name             = "runner-scaler-func-001"
servicebus_namespace_name     = "runner-scale-bus-001"

github_org  = "your-org"
github_repo = "your-org/your-repo"

runner_min_instances        = 0
runner_max_instances        = 20
runner_idle_timeout_minutes = 15
```

### 3) Deploy

```bash
terraform init
terraform plan
terraform apply
```

## Runner token rotation

Registration token minting is automatic in the scaler via GitHub App credentials.

## Runner image import on apply

This module always imports the runner image into ACR during `terraform apply`.

- source image is fixed to `ghcr.io/myoung34/docker-github-actions-runner:latest`
- target image/tag is fixed to `actions-runner:latest`

The scaler always uses `${acr_login_server}/actions-runner:latest`.

Note: this uses local Azure CLI from the machine running Terraform (`az acr import ...`).

## Post-deploy integration

You must deploy scaler function code that:

- accepts webhook/job events and enqueues scale requests
- processes queue messages
- creates/deletes ACI runner instances using ARM
- enforces min/max/idle policies

This module provisions the infrastructure and RBAC for that flow.

The repository now includes a starter scaffold under:

- `scaler-function/function_app.py`
- `scaler-function/host.json`
- `scaler-function/requirements.txt`
- `scaler-function/local.settings.example.json`

Use that scaffold as the deployment package for `azurerm_linux_function_app.scaler`.

## Outputs

- `function_app_name`
- `function_app_default_hostname`
- `servicebus_namespace_name`
- `servicebus_queue_name`
- `runner_pull_identity`
- `acr_login_server`

## Notes

- Existing pipelines that expected static `runner_names` outputs must be updated.
- Legacy cleanup/runbook resources were intentionally removed in favor of event-driven control.
