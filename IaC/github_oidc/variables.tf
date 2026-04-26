variable "environment" {
  type        = string
  description = "Specifies the environment used for naming the OIDC identity."
}

variable "app_name" {
  type        = string
  description = "Specifies the application name used for naming the OIDC identity."
}

variable "github_repo" {
  type        = string
  description = "GitHub repository in the format owner/repo. Used to scope federated identity credentials."
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to the OIDC application."
  default     = {}
}
