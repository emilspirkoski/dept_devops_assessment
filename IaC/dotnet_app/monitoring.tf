resource "azurerm_log_analytics_workspace" "main" {
  name                = "${var.environment}-${local.app_name}-law"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_application_insights" "main" {
  name                = "${var.environment}-${local.app_name}-ai"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = "web"
  workspace_id        = azurerm_log_analytics_workspace.main.id
}

resource "azurerm_monitor_action_group" "main" {
  name                = "${var.environment}-${local.app_name}-ag"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "${local.app_name_short}AG"

  email_receiver {
    name                    = "DevTeamEmail"
    email_address           = var.alert_email
    use_common_alert_schema = true
  }
}

resource "azurerm_monitor_metric_alert" "http5xx" {
  name                = "${var.environment}-${local.app_name}-alert-http5xx"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_linux_web_app.main.id]
  description         = "Alert when HTTP 5xx responses exceed 10 in 15 minutes"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 10
  }

  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }
}

resource "azurerm_monitor_metric_alert" "cpu" {
  name                = "${var.environment}-${local.app_name}-alert-cpu"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_service_plan.main.id]
  description         = "Alert when App Service Plan CPU exceeds 80% over 15 minutes"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"

  criteria {
    metric_namespace = "Microsoft.Web/serverfarms"
    metric_name      = "CpuPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }
}

### Availability tests
# Standard (multi-step) web availability test hitting the primary app via Front Door.
# Probes run from 5 Azure edge locations every 5 minutes with a 30s timeout.
resource "azurerm_application_insights_standard_web_test" "primary" {
  name                    = "${var.environment}-${local.app_name}-avail-primary"
  resource_group_name     = azurerm_resource_group.main.name
  location                = azurerm_resource_group.main.location
  application_insights_id = azurerm_application_insights.main.id
  geo_locations           = ["emea-nl-ams-azr", "emea-gb-db3-azr", "emea-se-sto-azr", "us-ca-sjc-azr", "apac-sg-sin-azr"]
  frequency               = 300
  timeout                 = 30
  enabled                 = true
  retry_enabled           = true

  request {
    url                              = "https://${azurerm_cdn_frontdoor_endpoint.main.host_name}/health"
    http_verb                        = "GET"
    parse_dependent_requests_enabled = false
  }

  validation_rules {
    expected_status_code        = 200
    ssl_check_enabled           = true
    ssl_cert_remaining_lifetime = 7
  }

  tags = merge({ "Purpose" = "Availability check for ${var.environment} ${local.app_name} primary origin" }, local.tags)
}


# Alert fires when availability drops below 100% (at least one probe location fails).
resource "azurerm_monitor_metric_alert" "availability_primary" {
  name                = "${var.environment}-${local.app_name}-alert-avail-primary"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_application_insights_standard_web_test.primary.id, azurerm_application_insights.main.id]
  description         = "Alert when primary app availability drops below 100%"
  severity            = 1
  frequency           = "PT5M"
  window_size         = "PT15M"

  application_insights_web_test_location_availability_criteria {
    web_test_id           = azurerm_application_insights_standard_web_test.primary.id
    component_id          = azurerm_application_insights.main.id
    failed_location_count = 1
  }

  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }
}
