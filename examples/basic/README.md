# Basic Example — Consuming the Runners Module

This example shows the minimum setup needed to deploy the GitHub runners platform in your own project. All configuration is driven by GitHub repository secrets and variables — no hardcoded values in the Terraform files.

## Files

```
├── main.tf                                  # Module call (reads from variables)
├── variables.tf                             # Variable declarations
├── versions.tf                             # Provider and backend configuration
└── .github/workflows/deploy-runners.yml     # CI/CD workflow (generates tfvars from GitHub variables)
```

## Quick start

### 1. Copy files into your project

Copy this directory into your project (e.g., as `infra/runners/`) and copy `.github/workflows/deploy-runners.yml` to your repo's `.github/workflows/`.

### 2. Create Azure identity (one-time)

Follow [step 2 in the main README](../../README.md#2-provision-azure-identity-and-permissions) to create the service principal with OIDC trust.

> When creating the federated credential, set the `subject` to your own repository (e.g. `repo:your-org/your-repo:ref:refs/heads/main`), not the module source repo.

### 3. Configure GitHub secrets and variables

**Secrets** (Settings → Secrets and variables → Actions → Repository secrets):

| Secret | Value |
|---|---|
| `AZURE_CLIENT_ID` | Service principal client ID |
| `AZURE_TENANT_ID` | Azure AD tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Target subscription ID |

**Variables** (Settings → Secrets and variables → Actions → Repository variables):

| Variable | Example | Description |
|---|---|---|
| `WORKLOAD` | `runner` | Short workload identifier |
| `ENVIRONMENT` | `prod` | Environment (e.g. prod, dev) |
| `INSTANCE` | `001` | Instance for uniqueness |
| `AZURE_LOCATION` | `westeurope` | Azure region |
| `GH_ORG` | `your-org` | GitHub organization |
| `GH_REPO` | `your-org/your-repo` | Repository in org/repo format |
| `RUNNER_MODULE_REF` | `v3.0.0` | Module version tag (optional, defaults to v3.0.0) |
| `RUNNER_WORKLOAD_ROLES` | `Contributor` | Comma-separated Azure roles for runner identity (optional) |
| `STATE_RESOURCE_GROUP` | `rg-tfstate` | Resource group containing the state storage account |
| `STATE_STORAGE_ACCOUNT` | `sttfstate1a2b` | Storage account name for Terraform state |
| `STATE_CONTAINER` | `tfstate` | Blob container name (optional, defaults to tfstate) |

### 4. Configure Terraform state backend

The workflow generates a `backend.hcl` file at runtime from the `STATE_*` GitHub variables above, so you don't need to hardcode backend values in your Terraform files.

You just need a storage account. Either use an existing one or create one:

```bash
LOCATION=westeurope
STATE_RG=rg-tfstate
STATE_SA=sttfstate$(openssl rand -hex 4)  # must be globally unique

az group create --name $STATE_RG --location $LOCATION
az storage account create \
  --name $STATE_SA --resource-group $STATE_RG --location $LOCATION \
  --sku Standard_LRS --allow-blob-public-access false
az storage container create \
  --name tfstate --account-name $STATE_SA

# Grant your CI service principal access
SP_OBJECT_ID=$(az ad sp show --id <AZURE_CLIENT_ID> --query id -o tsv)
az role assignment create \
  --assignee-object-id $SP_OBJECT_ID --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Contributor" \
  --scope $(az storage account show --name $STATE_SA --query id -o tsv)
```

Then set the three `STATE_*` variables in your GitHub repo (step 3 above).

> The workflow authenticates via OIDC, so no storage access keys are needed.

### 5. Push to main

The workflow handles everything:
- Generates `terraform.tfvars` from your GitHub variables
- Runs `terraform apply` (infrastructure)
- Imports the runner container image into ACR
- Deploys the scaler function code (fetched from the module repo)

## After first deploy

1. Store GitHub App secrets in the Key Vault — see [main README step 6](../../README.md#6-store-github-app-secrets-in-key-vault)
2. Register the GitHub webhook — see [main README step 7](../../README.md#7-register-the-webhook-in-github)
3. Trigger a workflow with `runs-on: [self-hosted, azure, container-instance]` to test

## Troubleshooting

**Key Vault secrets timing**: The Function App starts immediately after `terraform apply`, but Key Vault secrets (step 6) aren't stored yet. The scaler will log errors until the secrets exist — this is expected. Store the secrets, then the next webhook event will work.

**GitHub App installation scope**: The App must be installed on the specific repository that sends webhook events. If you created an org-level App, install it on the target repo via the App's "Install" page.

**OIDC federated credential subject mismatch**: The `subject` in the federated credential must exactly match your repo and branch. A `repo:wrong-org/wrong-repo:ref:refs/heads/main` subject will cause `AADSTS700024` errors in the workflow.
