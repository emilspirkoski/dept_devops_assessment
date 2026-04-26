# DEPT DevOps Engineer Assessment

The Terraform code and a sample .NET app are in this repo under `IaC/` and `src/`. This document covers the reasoning, go-live plan, and CI/CD approach.

Quick note on naming: the brief says "acceptance", I went with "stage" - same thing, I just find "stage" less ambiguous in a pipeline context since acceptance sometimes refers to UAT which is a separate client process.

---

## Architecture

I went with Azure. The stack is .NET/Umbraco, App Service has first-class support for it, and Azure SQL + Blob Storage map directly to the existing SQL Server and the shared media file mount. Front Door covers the CDN they already have, with WAF and health probes on top. No reason to pick anything else here.

One thing worth flagging: the brief calls this "serverless" but Umbraco isn't a good fit for actual serverless compute (Functions etc.) because it's stateful - it has a backoffice, DB, and media library. What this is, is PaaS. No VMs, no patching, autoscaling managed by the platform. Practically speaking it's the same outcome.

Request flow (single region):
- Users hit Front Door (WAF enabled)
- Front Door sends traffic to the production App Service slot
- GitHub Actions deploys new code to the staging slot, then swaps to production
- App Service connects to Azure SQL for data and Blob Storage for media
- Secrets come from Key Vault
- Telemetry goes to Application Insights and Log Analytics

How the legacy components map across:
- CMS + web server → App Service (single app, Umbraco runs backoffice and frontend together)
- SQL Server → Azure SQL
- Network file share (media) → Blob Storage, using the `Umbraco.StorageProviders.AzureBlob` package
- CDN → Front Door Standard
- FTP deploys → GitHub Actions with slot-based deploys

Three environments (test, stage, prod), each in its own subscription with separate resource groups, databases, and Key Vaults.

---

## Go-Live Plan

This assumes infra is already provisioned in prod and the app has been through test and stage successfully.

**A week before:**
Lower the DNS TTL for companyx.com to 300 seconds now - not on the day. Do a dry-run of the DB migration against a copy of prod data and make sure it finishes cleanly. Same with the media sync to Blob Storage, it's worth knowing how long that takes before the actual window. Confirm the prod Key Vault has all three secrets, Front Door custom domain is verified, and SSL cert is active. Make sure everyone on the team can actually log into Azure portal, the DNS provider, and GitHub Actions - you don't want to find out someone doesn't have access during the window.

**Day before:**
Rehearse the full deploy: trigger `app_deploy.yml` manually against prod, validate the staging slot, do the swap, then swap back. If anything breaks during rehearsal, the go-live doesn't happen.

**Go-live window:**

First, take a SQL backup from the legacy environment and export Umbraco content. Then put the legacy site into maintenance mode - from this point, no new content goes in and the client needs to know the window has started.

Run the final media sync:
```bash
azcopy sync "\\legacy-server\media" "https://<storage-account>.blob.core.windows.net/media" --recursive
```

Run the DB migration against prod SQL and spot-check a few tables look right.

Trigger `app_deploy.yml` via workflow_dispatch. If the pipeline fails, stop - don't try to push through it. Once it's deployed to the staging slot, verify it manually:
```bash
curl -s -o /dev/null -w "%{http_code}" https://<app-name>-staging.azurewebsites.net/health
```
Also log into the Umbraco backoffice on the slot and check the content tree and media library look right.

Once that's done, we do the swap:
```bash
az webapp deployment slot swap \
  --resource-group prod-dotnet-app-rg \
  --name <app-name> \
  --slot staging \
  --target-slot production
```

Then update DNS - point companyx.com CNAME to the Front Door endpoint. With TTL at 300s it propagates fast. Watch `dig +short companyx.com` to confirm. After that, check the site loads through Front Door, backoffice is accessible at `/umbraco`, and Application Insights isn't showing a spike in errors.

**Rollback:** If HTTP 5xx goes above 2% and stays there, or the backoffice is broken, or content is missing - revert DNS to the legacy server and swap the slot back. Keep the old environment running for at least 48 hours before decommissioning anything.

---

## CI/CD

GitHub Actions. If the code is already in GitHub, then it will have native OIDC federation with Azure, so the pipeline authenticates without storing any credentials. No need to manage long-lived client secrets anywhere. Azure DevOps could work too but it's extra work if the repo is already on GitHub.

Three workflows:

`terraform_plan.yml` runs on pull requests - fmt check, validate, plan across all three environments. Failed plan = blocked PR.

`terraform_deploy.yml` runs on merge to main for IaC changes. Applies test → stage → prod in order, manual approval required before stage and prod. The plan artifact from the plan job gets reused in apply, so there's no risk of the apply running a different plan than what was reviewed.

`app_deploy.yml` runs on merge to main when `src/` changes, or manually. Builds once, deploys to each environment's staging slot in sequence. Before each swap it pulls secrets from Key Vault and substitutes them into the config file, then validates the slot returns 200, then swaps.

Security-wise: OIDC only, no `ARM_CLIENT_SECRET`, the app runs as a managed identity with least-privilege RBAC, secrets stay in Key Vault and are injected at deploy time.

---

## IaC

Terraform with `azurerm` and `azuread` providers, due to HCL's structured code and modularity, giving us the opportunity to reuse the code wherever and however we want. I can say that I also considered Bicep but its lack of local modules makes the configuration far tougher than it should be. The Terraform module structure is pretty straightforward - `github_oidc/` sets up the Entra app and OIDC federation for the pipelines, `dotnet_app/` has everything else. Each environment gets its own remote `tfstate` in a separate storage account so that environments are fully isolated.

---

## Multi-Region (bonus)

For prod, there's an active-passive DR setup controlled by two variables in Terraform: `deploy_to_secondary_region` which spins up a second App Service in North Europe and adds it as a standby origin in Front Door, and `switch_to_secondary_region` which flips the priority so traffic routes to the secondary. Front Door health probes every 30 seconds, so automatic failover happens within about a minute if the primary goes down.

Request flow (multi-region / DR):
- Front Door keeps West Europe as priority 1 and North Europe as standby
- Health probes run every 30 seconds
- If West Europe fails health checks, traffic fails over to North Europe automatically
- Blob Storage is GZRS, so media is already region-resilient
- SQL geo-replication is planned next (not implemented in Terraform yet)

Blob Storage is GZRS so that's already cross-region. SQL geo-replication is in the diagram but I scoped it out of the Terraform for now - it would be the natural next addition.

---

## Monitoring (bonus)

Azure Monitor + Application Insights + Log Analytics. I didn't look at adding Datadog or anything external - native tooling is fine for this scale and it's one less thing to manage.

Alerts set up in Terraform: HTTP 5xx > 10 in 15 minutes, CPU > 80% for 15 minutes, and availability tests probing the Front Door endpoint from 5 locations every 5 minutes (a second one for the DR app when it's deployed). All of them notify via an Action Group email.

The availability tests are the most useful thing here post-go-live - they'll catch a regional routing issue that wouldn't necessarily produce 5xx errors. During hypercare I'd also keep Application Insights Live Metrics open to catch exceptions in real time rather than waiting for alert thresholds.



