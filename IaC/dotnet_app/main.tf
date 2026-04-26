locals {
  app_name            = "dotnet-app"
  app_name_short      = "dotnetapp"
  dev_team_db_readers = "Dev Team .NET App DB Readers"
  tags                = merge(var.default_tags, { "Application Name" = upper(local.app_name) })
  aspnetcore_env = {
    test  = "Test"
    stage = "Stage"
    prod  = "Production"
  }
}

resource "azurerm_resource_group" "main" {
  name     = "${var.environment}-${local.app_name}-rg"
  location = var.location
  tags     = local.tags
}

### Identity
resource "azurerm_user_assigned_identity" "main" {
  name                = "${var.environment}-${local.app_name}-mi"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
}

### App Service Plan and Web App with Deployment Slot
resource "azurerm_service_plan" "main" {
  name                = "${var.environment}-${local.app_name}-asp"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku_name            = "B1"
  os_type             = "Linux"
  tags                = merge({ "Purpose" = "Hosts the App Service for ${var.environment} ${local.app_name} application" }, local.tags)
}

resource "azurerm_linux_web_app" "main" {
  name                = "${var.environment}-${local.app_name}-app"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  service_plan_id     = azurerm_service_plan.main.id
  tags                = merge({ "Purpose" = "Handles requests for ${var.environment} ${local.app_name} application" }, local.tags)

  app_settings = {
    "ASPNETCORE_ENVIRONMENT" = local.aspnetcore_env[var.environment]
    "AZURE_CLIENT_ID"        = azurerm_user_assigned_identity.main.client_id
    "KeyVaultUrl"            = azurerm_key_vault.main.vault_uri
  }

  site_config {
    always_on = true
    application_stack {
      dotnet_version = "8.0"
    }
  }
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.main.id]
  }
}

resource "azurerm_linux_web_app_slot" "main" {
  name           = "${var.environment}-${local.app_name}-app-slot"
  app_service_id = azurerm_linux_web_app.main.id
  tags           = merge({ "Purpose" = "Handles requests for ${var.environment} ${local.app_name} application slot" }, local.tags)

  app_settings = {
    "ASPNETCORE_ENVIRONMENT" = local.aspnetcore_env[var.environment]
    "AZURE_CLIENT_ID"        = azurerm_user_assigned_identity.main.client_id
    "KeyVaultUrl"            = azurerm_key_vault.main.vault_uri
  }

  site_config {
    always_on = true
    application_stack {
      dotnet_version = "8.0"
    }
  }
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.main.id]
  }
}
### MSSQL Server and Database
resource "azurerm_mssql_server" "main" {
  name                = "${var.environment}-${local.app_name}-sql"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  version             = "12.0"
  azuread_administrator {
    azuread_authentication_only = true
    object_id                   = azurerm_user_assigned_identity.main.principal_id
    login_username              = azurerm_user_assigned_identity.main.name
  }
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.main.id]
  }
}

resource "azurerm_mssql_database" "main" {
  name      = "${var.environment}-${local.app_name}-db"
  server_id = azurerm_mssql_server.main.id

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_mssql_firewall_rule" "main" {
  name             = "${var.environment}-${local.app_name}-fw"
  server_id        = azurerm_mssql_server.main.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

### Storage Account and Blob Container
resource "azurerm_storage_account" "main" {
  name                     = "${var.environment}${local.app_name_short}sa"
  account_tier             = "Standard"
  account_replication_type = "GZRS"
  location                 = azurerm_resource_group.main.location
  resource_group_name      = azurerm_resource_group.main.name
  tags                     = merge({ "Purpose" = "Stores data for ${var.environment} ${local.app_name} application" }, local.tags)
}

resource "azurerm_storage_container" "main" {
  name                  = "data"
  storage_account_id    = azurerm_storage_account.main.id
  container_access_type = "private"
}

resource "azurerm_role_assignment" "mi_contributor_sa" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.main.principal_id
}

### Azure Front Door for CDN
resource "azurerm_cdn_frontdoor_profile" "main" {
  name                = "${var.environment}-${local.app_name}-fd-pr"
  resource_group_name = azurerm_resource_group.main.name
  sku_name            = "Standard_AzureFrontDoor"
  tags                = merge({ "Purpose" = "Provides CDN for ${var.environment} ${local.app_name} application" }, local.tags)
}

resource "azurerm_cdn_frontdoor_endpoint" "main" {
  name                     = "${var.environment}-${local.app_name}-fd-ep"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id
  tags                     = merge({ "Purpose" = "Provides CDN endpoint for ${var.environment} ${local.app_name} application" }, local.tags)
}

resource "azurerm_cdn_frontdoor_origin_group" "main" {
  name                     = "${var.environment}-${local.app_name}-fd-ogrp"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id
  load_balancing {}
}

# Custom domain — only created when var.custom_domain is set. 
# Front Door will generate a TXT record value for DNS ownership verification;
# that value is available as azurerm_cdn_frontdoor_custom_domain.main["true"].validation_token
# and must be added to the domain's DNS before Front Door will activate the binding.
resource "azurerm_cdn_frontdoor_custom_domain" "main" {
  for_each = var.custom_domain != null ? toset(["true"]) : []

  name                     = "${var.environment}-${local.app_name}-fd-domain"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id
  host_name                = var.custom_domain

  tls {
    certificate_type = "ManagedCertificate"
  }

  provisioner "local-exec" {
    command = "echo 'Custom domain ${var.custom_domain} requires DNS validation. Please create a TXT record with the following value to complete domain verification:' && echo '${azurerm_cdn_frontdoor_custom_domain.main["true"].validation_token}'"
  }
}

### Secrets management
resource "azurerm_key_vault" "main" {
  name                        = "${var.environment}-${local.app_name}-kv"
  resource_group_name         = azurerm_resource_group.main.name
  location                    = azurerm_resource_group.main.location
  tenant_id                   = var.tenant_id
  sku_name                    = "standard"
  soft_delete_retention_days  = 7
  purge_protection_enabled    = true
  enabled_for_disk_encryption = true
}

resource "azurerm_key_vault_secret" "main" {
  for_each = {
    "db-connection-string"             = "Server=tcp:${var.deploy_to_secondary_region ? azurerm_mssql_failover_group.main["true"].name : azurerm_mssql_server.main.name}.database.windows.net,1433;Initial Catalog=${azurerm_mssql_database.main.name};Authentication=Active Directory Managed Identity;User Id=${azurerm_user_assigned_identity.main.client_id};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
    "app-insights-instrumentation-key" = azurerm_application_insights.main.instrumentation_key
    "app-insights-connection-string"   = azurerm_application_insights.main.connection_string
  }
  name         = each.key
  value        = each.value
  key_vault_id = azurerm_key_vault.main.id
}

resource "azurerm_role_assignment" "main" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.main.principal_id
}

resource "azurerm_role_assignment" "github_actions_rg_contributor" {
  for_each             = var.github_actions_principal_object_id != null ? toset(["true"]) : []
  scope                = azurerm_resource_group.main.id
  role_definition_name = "Contributor"
  principal_id         = var.github_actions_principal_object_id
}

resource "azurerm_role_assignment" "github_actions_kv_secrets_user" {
  for_each             = var.github_actions_principal_object_id != null ? toset(["true"]) : []
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = var.github_actions_principal_object_id
}