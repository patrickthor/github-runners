# Event-Driven Ephemeral GitHub Runners on Azure

Terraform module that provisions a fully event-driven, autoscaling GitHub Actions runner platform on Azure. A Function App ingests GitHub webhook events, queues scale requests, and dynamically creates or destroys ephemeral Azure Container Instance (ACI) runners on demand.

## Architecture

```
GitHub Webhook
     │
     ▼
Azure Function App (github_webhook)
     │  enqueues scale request
     ▼
Service Bus Queue
     │
     ▼
Azure Function App (scale_worker)
     │  create / delete ACI runners
     ▼
Azure Container Instances  ──►  ACR (actions-runner image)
     │
     ▼
Azure Function App (cleanup_timer)  [runs every 3 min]
     │  removes stale / completed runners
```

---

# For module consumers

Everything you need to use this module in your own project.

## Usage

```hcl
module "runners" {
  source = "github.com/patrickthor/github-runners//modules/runners?ref=v3.0.0"

  workload    = "runner"
  environment = "prod"
  instance    = "001"
  location    = "westeurope"

  github_org  = "your-org"
  github_repo = "your-org/your-repo"

  github_app_id_secret_name              = "github-app-id"
  github_app_installation_id_secret_name = "github-app-installation-id"
  github_app_private_key_secret_name     = "github-app-private-key"
}
```

## Getting started

1. Install [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5 and [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)
2. Create a GitHub App — see [Create a GitHub App](#1-create-a-github-app) below
3. Create the Azure service principal with OIDC trust — see [Provision Azure identity](#2-provision-azure-identity-and-permissions) below
4. Copy the four files from [`examples/basic`](examples/basic/README.md) into your repo (`main.tf`, `variables.tf`, `versions.tf` at root + the workflow into `.github/workflows/`), then configure GitHub secrets and variables. The [setup guide](examples/basic/README.md) walks through every step. State storage is created automatically on first run.
5. After the first deploy, [store GitHub App secrets in Key Vault](#6-store-github-app-secrets-in-key-vault)
6. [Register the webhook in GitHub](#7-register-the-webhook-in-github)

The example workflow handles Terraform apply, ACR image import, and scaler function deployment in a single pipeline. You don't need to copy the Python code into your project.

> The Terraform module provisions all infrastructure. The scaler Function App code (`scaler-function/`) is deployed automatically by the example workflow — see [Deploying the scaler function](#deploying-the-scaler-function) for manual options.

## Variables reference

### Required

| Variable | Description |
|---|---|
| `workload` | Short workload identifier (e.g. `runner`) — used to generate all resource names |
| `environment` | Environment identifier (e.g. `poc`, `dev`, `prod`) |
| `instance` | Instance identifier for uniqueness (e.g. `bvt`, `001`) |
| `location` | Azure region (e.g. `westeurope`) |
| `github_org` | GitHub organisation name |
| `github_repo` | Repository in `org/repo` format |
| `github_app_id_secret_name` | Key Vault secret name for GitHub App ID |
| `github_app_installation_id_secret_name` | Key Vault secret name for installation ID |
| `github_app_private_key_secret_name` | Key Vault secret name for private key PEM |

> `subscription_id` is not a module variable — set it on the `azurerm` provider block instead. The module reads it from `data.azurerm_client_config.current`.

### Resource name overrides

All resource names are auto-generated from `workload`/`environment`/`instance` using Azure CAF conventions. Override any name by setting the corresponding variable:

| Variable | Default pattern | Example (`runner`/`poc`/`bvt`) |
|---|---|---|
| `resource_group_name` | `rg-{w}-{e}-{i}` | `rg-runner-poc-bvt` |
| `acr_name` | `cr{w}{e}{i}` | `crrunnerpocbvt` |
| `aci_name` | `ci-{w}-{e}-{i}` | `ci-runner-poc-bvt` |
| `key_vault_name` | `kv-{w}-{e}-{i}` | `kv-runner-poc-bvt` |
| `storage_account_name` | `st{w}{e}{i}` | `strunnerpocbvt` |
| `function_app_name` | `func-{w}-{e}-{i}` | `func-runner-poc-bvt` |
| `function_storage_account_name` | `stfn{w}{e}{i}` | `stfnrunnerpocbvt` |
| `servicebus_namespace_name` | `sbns-{w}-{e}-{i}` | `sbns-runner-poc-bvt` |

### Optional

| Variable | Default | Description |
|---|---|---|
| `create_resource_group` | `true` | Whether the module creates the resource group |
| `create_log_analytics_workspace` | `true` | Create a new Log Analytics workspace (set false + provide ID to use existing) |
| `log_analytics_workspace_id` | `null` | Existing Log Analytics workspace ID |
| `log_analytics_workspace_name` | `null` | Name for created workspace (auto-derived if omitted) |
| `log_analytics_retention_days` | `30` | Log Analytics retention (30–730 days) |
| `subnet_id` | `null` | Subnet ID for VNet integration |
| `enable_public_network_access` | `true` | Set to `false` for private endpoint environments |
| `webhook_secret_secret_name` | `null` | Key Vault secret name for webhook HMAC validation |
| `runner_min_instances` | `0` | Minimum live runners |
| `runner_max_instances` | `5` | Maximum live runners |
| `runner_completed_ttl_minutes` | `5` | Minutes to retain a completed runner before deletion |
| `max_runner_runtime_hours` | `2` | Hard cap on runner lifetime |
| `cpu` | `2` | CPU cores per runner |
| `memory` | `4` | Memory (GB) per runner |
| `runner_labels` | `azure,container-instance,self-hosted` | Comma-separated runner labels |
| `cleanup_timer_schedule` | `0 */3 * * * *` | NCRONTAB schedule for the cleanup timer function |
| `runner_workload_roles` | `[]` | Azure roles granted to runner identity at subscription scope |
| `enable_resource_locks` | `false` | CanNotDelete locks on Key Vault and state storage |
| `acr_sku` | `Basic` | Container Registry SKU |
| `storage_account_replication_type` | `LRS` | State storage replication |
| `github_webhook_ip_ranges` | GitHub webhook CIDRs | GitHub webhook CIDR ranges for IP restriction |
| `deployment_ip_ranges` | `[]` | Additional CIDRs to allow (e.g. static deploy IPs) |
| `tags` | `{ManagedBy, Purpose}` | Common resource tags |

## Outputs

| Output | Description |
|---|---|
| `resource_group_name` | Resource group name |
| `function_app_name` | Function App name |
| `function_app_default_hostname` | Function App hostname (use for webhook URL) |
| `acr_login_server` | ACR login server URL |
| `acr_id` | ACR resource ID |
| `key_vault_uri` | Key Vault URI |
| `key_vault_id` | Key Vault resource ID |
| `servicebus_namespace_name` | Service Bus namespace name |
| `servicebus_queue_name` | Service Bus queue name |
| `runner_pull_identity` | User-assigned identity (id, client_id, principal_id) for ACR pull |
| `scaler_identity_principal_id` | System-assigned principal ID for scaler Function App |
| `log_analytics_workspace_id` | Log Analytics workspace ID used for diagnostics |
| `application_insights_connection_string` | Application Insights connection string (sensitive) |

## Deploying the scaler function

The Terraform module provisions all Azure infrastructure, but the Python Function App code (`scaler-function/`) must be deployed separately. This is a one-time step after `terraform apply`, plus whenever the scaler code changes.

The easiest approach is to copy the example workflow from [`examples/basic/.github/workflows/deploy-runners.yml`](examples/basic/.github/workflows/deploy-runners.yml) into your repo. It handles everything: Terraform apply, ACR image import, and scaler function deployment. The workflow fetches the scaler function code from this repo at the pinned version tag, so you don't need to copy the Python code into your project.

Alternatively, deploy manually:

```bash
# 1. Import the runner image into your ACR
ACR_NAME=$(terraform output -raw acr_login_server | cut -d. -f1)
az acr import --name "$ACR_NAME" \
  --source ghcr.io/myoung34/docker-github-actions-runner:latest \
  --image actions-runner:latest --force

# 2. Deploy the scaler function
FUNC_APP=$(terraform output -raw function_app_name)
RG=$(terraform output -raw resource_group_name)

cd scaler-function
pip install --target=".python_packages/lib/site-packages" -r requirements.txt
zip -r ../deploy.zip . -x "local.settings*.json" -x "__pycache__/*" -x "*.pyc" -x "DEPLOYMENT.md"
cd ..

az functionapp deployment source config-zip \
  --resource-group "$RG" --name "$FUNC_APP" --src deploy.zip --timeout 300
```

> If the Function App has IP restrictions enabled (default), you may need to temporarily whitelist your IP. See the deploy workflow for an example of how to do this automatically.

## Provisioned resources

| Resource | Name pattern | Example (`poc` / `bvt`) | Purpose |
|---|---|---|---|
| Resource group | `rg-{workload}-{env}-{instance}` | `rg-runner-poc-bvt` | Container for all resources |
| Container Registry | `cr{workload}{env}{instance}` | `crrunnerpocbvt` | Runner image store |
| Key Vault | `kv-{workload}-{env}-{instance}` | `kv-runner-poc-bvt` | GitHub App credentials |
| Service Bus namespace | `sbns-{workload}-{env}-{instance}` | `sbns-runner-poc-bvt` | Scale request queue |
| Function App | `func-{workload}-{env}-{instance}` | `func-runner-poc-bvt` | Control plane |
| Function storage | `stfn{workload}{env}{instance}` | `stfnrunnerpocbvt` | Functions runtime storage |
| App Service plan | `asp-{workload}-{env}-{instance}` | `asp-runner-poc-bvt` | Flex Consumption FC1 (Linux) |
| Application Insights | `appi-{workload}-{env}-{instance}` | `appi-runner-poc-bvt` | Telemetry |
| Log Analytics | `log-{workload}-{env}-{instance}` | `log-runner-poc-bvt` | Diagnostics & log retention |
| Managed identity | `id-{workload}-{env}-{instance}` | `id-runner-poc-bvt` | ACI → ACR pull |

---

# For module developers

Everything below is for developing, operating, and maintaining this repository.

## Project structure

```
├── modules/runners/     # Reusable Terraform module (all resources)
├── scaler-function/     # Python Function App code (deployed separately)
├── bootstrap/           # One-time state storage provisioning (this repo only)
├── examples/basic/      # Minimal module usage example for consumers (includes CI/CD workflow)
├── examples/demo/       # Demo workflow using self-hosted runners
├── main.tf              # Root wrapper used by this repo's CI/CD
├── variables.tf         # Root variables (passed through to module)
├── outputs.tf           # Root outputs (passed through from module)
└── .github/workflows/   # CI/CD pipelines (this repo only)
```

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) (logged in: `az login`)
- A GitHub App with `Administration: Read and write` + `Actions: Read` repository permissions

## Fresh deployment — step by step

### 1. Create a GitHub App

If you don't already have one:

- Personal: `https://github.com/settings/apps/new`
- Organisation: `https://github.com/organizations/<org>/settings/apps/new`

**Naming convention**: `ghapp-{workload}-{env}-{instance}` → e.g. `ghapp-runner-poc-bvt`

Minimum permissions:
- `Repository → Administration: Read and write` (required — mints runner registration tokens)
- `Repository → Actions: Read` (recommended)

Disable the webhook on the App unless you have a separate use for it — this module receives webhooks directly on the Function App.

Install the app on the target repository. After creation collect:
- **App ID** (shown on the app settings page)
- **Installation ID**: `gh api /repos/<org>/<repo>/installation --jq .id`
- **Private key PEM** (generate from the app settings page)

---

### 2. Provision Azure identity and permissions

This is a **one-time** setup that creates the service principal used by GitHub Actions, assigns it the roles Terraform needs, and establishes the OIDC trust with your repository.

```bash
# Edit these four values
RG=rg-runner-poc-bvt
LOCATION=westeurope
APP_NAME=sp-runner-poc-bvt
GITHUB_ORG=your-org
GITHUB_REPO=your-repo   # just the repo name, not org/repo

SUBSCRIPTION_ID=$(az account show --query id -o tsv)

# 1. Create the resource group (also done idempotently by the Bootstrap workflow)
az group create --name $RG --location $LOCATION

# 2. Create the App Registration and its service principal
CLIENT_ID=$(az ad app create --display-name $APP_NAME --query appId -o tsv)
az ad sp create --id $CLIENT_ID

# 3. Add OIDC federated credential so GitHub Actions can authenticate without secrets
az ad app federated-credential create --id $CLIENT_ID --parameters "{
  \"name\": \"github-actions-main\",
  \"issuer\": \"https://token.actions.githubusercontent.com\",
  \"subject\": \"repo:$GITHUB_ORG/$GITHUB_REPO:ref:refs/heads/main\",
  \"audiences\": [\"api://AzureADTokenExchange\"]
}"

# 4. Assign roles — all three at subscription scope
PRINCIPAL_ID=$(az ad sp show --id $CLIENT_ID --query id -o tsv)
SUB_SCOPE=/subscriptions/$SUBSCRIPTION_ID

# Contributor — creates/modifies all module resources
az role assignment create \
  --assignee-object-id $PRINCIPAL_ID --assignee-principal-type ServicePrincipal \
  --role Contributor --scope $SUB_SCOPE

# User Access Administrator — required to create intra-RG role assignments inside the module
# (AcrPull, Managed Identity Operator, Key Vault Secrets User)
az role assignment create \
  --assignee-object-id $PRINCIPAL_ID --assignee-principal-type ServicePrincipal \
  --role "User Access Administrator" --scope $SUB_SCOPE

# Role Based Access Control Administrator — required to create the runner_pull workload role
# assignment at subscription scope (runner_workload_roles variable)
az role assignment create \
  --assignee-object-id $PRINCIPAL_ID --assignee-principal-type ServicePrincipal \
  --role "Role Based Access Control Administrator" --scope $SUB_SCOPE

# 5. Print values to paste into GitHub secrets
echo ""
echo "--- GitHub Secrets ---"
echo "AZURE_CLIENT_ID:       $CLIENT_ID"
echo "AZURE_TENANT_ID:       $(az account show --query tenantId -o tsv)"
echo "AZURE_SUBSCRIPTION_ID: $SUBSCRIPTION_ID"
```

> `Storage Blob Data Contributor` on the state storage account is granted automatically by the Bootstrap workflow after it creates the storage account.

---

### 3. Configure GitHub Actions variables and secrets

**Do this before running any workflow** — Bootstrap needs the secrets to authenticate to Azure.

In your repository go to **Settings → Secrets and variables → Actions**.

**Secrets** (sensitive) — add under *Repository secrets*:

| Secret | Value |
|---|---|
| `AZURE_CLIENT_ID` | App Registration client ID (printed at end of step 2) |
| `AZURE_TENANT_ID` | Azure AD tenant ID (printed at end of step 2) |
| `AZURE_SUBSCRIPTION_ID` | Target subscription ID (printed at end of step 2) |

**Variables** (non-sensitive) — add under *Repository variables*:

| Variable | Example value |
|---|---|
| `WORKLOAD` | `runner` |
| `ENVIRONMENT` | `poc` |
| `INSTANCE` | `bvt` |
| `AZURE_LOCATION` | `westeurope` |
| `GH_ORG` | `your-org` |
| `GH_REPO` | `your-org/your-repo` |
| `STATE_STORAGE_ACCOUNT_NAME` | *(optional — auto-derived as `st{workload}{environment}{instance}`)* |
| `STATE_CONTAINER_NAME` | `tfstate` |
| `RUNNER_WORKLOAD_ROLES` | *(empty — explicitly grant what runners need, comma-separated)* |
| `CREATE_RESOURCE_GROUP` | `true` *(set to `false` if RG already exists)* |
| `ENABLE_RESOURCE_LOCKS` | `false` *(set to `true` in production)* |

---

### 4. Bootstrap — provision remote state storage

The bootstrap module creates the Storage Account and blob container that holds Terraform remote state. It uses **local state** by design and only needs to run once per environment.

**Requires Step 3 secrets to be configured first.**

Trigger via GitHub Actions: **Actions → Bootstrap → Run workflow** (leave *skip_create* unchecked for a first run).

The workflow will:
- Run `terraform apply` in `bootstrap/` to provision the storage account and blob container
- Grant the CI identity `Storage Blob Data Contributor` on the state storage
- Print the backend config snippet in the job summary

If the storage account already exists from a previous run, check *skip_create* — the workflow will adopt it without recreating it.

> Paste the values printed at the end of step 2 as the three secrets.

---

### 5. Deploy infrastructure + code (push to `main`)

Push any commit to `main` — the **Deploy** workflow runs automatically:

- **Stage 2 — Infrastructure**: generates `backend.hcl` and `terraform.tfvars` from your GitHub variables, runs `terraform init`, `validate`, `plan`, and `apply`.
- **Stage 3 — Function App code**: packages `scaler-function/` as a zip and deploys via `az functionapp deployment source config-zip --build-remote true` (Microsoft's recommended method for Python Flex Consumption).

> **IP restrictions and deployment**: The Function App restricts inbound traffic to GitHub webhook IP ranges by default. The deploy workflow automatically whitelists the GitHub Actions runner's public IP before deploying and removes it afterwards. If you deploy manually (e.g. from a local machine), the deploying machine's IP must be allowed through the Function App's IP restrictions — either temporarily via `az functionapp config access-restriction add` or permanently via the `deployment_ip_ranges` Terraform variable.

---

### 6. Store GitHub App secrets in Key Vault

```bash
KV=<key-vault-name>   # your Key Vault name

# Grant yourself write access (once)
az role assignment create \
  --assignee $(az ad signed-in-user show --query id -o tsv) \
  --role "Key Vault Secrets Officer" \
  --scope $(az keyvault show --name $KV --query id -o tsv)

# Store secrets — names must match the terraform.tfvars values
# (default: github-app-id, github-app-installation-id, github-app-private-key)
az keyvault secret set --vault-name $KV \
  --name github-app-id --value "<APP_ID>"

az keyvault secret set --vault-name $KV \
  --name github-app-installation-id --value "<INSTALLATION_ID>"

az keyvault secret set --vault-name $KV \
  --name github-app-private-key --file <path/to/private-key.pem>

# Optional — webhook signature validation
az keyvault secret set --vault-name $KV \
  --name github-webhook-secret --value "<WEBHOOK_SECRET>"
```

Default secret names expected by this module:

| Variable | Example value |
|---|---|
| `github_app_id_secret_name` | `github-app-id` |
| `github_app_installation_id_secret_name` | `github-app-installation-id` |
| `github_app_private_key_secret_name` | `github-app-private-key` |
| `webhook_secret_secret_name` | *(optional, set to `null` to disable)* |

These are required variables with no defaults — you must explicitly set them in your `terraform.tfvars`.

The Function App is granted `Key Vault Secrets User` automatically by this module.

---

### 7. Register the webhook in GitHub

From the Terraform output:

```bash
terraform output function_app_default_hostname
```

In your GitHub repository: **Settings → Webhooks → Add webhook**

- **Payload URL**: `https://<hostname>/api/webhook/github?code=<function_key>`
- **Content type**: `application/json`
- **Events**: `Workflow jobs`

Retrieve the function key:

```bash
az functionapp function keys list \
  --resource-group rg-runner-poc-bvt \
  --name func-runner-poc-bvt \
  --function-name github_webhook \
  --query default -o tsv
```

---

## GitHub Actions workflows

| Workflow | Trigger | Stages |
|---|---|---|
| `bootstrap.yml` | Manual (`workflow_dispatch`) | Stage 1 — provision Terraform state storage |
| `deploy.yml` | Push to `main` or manual | Stage 2 — Terraform infra; Stage 3 — Function App code |
| `release.yml` | Push to `main` | Semantic versioning + GitHub Release |

**Migrating an existing environment** (state is currently local): remove the old storage account resource from state before the first CI run, then push to main:

```bash
terraform state rm azurerm_storage_account.storage
git push
```

---

## Runner image

On every `terraform apply` in this repo, the deploy workflow imports the public runner image into ACR:

- **Source**: `ghcr.io/myoung34/docker-github-actions-runner:latest`
- **Target**: `<acr_login_server>/actions-runner:latest`

The Function App always uses the ACR-hosted image. To use a custom image, push it to ACR as `actions-runner:latest` before runners are needed.

---

## Scaler function internals

The control plane (`scaler-function/function_app.py`) has three functions:

| Function | Trigger | Role |
|---|---|---|
| `github_webhook` | HTTP | Validates signature, filters to `self-hosted` jobs, enqueues scale request |
| `scale_worker` | Service Bus | Deduplicates runners per job, computes desired count, creates/deletes ACI |
| `cleanup_timer` | Timer (configurable, default 3 min) | Removes completed, stale, or over-TTL runners |

Key behaviours:
- `maxConcurrentCalls: 1` on the Service Bus trigger prevents duplicate scale operations
- At-capacity handling: checks GitHub API if the job is still queued, sleeps 100s between retries (giving ~50 min retry window across 30 attempts), and creates the runner immediately if a slot frees up during the wait
- Non-terminal runner deduplication — terminated containers are not counted as active
- HTTP session pooling for ARM and GitHub API calls
- ACI quota retry — 3 attempts with 35s backoff on `ContainerGroupQuotaReached`
- Permanent config errors (missing env vars) are consumed silently to avoid DLQ spam
