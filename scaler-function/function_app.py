from __future__ import annotations

import concurrent.futures
import datetime as dt
import base64
import hashlib
import hmac
import json
import logging
import os
import uuid
from typing import Any

import azure.functions as func
import jwt
import requests
from azure.identity import DefaultAzureCredential

app = func.FunctionApp(http_auth_level=func.AuthLevel.FUNCTION)

ARM_API_VERSION = "2023-05-01"
ARM_BASE = "https://management.azure.com"
GITHUB_API_BASE = "https://api.github.com"

_registration_token_cache: dict[str, Any] = {
    "token": "",
    "expires_at": dt.datetime.fromtimestamp(0, tz=dt.timezone.utc),
}

_installation_token_cache: dict[str, Any] = {
    "token": "",
    "expires_at": dt.datetime.fromtimestamp(0, tz=dt.timezone.utc),
}

TERMINAL_RUNNER_STATES = {"succeeded", "failed", "stopped", "terminated"}


def _env(name: str, default: str | None = None, required: bool = False) -> str:
    value = os.getenv(name, default)
    if required and (value is None or str(value).strip() == ""):
        raise ValueError(f"Missing required environment variable: {name}")
    return "" if value is None else str(value)


def _int_env(name: str, default: int) -> int:
    try:
        return int(_env(name, str(default)))
    except ValueError as exc:
        raise ValueError(f"Environment variable {name} must be an integer") from exc


def _utcnow() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


def _verify_github_signature(raw: bytes, secret: str, signature_header: str | None) -> bool:
    if not secret:
        return True
    if not signature_header or not signature_header.startswith("sha256="):
        return False
    expected = "sha256=" + hmac.new(secret.encode("utf-8"), raw, hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, signature_header)


def _servicebus_send(payload: dict[str, Any]) -> None:
    from azure.servicebus import ServiceBusClient, ServiceBusMessage
    from azure.identity import DefaultAzureCredential

    fqdn = _env("SERVICEBUS_NAMESPACE_FQDN", required=True)
    queue_name = _env("SERVICEBUS_QUEUE_NAME", required=True)

    with ServiceBusClient(fully_qualified_namespace=fqdn, credential=DefaultAzureCredential()) as client:
        sender = client.get_queue_sender(queue_name=queue_name)
        with sender:
            sender.send_messages(ServiceBusMessage(json.dumps(payload)))


def _arm_token() -> str:
    credential = DefaultAzureCredential()
    token = credential.get_token("https://management.azure.com/.default")
    return token.token


def _arm_request(method: str, path: str, body: dict[str, Any] | None = None) -> requests.Response:
    subscription_id = _env("AZURE_SUBSCRIPTION_ID")
    if not subscription_id:
        raise ValueError("AZURE_SUBSCRIPTION_ID is required (set in Function App settings)")

    token = _arm_token()
    url = f"{ARM_BASE}/subscriptions/{subscription_id}{path}"
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }

    response = requests.request(method, url, headers=headers, json=body, timeout=30)
    if response.status_code >= 400:
        logging.error("ARM %s %s failed: %s", method, path, response.text)
        response.raise_for_status()
    return response


def _list_runners() -> list[dict[str, Any]]:
    rg = _env("RUNNER_RESOURCE_GROUP", required=True)
    prefix = _env("RUNNER_NAME_PREFIX", required=True)
    path = f"/resourceGroups/{rg}/providers/Microsoft.ContainerInstance/containerGroups?api-version={ARM_API_VERSION}"
    response = _arm_request("GET", path)
    items = [
        item for item in response.json().get("value", [])
        if item.get("name", "").startswith(prefix + "-")
    ]
    # The list endpoint omits instanceView; fetch each individually to get full state.
    # Use a thread pool so all GETs fire in parallel rather than sequentially.
    def _fetch_detail(item: dict[str, Any]) -> dict[str, Any]:
        name = item.get("name", "")
        try:
            detail_path = f"/resourceGroups/{rg}/providers/Microsoft.ContainerInstance/containerGroups/{name}?api-version={ARM_API_VERSION}"
            return _arm_request("GET", detail_path).json()
        except Exception:
            logging.warning("Failed to GET individual runner %s; using list data", name)
            return item

    if not items:
        return []
    with concurrent.futures.ThreadPoolExecutor(max_workers=min(10, len(items))) as pool:
        return list(pool.map(_fetch_detail, items))


def _parse_github_timestamp(value: str) -> dt.datetime:
    parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=dt.timezone.utc)
    return parsed.astimezone(dt.timezone.utc)


def _parse_any_timestamp(value: Any) -> dt.datetime | None:
    if not value:
        return None
    try:
        parsed = dt.datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        if parsed.tzinfo is None:
            return parsed.replace(tzinfo=dt.timezone.utc)
        return parsed.astimezone(dt.timezone.utc)
    except Exception:
        return None


def _runner_created_at(runner: dict[str, Any]) -> dt.datetime | None:
    tags = runner.get("tags") or {}
    tagged = _parse_any_timestamp(tags.get("created_at"))
    if tagged is not None:
        return tagged

    system_created = _parse_any_timestamp((runner.get("systemData") or {}).get("createdAt"))
    if system_created is not None:
        return system_created

    events = ((runner.get("properties") or {}).get("instanceView") or {}).get("events") or []
    for event in events:
        event_ts = _parse_any_timestamp(event.get("firstTimestamp") or event.get("lastTimestamp"))
        if event_ts is not None:
            return event_ts
    return None


def _runner_state(runner: dict[str, Any]) -> str:
    # Container group-level state (e.g. "Running", "Succeeded")
    state = ((runner.get("properties") or {}).get("instanceView") or {}).get("state")
    if state:
        return str(state).strip().lower()
    # Fallback: per-container currentState (e.g. "Running", "Terminated")
    containers = ((runner.get("properties") or {}).get("containers") or [])
    if containers:
        cs = (containers[0].get("instanceView") or {}).get("currentState") or {}
        container_state = cs.get("state")
        if container_state:
            return str(container_state).strip().lower()
    return ""


def _runner_workflow_job_id(runner: dict[str, Any]) -> str:
    tags = runner.get("tags") or {}
    return str(tags.get("workflow_job_id") or "").strip()


def _extract_workflow_job_id(event: dict[str, Any]) -> str:
    direct = str(event.get("workflow_job_id") or "").strip()
    if direct:
        return direct

    raw = event.get("raw") or {}
    nested = ((raw.get("workflow_job") or {}).get("id"))
    if nested is None:
        return ""
    return str(nested).strip()


def _runner_name_for_workflow_job(workflow_job_id: str) -> str:
    prefix = _env("RUNNER_NAME_PREFIX", required=True)
    digest = hashlib.sha1(workflow_job_id.encode("utf-8")).hexdigest()[:8]
    return f"{prefix}-{digest}"


def _prune_stale_runners(runners: list[dict[str, Any]]) -> int:
    max_runtime_hours = _int_env("MAX_RUNNER_RUNTIME_HOURS", 2)
    terminal_ttl_minutes = _int_env("RUNNER_COMPLETED_TTL_MINUTES", 5)
    now = _utcnow()

    deleted = 0
    for runner in runners:
        name = str(runner.get("name", "")).strip()
        if not name:
            continue

        state = _runner_state(runner)
        created_at = _runner_created_at(runner)

        age_hours = None
        age_minutes = None
        if created_at is not None:
            delta = now - created_at
            age_hours = delta.total_seconds() / 3600
            age_minutes = delta.total_seconds() / 60

        should_delete = False
        reason = ""

        if age_hours is not None and age_hours >= max_runtime_hours:
            should_delete = True
            reason = f"runtime>{max_runtime_hours}h"
        elif state in TERMINAL_RUNNER_STATES and (age_minutes is None or age_minutes >= terminal_ttl_minutes):
            should_delete = True
            reason = f"terminal+ttl>{terminal_ttl_minutes}m"

        if should_delete:
            logging.info("Pruning runner %s (%s, state=%s)", name, reason, state or "unknown")
            _delete_runner(name)
            deleted += 1

    return deleted


def _has_runner_for_workflow_job(runners: list[dict[str, Any]], workflow_job_id: str) -> bool:
    """Return True only if a non-terminal runner already exists for this job."""
    if not workflow_job_id:
        return False
    for runner in runners:
        if _runner_workflow_job_id(runner) == workflow_job_id:
            if _runner_state(runner) not in TERMINAL_RUNNER_STATES:
                return True
    return False


def _normalize_private_key(raw_key: str) -> str:
    value = str(raw_key).strip()
    if (value.startswith('"') and value.endswith('"')) or (value.startswith("'") and value.endswith("'")):
        value = value[1:-1]

    value = value.replace("\\r", "\r").replace("\\n", "\n")

    if "BEGIN" in value and "PRIVATE KEY" in value:
        return value

    compact = "".join(value.split())
    try:
        decoded = base64.b64decode(compact, validate=True).decode("utf-8")
        decoded = decoded.strip().replace("\\r", "\r").replace("\\n", "\n")
        if "BEGIN" in decoded and "PRIVATE KEY" in decoded:
            return decoded
    except Exception:
        pass

    return value


def _github_installation_access_token() -> str:
    app_id = _env("GITHUB_APP_ID", required=True)
    installation_id = _env("GITHUB_APP_INSTALLATION_ID", required=True)
    private_key = _normalize_private_key(_env("GITHUB_APP_PRIVATE_KEY", required=True))

    now = _utcnow()
    cached_token = str(_installation_token_cache.get("token", ""))
    cached_expiry = _installation_token_cache.get("expires_at")
    if (
        cached_token
        and isinstance(cached_expiry, dt.datetime)
        and cached_expiry > now + dt.timedelta(minutes=2)
    ):
        return cached_token

    payload = {
        "iat": int((now - dt.timedelta(seconds=60)).timestamp()),
        "exp": int((now + dt.timedelta(minutes=9)).timestamp()),
        "iss": app_id,
    }
    app_jwt = jwt.encode(payload, private_key, algorithm="RS256")

    url = f"{GITHUB_API_BASE}/app/installations/{installation_id}/access_tokens"
    headers = {
        "Authorization": f"Bearer {app_jwt}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    }

    response = requests.post(url, headers=headers, timeout=30)
    if response.status_code >= 400:
        logging.error("GitHub App installation token minting failed: %s", response.text)
        response.raise_for_status()

    payload_json = response.json()
    token = str(payload_json.get("token", "")).strip()
    expires_at_raw = str(payload_json.get("expires_at", "")).strip()
    if not token or not expires_at_raw:
        raise ValueError("GitHub App installation token response missing token or expires_at")

    _installation_token_cache["token"] = token
    _installation_token_cache["expires_at"] = _parse_github_timestamp(expires_at_raw)
    return token


def _github_runner_registration_token() -> str:
    now = _utcnow()
    cached_token = str(_registration_token_cache.get("token", ""))
    cached_expiry = _registration_token_cache.get("expires_at")
    if (
        cached_token
        and isinstance(cached_expiry, dt.datetime)
        and cached_expiry > now + dt.timedelta(minutes=2)
    ):
        return cached_token

    repo = _env("GITHUB_REPO", required=True)
    url = f"{GITHUB_API_BASE}/repos/{repo}/actions/runners/registration-token"
    headers = {
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    }

    auth_token = _github_installation_access_token()
    headers["Authorization"] = f"Bearer {auth_token}"

    response = requests.post(url, headers=headers, timeout=30)
    if response.status_code >= 400:
        logging.error("GitHub token refresh failed: %s", response.text)
        response.raise_for_status()

    payload = response.json()
    token = str(payload.get("token", "")).strip()
    if not token:
        raise ValueError("GitHub registration token refresh returned empty token")

    _registration_token_cache["token"] = token
    _registration_token_cache["expires_at"] = now + dt.timedelta(minutes=55)
    return token


def _runner_secure_env() -> dict[str, str]:
    refreshed = _github_runner_registration_token()
    return {"RUNNER_TOKEN": refreshed}


def _create_runner(workflow_job_id: str = "") -> str:
    rg = _env("RUNNER_RESOURCE_GROUP", required=True)
    location = _env("AZURE_LOCATION", "westeurope")
    prefix = _env("RUNNER_NAME_PREFIX", required=True)
    runner_name = _runner_name_for_workflow_job(workflow_job_id) if workflow_job_id else f"{prefix}-{uuid.uuid4().hex[:8]}"

    runner_image = _env("RUNNER_IMAGE", required=True)
    labels = _env("RUNNER_LABELS", "azure,container-instance,self-hosted")
    repo = _env("GITHUB_REPO", required=True)
    pull_identity_id = _env("RUNNER_PULL_IDENTITY_ID", required=True)

    cpu = _int_env("RUNNER_CPU", 2)
    memory = _int_env("RUNNER_MEMORY", 4)

    pull_identity_client_id = _env("RUNNER_PULL_IDENTITY_CLIENT_ID", required=True)

    environment_variables = [
        {"name": "REPO_URL", "value": f"https://github.com/{repo}"},
        {"name": "RUNNER_NAME", "value": runner_name},
        {"name": "LABELS", "value": labels},
        {"name": "EPHEMERAL", "value": "true"},
        # ARM_CLIENT_ID tells azurerm/terraform which user-assigned managed identity
        # to use when authenticating via IMDS (ARM_USE_MSI=true)
        {"name": "ARM_CLIENT_ID", "value": pull_identity_client_id},
    ]
    secure_environment_variables = [{"name": key, "secureValue": value} for key, value in _runner_secure_env().items()]

    body = {
        "location": location,
        "tags": {
            "managed-by": "runner-scaler",
            "created_at": _utcnow().isoformat(),
            "workflow_job_id": workflow_job_id,
            "ephemeral": "true",
        },
        "identity": {
            "type": "SystemAssigned, UserAssigned",
            "userAssignedIdentities": {
                pull_identity_id: {}
            },
        },
        "properties": {
            "osType": "Linux",
            "restartPolicy": "Never",
            "containers": [
                {
                    "name": "github-runner",
                    "properties": {
                        "image": runner_image,
                        "resources": {
                            "requests": {
                                "cpu": cpu,
                                "memoryInGB": memory,
                            }
                        },
                        "environmentVariables": environment_variables + secure_environment_variables,
                    },
                }
            ],
            "imageRegistryCredentials": [
                {
                    "server": runner_image.split("/")[0],
                    "identity": pull_identity_id,
                }
            ],
        },
    }

    path = f"/resourceGroups/{rg}/providers/Microsoft.ContainerInstance/containerGroups/{runner_name}?api-version={ARM_API_VERSION}"
    try:
        _arm_request("PUT", path, body)
    except requests.HTTPError as exc:
        if exc.response is not None and exc.response.status_code == 409:
            logging.info("Runner %s already exists (409 conflict); treating as idempotent", runner_name)
        else:
            raise
    logging.info("Created runner %s", runner_name)
    return runner_name


def _delete_runner(name: str) -> None:
    rg = _env("RUNNER_RESOURCE_GROUP", required=True)
    path = f"/resourceGroups/{rg}/providers/Microsoft.ContainerInstance/containerGroups/{name}?api-version={ARM_API_VERSION}"
    _arm_request("DELETE", path)
    logging.info("Deleted runner %s", name)


def _scale_once(scale_hint: int = 0, workflow_job_id: str = "") -> dict[str, Any]:
    min_instances = _int_env("RUNNER_MIN_INSTANCES", 0)
    max_instances = _int_env("RUNNER_MAX_INSTANCES", 10)

    runners = _list_runners()
    pruned = _prune_stale_runners(runners)
    if pruned > 0:
        runners = _list_runners()

    if _has_runner_for_workflow_job(runners, workflow_job_id):
        logging.info("Duplicate workflow_job event detected (id=%s); suppressing extra scale-up", workflow_job_id)
        scale_hint = 0

    active_runners = [runner for runner in runners if _runner_state(runner) not in TERMINAL_RUNNER_STATES]
    current = len(active_runners)

    if workflow_job_id:
        # Job event: create exactly 1 runner for this job.
        desired = min(max_instances, current + scale_hint)
    else:
        # Timer path: only maintain min_instances floor.
        # The SB trigger is solely responsible for job-driven scale-up.
        desired = max(min_instances, current)

    created = 0
    deleted = 0

    if workflow_job_id and scale_hint > 0 and current >= max_instances:
        # At capacity — do not consume this message. Re-raise so Service Bus
        # retries it after the lock timeout (default 30s), by which time a
        # slot may have freed up.
        raise RuntimeError(
            f"At max_instances ({max_instances}); deferring job {workflow_job_id} for retry"
        )

    while current < desired:
        _create_runner(workflow_job_id=workflow_job_id if created == 0 else "")
        current += 1
        created += 1

    if current > max_instances:
        for runner in sorted(active_runners, key=lambda item: item.get("name", "")):
            if current <= max_instances:
                break
            _delete_runner(runner["name"])
            current -= 1
            deleted += 1

    return {
        "desired": desired,
        "current": current,
        "created": created,
        "deleted": deleted,
        "pruned": pruned,
        "workflow_job_id": workflow_job_id,
    }


@app.function_name(name="github_webhook")
@app.route(route="webhook/github", methods=["POST"])
def github_webhook(req: func.HttpRequest) -> func.HttpResponse:
    try:
        raw = req.get_body()
        secret = _env("WEBHOOK_SECRET")
        signature = req.headers.get("X-Hub-Signature-256")

        if secret and not _verify_github_signature(raw, secret, signature):
            return func.HttpResponse("Invalid signature", status_code=401)

        payload = req.get_json()
        event_name = req.headers.get("X-GitHub-Event", "unknown")

        # Only process workflow_job events
        if event_name == "ping":
            return func.HttpResponse("pong", status_code=200)
        if event_name != "workflow_job":
            logging.info("Ignoring event type: %s", event_name)
            return func.HttpResponse("ignored", status_code=200)

        # Only process jobs targeting self-hosted runners
        job_labels = [str(l).lower() for l in ((payload.get("workflow_job") or {}).get("labels") or [])]
        if "self-hosted" not in job_labels:
            logging.info("Ignoring workflow_job not targeting self-hosted (labels=%s)", job_labels)
            return func.HttpResponse("ignored", status_code=200)

        message = {
            "event": event_name,
            "received_at": _utcnow().isoformat(),
            "repository": payload.get("repository", {}).get("full_name"),
            "action": payload.get("action"),
            "workflow_job_id": ((payload.get("workflow_job") or {}).get("id")),
            "raw": payload,
        }

        _servicebus_send(message)
        return func.HttpResponse("queued", status_code=202)
    except Exception as exc:
        logging.exception("Webhook processing failed")
        return func.HttpResponse(f"error: {exc}", status_code=500)


@app.function_name(name="scale_worker")
@app.service_bus_queue_trigger(
    arg_name="message",
    queue_name="%SERVICEBUS_QUEUE_NAME%",
    connection="SERVICEBUS_CONNECTION",
)
def scale_worker(message: func.ServiceBusMessage) -> None:
    try:
        body = message.get_body().decode("utf-8")
        event = json.loads(body)

        scale_hint = 0
        action = event.get("action")
        if action in {"queued", "requested", "created"}:
            scale_hint = 1

        workflow_job_id = _extract_workflow_job_id(event)
        result = _scale_once(scale_hint=scale_hint, workflow_job_id=workflow_job_id)
        logging.info("Scale result: %s", json.dumps(result))
    except Exception:
        logging.exception("Scale worker failed")
        raise


@app.timer_trigger(
    arg_name="timer",
    schedule="0 */5 * * * *",
    run_on_startup=False,
    use_monitor=True,
)
def cleanup_timer(timer: func.TimerRequest) -> None:
    if timer.past_due:
        logging.warning("Cleanup timer is running late")

    result = _scale_once(scale_hint=0)
    logging.info(
        "Timer cleanup result: pruned=%s desired=%s current=%s",
        result.get("pruned"),
        result.get("desired"),
        result.get("current"),
    )
