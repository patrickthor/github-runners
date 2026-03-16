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
| `RUNNER_MODULE_REF` | `v2.0.0` | Module version tag (optional, defaults to v2.0.0) |
| `RUNNER_WORKLOAD_ROLES` | `Contributor` | Comma-separated Azure roles for runner identity (optional) |

### 4. Configure Terraform backend

Uncomment and configure the backend block in `versions.tf`, or use local state for testing.

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
