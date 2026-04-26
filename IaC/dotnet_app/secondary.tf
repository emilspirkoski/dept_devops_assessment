### Secondary-region DR resources
resource "azurerm_mssql_server" "secondary" {
  for_each            = var.deploy_to_secondary_region ? toset(["true"]) : []
  name                = "${var.environment}-${local.app_name}-sql-dr"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.secondary_location
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

resource "azurerm_mssql_firewall_rule" "secondary" {
  for_each         = var.deploy_to_secondary_region ? toset(["true"]) : []
  name             = "${var.environment}-${local.app_name}-fw-dr"
  server_id        = azurerm_mssql_server.secondary["true"].id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

resource "azurerm_mssql_failover_group" "main" {
  for_each  = var.deploy_to_secondary_region ? toset(["true"]) : []
  name      = "${var.environment}-${local.app_name}-fog"
  server_id = azurerm_mssql_server.main.id
  databases = [azurerm_mssql_database.main.id]

  partner_server {
    id = azurerm_mssql_server.secondary["true"].id
  }

  read_write_endpoint_failover_policy {
    mode          = "Automatic"
    grace_minutes = 60
  }

  tags = merge({ "Purpose" = "Provides SQL failover group for ${var.environment} ${local.app_name} database" }, local.tags)
}

resource "azurerm_service_plan" "secondary" {
  for_each            = var.deploy_to_secondary_region ? toset(["true"]) : []
  name                = "${var.environment}-${local.app_name}-asp-dr"
  location            = var.secondary_location
  resource_group_name = azurerm_resource_group.main.name
  sku_name            = "B1"
  os_type             = "Linux"
  tags                = merge({ "Purpose" = "Hosts the secondary DR App Service for ${var.environment} ${local.app_name} application" }, local.tags)
}

resource "azurerm_linux_web_app" "secondary" {
  for_each            = var.deploy_to_secondary_region ? toset(["true"]) : []
  name                = "${var.environment}-${local.app_name}-app-dr"
  location            = var.secondary_location
  resource_group_name = azurerm_resource_group.main.name
  service_plan_id     = azurerm_service_plan.secondary["true"].id
  tags                = merge({ "Purpose" = "Handles DR requests for ${var.environment} ${local.app_name} application" }, local.tags)

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

### Front Door routing and DR origins
resource "azurerm_cdn_frontdoor_origin" "main" {
  name                           = "${var.environment}-${local.app_name}-fd-orig"
  cdn_frontdoor_origin_group_id  = azurerm_cdn_frontdoor_origin_group.main.id
  host_name                      = azurerm_linux_web_app.main.default_hostname
  priority                       = var.deploy_to_secondary_region && var.switch_to_secondary_region ? 2 : 1
  weight                         = 1000
  certificate_name_check_enabled = false
}

resource "azurerm_cdn_frontdoor_origin" "secondary" {
  for_each                       = var.deploy_to_secondary_region ? toset(["true"]) : []
  name                           = "${var.environment}-${local.app_name}-fd-orig-dr"
  cdn_frontdoor_origin_group_id  = azurerm_cdn_frontdoor_origin_group.main.id
  host_name                      = azurerm_linux_web_app.secondary["true"].default_hostname
  priority                       = var.switch_to_secondary_region ? 1 : 2
  weight                         = 500
  certificate_name_check_enabled = false
}

resource "azurerm_cdn_frontdoor_route" "main" {
  name                            = "${var.environment}-${local.app_name}-fd-route"
  cdn_frontdoor_origin_group_id   = azurerm_cdn_frontdoor_origin_group.main.id
  cdn_frontdoor_origin_ids        = concat([azurerm_cdn_frontdoor_origin.main.id], var.deploy_to_secondary_region ? [azurerm_cdn_frontdoor_origin.secondary["true"].id] : [])
  cdn_frontdoor_endpoint_id       = azurerm_cdn_frontdoor_endpoint.main.id
  cdn_frontdoor_custom_domain_ids = var.custom_domain != null ? [azurerm_cdn_frontdoor_custom_domain.main["true"].id] : []
  supported_protocols             = ["Http", "Https"]
  patterns_to_match               = ["/*"]
  https_redirect_enabled          = true

  depends_on = [azurerm_cdn_frontdoor_custom_domain.main]
}

# Associates the custom domain with the route so Front Door serves traffic for it.
resource "azurerm_cdn_frontdoor_custom_domain_association" "main" {
  for_each = var.custom_domain != null ? toset(["true"]) : []

  cdn_frontdoor_custom_domain_id = azurerm_cdn_frontdoor_custom_domain.main["true"].id
  cdn_frontdoor_route_ids        = [azurerm_cdn_frontdoor_route.main.id]
}

### DR-specific availability checks and alerting
resource "azurerm_application_insights_standard_web_test" "secondary" {
  for_each                = var.deploy_to_secondary_region ? toset(["true"]) : []
  name                    = "${var.environment}-${local.app_name}-avail-secondary"
  resource_group_name     = azurerm_resource_group.main.name
  location                = azurerm_resource_group.main.location
  application_insights_id = azurerm_application_insights.main.id
  geo_locations           = ["emea-nl-ams-azr", "emea-gb-db3-azr", "emea-se-sto-azr", "us-ca-sjc-azr", "apac-sg-sin-azr"]
  frequency               = 300
  timeout                 = 30
  enabled                 = true
  retry_enabled           = true

  request {
    url                              = "https://${azurerm_linux_web_app.secondary["true"].default_hostname}/health"
    http_verb                        = "GET"
    parse_dependent_requests_enabled = false
  }

  validation_rules {
    expected_status_code        = 200
    ssl_check_enabled           = true
    ssl_cert_remaining_lifetime = 7
  }

  tags = merge({ "Purpose" = "Availability check for ${var.environment} ${local.app_name} secondary DR origin" }, local.tags)
}

resource "azurerm_monitor_metric_alert" "availability_secondary" {
  for_each            = var.deploy_to_secondary_region ? toset(["true"]) : []
  name                = "${var.environment}-${local.app_name}-alert-avail-secondary"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_application_insights_standard_web_test.secondary["true"].id, azurerm_application_insights.main.id]
  description         = "Alert when secondary DR app availability drops below 100%"
  severity            = 1
  frequency           = "PT5M"
  window_size         = "PT15M"

  application_insights_web_test_location_availability_criteria {
    web_test_id           = azurerm_application_insights_standard_web_test.secondary["true"].id
    component_id          = azurerm_application_insights.main.id
    failed_location_count = 1
  }

  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }
}
