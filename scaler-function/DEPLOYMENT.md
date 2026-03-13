# Function App Deployment Notes

## Deployment Method

Use Azure Functions Core Tools (v4+). **Do not use `terraform apply` to deploy code** — the `zip_deploy_file` resource has a race condition on Linux Consumption plans.

```bash
cd scaler-function
func azure functionapp publish func-runner-poc-bvt --python --build remote
```

The `--build remote` flag triggers an Oryx build on the SCM container (pip install, squashfs packaging). Required for Python on Linux Consumption.

---

## Known Issues & Fixes

### 1. Functions not registered after deploy (zero functions discovered)
**Symptom**: `Functions in <app>:` shows empty list after publish.  
**Cause**: A module-level exception in `function_app.py` silently prevents all function registrations. The host shows no error.  
**Fix**: Ensure all decorator usage is standard `@app.timer_trigger(...)` syntax. Imperative reversed-decorator patterns (`app.function_name(...)(fn)` before the trigger decorator) throw at import time.

### 2. Cleanup timer not deleting terminated containers
**Symptom**: Containers stuck in `Succeeded`/`Terminated` state indefinitely.  
**Cause**: The ARM List API (`GET /containerGroups`) does **not** return `instanceView`. Only individual `GET /containerGroups/{name}` does.  
**Fix**: `_list_runners()` now calls individual GETs for each container to get full state. `_runner_state()` also falls back to `containers[0].instanceView.currentState.state`.

### 3. Multiple containers created for a single job
**Symptom**: One webhook event results in 2–3 container instances being created.  
**Cause 1**: `host.json` defaulted `maxConcurrentCalls` to 16, causing parallel `scale_worker` executions that all read 0 runners simultaneously.  
**Fix**: Set `maxConcurrentCalls: 1` in `host.json` to serialize scale decisions.  
**Cause 2**: Scale formula used `scale_hint + queue_backlog` — when 1 message was in-flight and 1 was waiting, desired became 2.  
**Fix**: Changed to `max(scale_hint, queue_backlog)`. Each message gets its own serialized invocation, so the next invocation handles the next job.

### 4. `WEBSITE_RUN_FROM_PACKAGE=1` breaks deployment on Linux Consumption
**Symptom**: Function app starts but functions are not found / app errors on startup.  
**Cause**: `WEBSITE_RUN_FROM_PACKAGE=1` tells the host to look for a local zip that doesn't exist. On Linux Consumption, `func azure functionapp publish` manages the `SCM_RUN_FROM_PACKAGE` blob SAS URL internally.  
**Fix**: Remove `WEBSITE_RUN_FROM_PACKAGE` from app settings. Keep `ENABLE_ORYX_BUILD=true` and `SCM_DO_BUILD_DURING_DEPLOYMENT=true`.

### 5. Webhook not triggering runner creation
**Symptom**: GitHub Actions job queued but no container created, no webhook hit in App Insights.  
**Cause**: GitHub webhook misconfigured (wrong URL, wrong event type, or missing `self-hosted` label on the workflow job).  
**Fix**:
- Webhook URL format: `https://<app>.azurewebsites.net/api/webhook/github?code=<function_key>`
- Content type: `application/json`
- Event: **Workflow jobs** only
- Workflow must use `runs-on: [self-hosted, ...]` — jobs without `self-hosted` label are ignored by the function

---

## Retrieving the Webhook URL

```bash
KEY=$(az functionapp function keys list -g rg-runner-poc-bvt -n func-runner-poc-bvt \
  --function-name github_webhook --query default -o tsv)
echo "https://func-runner-poc-bvt.azurewebsites.net/api/webhook/github?code=$KEY"
```

---

## Verifying Deployment

After publish, confirm all three functions appear:
```
Functions in func-runner-poc-bvt:
    cleanup_timer - [timerTrigger]
    github_webhook - [httpTrigger]
    scale_worker   - [serviceBusTrigger]
```

If any are missing, check for module-level import errors (see issue #1).
