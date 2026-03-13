# Improvement Plan: Event-Driven Ephemeral GitHub Runners on Azure

Verified against official Microsoft documentation and Azure Well-Architected Framework (March 2026).

---

## Remaining Improvements

### Security & RBAC

#### Tighten Function App RBAC scope

**Current**: Scaler Function App has `Contributor` on the entire resource group.

**Recommended**: Use a custom role with only the required ACI operations, or scope Contributor down to only the specific resources needed.

**Source**: [Azure best practices — least privilege](https://learn.microsoft.com/azure/role-based-access-control/best-practices)

#### Pin GitHub Actions to commit SHAs

**Current**: Actions pinned to major version tags (`@v4`, `@v2`, `@v3`).

**Recommended**: Pin to full commit SHA for supply chain security. Add Dependabot for automatic updates.

#### Consider GitHub Environment protection rules

**Current**: `terraform apply -auto-approve` runs automatically on push to main.

**Recommended**: For a module used by multiple consumers, consider adding a GitHub Environment with required reviewers for production applies.

#### Pin semantic-release dependencies

**Current**: `release.yml` runs `npm install -g semantic-release @semantic-release/...` without version pins.

**Recommended**: Pin exact versions or use a lockfile to prevent unexpected breaking changes.

### Python / Function App

#### Optimize cleanup timer for high runner counts

**Current**: `cleanup_timer` calls individual GET per runner every minute. At `max_instances=200`, that's 200+ ARM calls/min.

**Recommended**: Add caching or batch operations. Only relevant if scaling beyond 10-20 runners.

#### Pin Python dependencies

**Current**: `requirements.txt` uses minimum version constraints (`azure-identity>=1.16.0`) without upper bounds.

**Recommended**: Pin exact versions (e.g., `azure-functions==1.21.3`) for reproducible deployments.

---

## Completed ✅

### Architecture & Module Structure
- Package as Terraform module — resources moved to `modules/runners/`, root is a thin wrapper, `examples/demo/` for demo usage
- Simplify variable surface — 3 core variables (`workload`, `environment`, `instance`) generate all resource names via Azure CAF conventions, with override support
- Configurable resource group creation via `create_resource_group`
- Remove stale `moved` blocks — 25 migration blocks removed after state migration completed

### Security & RBAC
- Runner workload roles default changed from `["Contributor"]` to `[]` (least privilege)
- Hardcoded subscription ID removed from demo
- Generic error messages in webhook (no exception details exposed)

### Infrastructure
- Migrate to FC1 Flex Consumption — `sku_name = "FC1"`, VNet support via `subnet_id`
- Remove storage access key — managed identity with `AzureWebJobsStorage__accountName`
- Remove instrumentation key — connection string only (instrumentation key deprecated March 2025)
- Fix `storage_account_replication_type` variable — now actually used in function storage account (was declared but hardcoded to LRS)
- Align provider versions — bootstrap, demo, and module all require `>= 4.63`

### Observability
- Log Analytics Workspace — created and linked to Application Insights
- Diagnostic settings — Key Vault, Service Bus, Function App
- Resource locks — configurable via `enable_resource_locks`

### CI/CD Workflows
- Terraform validate step added to deploy workflow
- Fix demo workflow retry logic — loops now correctly exit with failure after 3 attempts
- Improve deploy workflow role parsing — use `jq` instead of `python3` for CSV→JSON conversion
- Demo workflow uses `terraform init -upgrade` to handle lock file version updates
- Demo workflow retry for transient Azure WAF blocks on ephemeral ACI IPs

### Function App / Scaler
- Module-level HTTP session pooling (`requests.Session()`)
- Add `urllib3` retry adapter to HTTP session — automatic retries for transport-level errors (connection resets, DNS failures), simplifying `_arm_request`
- GitHub API rate limit handling in `_is_job_still_queued` — checks `X-RateLimit-Remaining` header and backs off gracefully
- Remove unused app settings — `RUNNER_IDLE_TIMEOUT_MIN` and `EVENT_POLL_INTERVAL_SEC` removed (never read by Python code)
- Fix at-capacity DLQ spam — sleep 100s between retries, check GitHub job status before retrying, ACI quota retry with backoff
- Update stale references — `local.settings.example.json`, `DEPLOYMENT.md`, and README now use CAF naming conventions
- Fix README Key Vault secret names to match deploy workflow defaults
- Update README scaler internals documentation

---

## Not Implemented (Deliberate Decision)

### Container Apps Jobs as alternative to ACI

Microsoft recommends Container Apps Jobs for self-hosted runners ([official tutorial](https://learn.microsoft.com/azure/container-apps/tutorial-ci-cd-runners-jobs)), and it would dramatically simplify the architecture (removes Function App, Service Bus, ~500 lines of Python). However, it has a critical limitation:

> **"Container apps and jobs don't support running Docker in containers. Any steps in your workflows that use Docker commands fail when run on a self-hosted runner."**
> — [Microsoft Learn](https://learn.microsoft.com/azure/container-apps/tutorial-ci-cd-runners-jobs)

For a module intended for multiple consumers, Docker support (`docker build`, `docker push`, Docker Compose, Testcontainers) is a common requirement. Excluding this limits the module's applicability too much.

**Decision**: Keep ACI as the sole compute platform. A Container Apps Jobs variant could be offered as an alternative, but the complexity of maintaining two separate implementations does not outweigh the benefits.
