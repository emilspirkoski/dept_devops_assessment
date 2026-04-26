variable "environment" {
  type        = string
  description = "Specifies the environment used for the project. Environment is then passed through specific backend for the tfstate and selected tfvars file."
}

variable "github_repo" {
  type        = string
  description = "GitHub repository in the format owner/repo. Used to scope OIDC federated identity credentials."
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

variable "custom_domain" {
  type        = string
  description = "Custom domain hostname to associate with the Front Door endpoint (e.g. companyx.com). Leave null to use the auto-generated azurefd.net hostname."
  default     = null
}