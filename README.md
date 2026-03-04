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
Azure Function App (cleanup_timer)  [runs every 5 min]
     │  removes stale / completed runners
```

**Provisioned resources**

| Resource | Name pattern | Example (`poc` / `bvt`) | Purpose |
|---|---|---|---|
| Resource group | `rg-{workload}-{env}-{instance}` | `rg-runner-poc-bvt` | Container for all resources |
| Container Registry | `cr{workload}{env}{instance}` | `crrunnerpocbvt` | Runner image store |
| Key Vault | `kv-{workload}-{env}-{instance}` | `kv-runner-poc-bvt` | GitHub App credentials |
| Service Bus namespace | `sbns-{workload}-{env}-{instance}` | `sbns-runner-poc-bvt` | Scale request queue |
| Function App | `func-{workload}-{env}-{instance}` | `func-runner-poc-bvt` | Control plane |
| Function storage | `stfn{workload}{env}{instance}` | `stfnrunnerpocbvt` | Functions runtime storage |
| App Service plan | `asp-{workload}-{env}-{instance}` | `asp-runner-poc-bvt` | Consumption Y1 (Linux) |
| Application Insights | `appi-{workload}-{env}-{instance}` | `appi-runner-poc-bvt` | Telemetry |
| Managed identity | `id-{workload}-{env}-{instance}` | `id-runner-poc-bvt` | ACI → ACR pull |
| State storage | `st{workload}{env}{instance}` (bootstrap) | `strunnerpocbvt` | Terraform remote state |
| GitHub App | `ghapp-{workload}-{env}-{instance}` | `ghapp-runner-poc-bvt` | Issues runner tokens |
| Azure service principal | `sp-{workload}-{env}-{instance}` | `sp-runner-poc-bvt` | CI/CD identity (OIDC) |

---

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.0
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) (logged in: `az login`)
- [Azure Functions Core Tools v4](https://learn.microsoft.com/en-us/azure/azure-functions/functions-run-local) (`npm i -g azure-functions-core-tools@4`)
- A GitHub App with `Administration: Read and write` + `Actions: Read` repository permissions


---

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

# 4. Assign roles on the resource group
PRINCIPAL_ID=$(az ad sp show --id $CLIENT_ID --query id -o tsv)
SCOPE=/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG

# Contributor — creates/modifies all module resources
az role assignment create \
  --assignee-object-id $PRINCIPAL_ID --assignee-principal-type ServicePrincipal \
  --role Contributor --scope $SCOPE

# User Access Administrator — required to create the role assignments inside the module
# (AcrPull, Contributor on RG, Managed Identity Operator, Key Vault Secrets User)
az role assignment create \
  --assignee-object-id $PRINCIPAL_ID --assignee-principal-type ServicePrincipal \
  --role "User Access Administrator" --scope $SCOPE

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
| `AZURE_RESOURCE_GROUP` | `rg-runner-poc-bvt` |
| `AZURE_LOCATION` | `westeurope` |
| `ACR_NAME` | `crrunnerpocbvt` |
| `ACI_NAME` | `ci-runner-poc-bvt` |
| `KEY_VAULT_NAME` | `kv-runner-poc-bvt` |
| `STATE_STORAGE_ACCOUNT_NAME` | `strunnerpocbvt` |
| `STATE_CONTAINER_NAME` | `tfstate` |
| `FUNCTION_STORAGE_ACCOUNT_NAME` | `stfnrunnerpocbvt` |
| `FUNCTION_APP_NAME` | `func-runner-poc-bvt` |
| `SERVICEBUS_NAMESPACE_NAME` | `sbns-runner-poc-bvt` |
| `GITHUB_ORG` | `your-org` |
| `GITHUB_REPO` | `your-org/your-repo` |

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

- **Stage 2 — Infrastructure**: generates `backend.hcl` and `terraform.tfvars` from your GitHub variables, runs `terraform init`, `plan`, and `apply`.
- **Stage 3 — Function App code**: publishes `scaler-function/` via `func azure functionapp publish --python --build remote`.

---

### 6. Store GitHub App secrets in Key Vault

```bash
KV=<key-vault-name>   # your Key Vault name

# Grant yourself write access (once)
az role assignment create \
  --assignee $(az ad signed-in-user show --query id -o tsv) \
  --role "Key Vault Secrets Officer" \
  --scope $(az keyvault show --name $KV --query id -o tsv)

# Store secrets
az keyvault secret set --vault-name $KV \
  --name runnerpocbouvet-github-app-id --value "<APP_ID>"

az keyvault secret set --vault-name $KV \
  --name runnerpocbouvet-github-app-installation-id --value "<INSTALLATION_ID>"

az keyvault secret set --vault-name $KV \
  --name runnerpocbouvet-github-app-private-key --file <path/to/private-key.pem>

# Optional — webhook signature validation
az keyvault secret set --vault-name $KV \
  --name runnerpocbouvet-webhook-secret --value "<WEBHOOK_SECRET>"
```

Default secret names expected by this module:

| Variable | Default secret name |
|---|---|
| `github_app_id_secret_name` | `runnerpocbouvet-github-app-id` |
| `github_app_installation_id_secret_name` | `runnerpocbouvet-github-app-installation-id` |
| `github_app_private_key_secret_name` | `runnerpocbouvet-github-app-private-key` |
| `webhook_secret_secret_name` | *(optional, set to `null` to disable)* |

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

## Variables reference

### Required

| Variable | Description |
|---|---|
| `resource_group_name` | Azure resource group |
| `location` | Azure region (e.g. `westeurope`) |
| `subscription_id` | Azure subscription ID |
| `acr_name` | Container Registry name — alphanumeric only, globally unique |
| `aci_name` | ACI runner name prefix; seeds `id-`, `asp-`, `appi-` names |
| `key_vault_name` | Key Vault name — globally unique |
| `storage_account_name` | State storage account name (provisioned by bootstrap) |
| `function_storage_account_name` | Function App runtime storage — alphanumeric only, globally unique |
| `function_app_name` | Function App name — globally unique |
| `servicebus_namespace_name` | Service Bus namespace name — globally unique |
| `github_org` | GitHub organisation name |
| `github_repo` | Repository in `org/repo` format |
| `github_app_id_secret_name` | Key Vault secret name for GitHub App ID |
| `github_app_installation_id_secret_name` | Key Vault secret name for installation ID |
| `github_app_private_key_secret_name` | Key Vault secret name for private key PEM |

### Optional

| Variable | Default | Description |
|---|---|---|
| `webhook_secret_secret_name` | `null` | Key Vault secret name for webhook HMAC validation |
| `runner_min_instances` | `0` | Minimum live runners |
| `runner_max_instances` | `10` | Maximum live runners |
| `runner_idle_timeout_minutes` | `15` | Minutes before idle runner is terminated |
| `runner_completed_ttl_minutes` | `5` | Minutes to retain a completed runner before deletion |
| `max_runner_runtime_hours` | `2` | Hard cap on runner lifetime |
| `cpu` | `2` | CPU cores per runner |
| `memory` | `4` | Memory (GB) per runner |
| `runner_labels` | `azure,container-instance,self-hosted` | Comma-separated runner labels |
| `acr_sku` | `Standard` | Container Registry SKU |
| `storage_account_replication_type` | `LRS` | State storage replication |
| `enable_public_network_access` | `true` | Set to `false` for private endpoint environments |
| `tags` | `{Environment, ManagedBy, Purpose}` | Common resource tags |

---

## Outputs

| Output | Description |
|---|---|
| `function_app_name` | Function App name |
| `function_app_default_hostname` | Function App hostname (use for webhook URL) |
| `acr_login_server` | ACR login server URL |
| `acr_id` | ACR resource ID |
| `key_vault_uri` | Key Vault URI |
| `key_vault_id` | Key Vault resource ID |
| `servicebus_namespace_name` | Service Bus namespace name |
| `servicebus_queue_name` | Service Bus queue name |
| `storage_account_id` | State storage account ID |
| `function_storage_account_id` | Function App storage account ID |

---

## Runner image

On every `terraform apply`, this module imports the public runner image into ACR:

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
| `cleanup_timer` | Timer (5 min) | Removes completed, stale, or over-TTL runners |

Key behaviours:
- `maxConcurrentCalls: 1` on the Service Bus trigger prevents duplicate scale operations
- Scale formula: `max(scale_hint, queue_backlog)` — never sums, avoids over-provisioning
- Non-terminal runner deduplication — terminated containers are not counted as active
