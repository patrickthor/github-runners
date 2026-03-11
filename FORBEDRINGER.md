# Forbedringsplan: Event-Driven Ephemeral GitHub Runners on Azure

Verifisert mot offisiell Microsoft-dokumentasjon og Azure Well-Architected Framework via MCP-verktøy (mars 2026).

---

## 1. Sikkerhet og RBAC

### 1a. Stram inn Function App RBAC-scope

**Nåværende**: Scaler Function App har `Contributor` på hele resource group.

**Anbefalt**: Bruk en custom role med kun de nødvendige ACI-operasjonene, eller scope Contributor ned til kun de spesifikke ressursene som trengs.

**Kilde**: [Azure best practices — least privilege](https://learn.microsoft.com/azure/role-based-access-control/best-practices)

---

## 2. GitHub Actions-forbedringer

### 2a. Vurder GitHub Environment protection rules

**Nåværende**: `terraform apply -auto-approve` kjører automatisk på push til main.

**Anbefalt**: For en modul som brukes av flere kunder, vurder å legge til et GitHub Environment med required reviewers for produksjons-apply. Dokumenter dette som anbefalt oppsett.

### 2b. Pin GitHub Actions til SHA

**Nåværende**: Actions pinnet til major version (`@v4`, `@v2`, `@v3`).

**Anbefalt**: For en sikkerhetsbevisst modul, pin til full commit SHA for supply chain security. Legg til Dependabot for automatiske oppdateringer.

---

## Implementert ✅

Følgende punkter fra den opprinnelige planen er nå implementert:

- ~~4a. Pakk som Terraform-modul~~ — Ressurser flyttet til `modules/runners/`, root er en thin wrapper, `moved`-blokker for state-migrasjon, `examples/demo/` for demo
- ~~4b. Forenkle variabel-mengden~~ — 3 core-variabler (`workload`, `environment`, `instance`) genererer alle ressursnavn via CAF-konvensjoner, med override-mulighet

- ~~2b. Runner workload-roller~~ — Default endret fra `["Contributor"]` til `[]`
- ~~2c. Hardkodet subscription ID~~ — Fjernet fra demo
- ~~3a. Migrer til FC1 Flex Consumption~~ — `sku_name = "FC1"`, VNet-støtte via `subnet_id`
- ~~3b. Fjern storage access key~~ — Managed identity med `AzureWebJobsStorage__accountName`
- ~~3c. Fjern instrumentation key~~ — Kun connection string brukes
- ~~4a. Log Analytics Workspace~~ — Opprettet og koblet til Application Insights
- ~~4b. Diagnostic settings~~ — Key Vault, Service Bus, Function App
- ~~4c. Resource locks~~ — Konfigurerbar via `enable_resource_locks`
- ~~5a. Terraform validate~~ — Lagt til i deploy workflow
- ~~6a. Ikke eksponer exception-detaljer~~ — Generisk feilmelding i webhook
- ~~6b. requests.Session()~~ — Modul-nivå HTTP session pooling
- ~~7c. Opprett resource group~~ — Konfigurerbar via `create_resource_group`


---

## Ikke implementert (bevisst valg)

### Container Apps Jobs som alternativ til ACI

Microsoft anbefaler Container Apps Jobs for self-hosted runners ([offisiell tutorial](https://learn.microsoft.com/azure/container-apps/tutorial-ci-cd-runners-jobs)), og det ville forenklet arkitekturen dramatisk (fjerner Function App, Service Bus, ~500 linjer Python). Men det har en kritisk begrensning:

> **"Container apps and jobs don't support running Docker in containers. Any steps in your workflows that use Docker commands fail when run on a self-hosted runner."**
> — [Microsoft Learn](https://learn.microsoft.com/azure/container-apps/tutorial-ci-cd-runners-jobs)

For en modul som skal brukes av flere kunder er Docker-støtte (`docker build`, `docker push`, Docker Compose, Testcontainers) et vanlig krav. Å utelukke dette begrenser modulens bruksområde for mye.

**Beslutning**: Behold ACI som eneste compute-plattform. En Container Apps Jobs-variant kunne vært tilbudt som et alternativ, men kompleksiteten ved å vedlikeholde to separate implementeringer veier ikke opp for fordelene.
