# GitHub Self-Hosted Runners on Azure

Terraform module to deploy self-hosted GitHub runners on Azure Container Instances with automatic cleanup.

## Features

- **Azure Container Instances** - Scalable, ephemeral runners
- **Managed Identity** - RBAC-based authentication (no keys)
- **Auto Cleanup** - Scheduled job removes stuck/failed containers
- **Security** - Network isolation, TLS 1.2, purge protection
- **OIDC Ready** - Works with GitHub Actions OIDC authentication

## Quick Start

### 1. Generate GitHub Runner Token

```bash
export TF_VAR_github_runner_token=$(gh api repos/your-org/your-repo/actions/runners/registration-token --jq .token)
```

### 2. Configure Variables

Copy `terraform.tfvars.example` to `terraform.tfvars` and update:

```hcl
resource_group_name  = "rg-github-runners"
location             = "eastus"
acr_name             = "acrgithubrunners001"
aci_name             = "aci-runner"
key_vault_name       = "kv-github-runners-001"
storage_account_name = "stgithubrunners001"

github_org  = "your-org"
github_repo = "your-org/your-repo"

instance_count = 2
```

### 3. Deploy

```bash
terraform init
terraform plan
terraform apply
```

### 4. Update Workflows

Change `runs-on` in your GitHub Actions workflows:

```yaml
jobs:
  my_job:
    runs-on: [self-hosted, azure, container-instance]
```

## Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `resource_group_name` | Azure resource group | `rg-github-runners` |
| `location` | Azure region | `eastus` |
| `acr_name` | Container Registry (globally unique) | `acrgithubrunners001` |
| `aci_name` | Container Instance prefix | `aci-runner` |
| `key_vault_name` | Key Vault (globally unique) | `kv-github-runners-001` |
| `storage_account_name` | Storage Account (globally unique) | `stgithubrunners001` |
| `github_org` | GitHub organization | `your-org` |
| `github_repo` | GitHub repository | `your-org/your-repo` |
| `github_runner_token` | Runner registration token | Generated via API |

## Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `instance_count` | `1` | Number of runners (1-10) |
| `cpu` | `2` | CPU cores per runner (1-4) |
| `memory` | `4` | Memory GB per runner (1-16) |
| `runner_labels` | `azure,container-instance,self-hosted` | Runner labels |
| `max_runner_runtime_hours` | `8` | Max hours before cleanup |
| `cleanup_frequency_hours` | `4` | Cleanup runs per day |

## Resources Created

- Azure Container Registry (Standard)
- Azure Key Vault (with RBAC)
- Azure Storage Account (with RBAC)
- N × Azure Container Instances
- N × User-assigned identities
- Azure Automation Account (cleanup)
- RBAC role assignments

## Automatic Cleanup

The module includes an Azure Automation runbook that runs daily to remove:

- Containers in Failed/Stopped state
- Containers running > 8 hours (configurable)
- Containers in crash loops (>10 restarts)

**Manual trigger:**
```bash
az automation runbook start \
  --automation-account-name aci-runner-automation \
  --resource-group rg-github-runners \
  --name Cleanup-StaleRunners
```

## Outputs

| Output | Description |
|--------|-------------|
| `acr_login_server` | ACR login server URL |
| `key_vault_uri` | Key Vault URI |
| `runner_names` | Container group names |
| `automation_account_name` | Cleanup automation account |

## Workflow Integration

Update your GitHub Actions workflows to use self-hosted runners:

**Before:**
```yaml
runs-on: ubuntu-latest
```

**After:**
```yaml
runs-on: [self-hosted, azure, container-instance]
```

Your existing OIDC authentication continues to work unchanged.

## Cost Estimate

Default configuration (2 runners, Standard SKU):

- 2× ACI (2 core, 4GB): ~$144/month
- ACR Standard: ~$5/month
- Storage + Key Vault: ~$2/month
- Automation Account: ~$1/month

**Total: ~$150/month**

## Security Best Practices

✅ Managed identity authentication (no keys)  
✅ RBAC authorization for all resources  
✅ Network deny-by-default policies  
✅ TLS 1.2 enforcement  
✅ Purge protection enabled  
✅ Soft delete (90 days)  
✅ No admin credentials  
✅ Blob versioning and retention  

## Troubleshooting

### Runners not appearing

```bash
# Check container logs
az container logs --name aci-runner-0 --resource-group rg-github-runners

# Check runner status
gh api repos/your-org/your-repo/actions/runners
```

### Token expired

Tokens expire after 1 hour. Generate a new one:
```bash
export TF_VAR_github_runner_token=$(gh api repos/your-org/your-repo/actions/runners/registration-token --jq .token)
terraform apply
```

### Container stuck

The cleanup job runs daily. To trigger manually:
```bash
az automation runbook start \
  --automation-account-name aci-runner-automation \
  --resource-group rg-github-runners \
  --name Cleanup-StaleRunners
```

## Module Files

```
.
├── main.tf              # All resources
├── variables.tf         # Input variables
├── outputs.tf           # Module outputs
├── providers.tf         # Provider config
├── versions.tf          # Version constraints
└── terraform.tfvars.example
```

## Requirements

- Terraform >= 1.0
- Azure CLI (authenticated)
- GitHub CLI or API access
- Azure subscription with Contributor role

## License

MIT
