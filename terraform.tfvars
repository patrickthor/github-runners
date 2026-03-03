resource_group_name  = "pocgithubrunners"
location             = "westeurope"
acr_name             = "runnerpocbouvetacr"
aci_name             = "runnerpocbouvet"
key_vault_name       = "kv-runner-bvt-030226"
storage_account_name = "ststatebouvetpoc"

github_org  = "patrickthor"
github_repo = "patrickthor/github-runners"

servicebus_namespace_name     = "sb-runner-bvt-030226"
function_app_name             = "func-runner-bvt-030226"
function_storage_account_name = "stfuncbvt030226"
