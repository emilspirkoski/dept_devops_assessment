variable "environment" {
  type        = string
  description = "Specifies the environment used for the project. Environment is then passed through specific backend for the tfstate and selected tfvars file."
}

variable "subscription_id" {
  type        = string
  description = "Specifies the value of the subscription."
}

variable "tenant_id" {
  type        = string
  description = "Specifies the value of the tenant."
}

variable "location" {
  type        = string
  description = "Specifies the location for the resources."
  default     = "westeurope"
}

variable "default_tags" {
  type        = map(string)
  description = "Specifies the tags for the resources."
}

variable "alert_email" {
  type        = string
  description = "Email address for monitoring alert notifications."
}

variable "deploy_to_secondary_region" {
  type        = bool
  description = "Deploys a secondary-region DR app instance and configures Front Door origin failover when true."
  default     = false
}

variable "switch_to_secondary_region" {
  type        = bool
  description = "Switches Front Door priority to route to secondary origin first. Requires deploy_to_secondary_region=true."
  default     = false

  validation {
    condition     = var.switch_to_secondary_region ? var.deploy_to_secondary_region : true
    error_message = "switch_to_secondary_region can only be true when deploy_to_secondary_region is true."
  }
}

variable "secondary_location" {
  type        = string
  description = "Secondary Azure region used for DR deployment when deploy_to_secondary_region is true."
  default     = "northeurope"
}

variable "github_actions_principal_object_id" {
  type        = string
  description = "Service principal object ID used by GitHub Actions OIDC identity for RBAC assignments on app resources."
  default     = null
}

variable "custom_domain" {
  type        = string
  description = "Custom domain hostname to associate with the Front Door endpoint (e.g. companyx.com). Leave null to use the auto-generated azurefd.net hostname."
  default     = null
}