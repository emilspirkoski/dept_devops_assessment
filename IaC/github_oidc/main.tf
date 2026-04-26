# GitHub Actions OIDC service principal for Terraform pipelines.
# Creates one identity per environment with two federated credentials:
#   - plan job  -> environment: {env}
#   - apply job -> environment: {env}-deploy

resource "azuread_application" "main" {
  display_name = "${var.environment}-${var.app_name}-github-sp"
  tags         = values(var.tags)
}

resource "azuread_service_principal" "main" {
  client_id = azuread_application.main.client_id
}

# Federated credential for the plan job (environment: {env})
resource "azuread_application_federated_identity_credential" "plan" {
  application_id = azuread_application.main.id
  display_name   = "${var.environment}-plan"
  description    = "GitHub Actions plan job for ${var.environment}"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_repo}:environment:${var.environment}"
}

# Federated credential for the apply job (environment: {env}-deploy)
resource "azuread_application_federated_identity_credential" "deploy" {
  application_id = azuread_application.main.id
  display_name   = "${var.environment}-deploy"
  description    = "GitHub Actions apply job for ${var.environment}"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_repo}:environment:${var.environment}-deploy"
}

# Storage Blob Data Contributor on the tfstate storage account so the pipeline
# can read and write the Terraform state file.
data "azurerm_storage_account" "tfstate" {
  name                = "${var.environment}dotnettfstatesa"
  resource_group_name = "${var.environment}-dotnet-tfstate-rg"
}

resource "azurerm_role_assignment" "tfstate_blob" {
  scope                = data.azurerm_storage_account.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azuread_service_principal.main.object_id
}
