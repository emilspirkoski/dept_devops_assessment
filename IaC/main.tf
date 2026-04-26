terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
  }
}

provider "azurerm" {
  features {}
}

provider "azuread" {}

data "azurerm_subscription" "current" {}

locals {
  tags = {
    "Environment" = var.environment
    "Project"     = "DEPT DevOps Assessment"
  }
}

module "github_oidc" {
  source = "./github_oidc"

  environment = var.environment
  app_name    = "dotnet-app"
  github_repo = var.github_repo
  tags        = local.tags
}

module "dotnet_app" {
  source                             = "./dotnet_app"
  environment                        = var.environment
  subscription_id                    = data.azurerm_subscription.current.subscription_id
  tenant_id                          = data.azurerm_subscription.current.tenant_id
  default_tags                       = local.tags
  alert_email                        = var.alert_email
  deploy_to_secondary_region         = var.deploy_to_secondary_region
  switch_to_secondary_region         = var.switch_to_secondary_region
  secondary_location                 = var.secondary_location
  github_actions_principal_object_id = module.github_oidc.service_principal_object_id
  custom_domain                      = var.custom_domain

  depends_on = [module.github_oidc]
}