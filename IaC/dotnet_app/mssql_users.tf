module "dev_team_mssql_user" {
  for_each = var.environment == "test" ? toset(["true"]) : []
  source   = "./mssql_users"

  mssql_server_fqdn = azurerm_mssql_server.main.fully_qualified_domain_name
  mssql_database    = "master"
  mssql_user        = local.dev_team_db_readers
  mssql_password    = null
}