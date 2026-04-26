variable "mssql_server_fqdn" {
  type = string
}

variable "mssql_database" {
  type = string
}

variable "mssql_user" {
  type = string
}

variable "mssql_password" {
  type      = string
  sensitive = true

  validation {
    condition     = !strcontains(coalesce(var.mssql_password, "valid"), "$")
    error_message = "The mssql_password shouldn't contain special Bash characters (e.g. '$')."
  }
}

variable "mssql_user_roles" {
  type    = list(string)
  default = []
}

variable "mssql_user_table_grants" {
  type = list(object({
    table       = string
    permissions = list(string)
  }))
  default = []
}
