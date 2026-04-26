locals {
  create_user_query = var.mssql_password != null ? "CREATE USER [${var.mssql_user}] WITH PASSWORD = '${var.mssql_password}'" : "CREATE USER [${var.mssql_user}] FROM EXTERNAL PROVIDER;"
}

resource "terraform_data" "main" {
  input = {
    mssql_server_fqdn = var.mssql_server_fqdn
    mssql_database    = var.mssql_database
    mssql_user        = var.mssql_user
  }

  provisioner "local-exec" {
    command     = <<EOD
    set -e

    az account get-access-token --resource https://database.windows.net --output tsv | cut -f 1 | tr -d '\n' | iconv -f ascii -t UTF-16LE > tokenFile

    sqlcmd -S ${self.input.mssql_server_fqdn} -d ${self.input.mssql_database} -G -P tokenFile -b -Q "
    ${local.create_user_query}
    "
    EOD
    interpreter = ["/bin/bash", "-c"]
  }

  provisioner "local-exec" {
    when        = destroy
    command     = <<EOD
    set -e

    az account get-access-token --resource https://database.windows.net --output tsv | cut -f 1 | tr -d '\n' | iconv -f ascii -t UTF-16LE > tokenFile

    sqlcmd -S ${self.input.mssql_server_fqdn} -d ${self.input.mssql_database} -G -P tokenFile -b -Q "
    DROP USER [${self.input.mssql_user}];
    "

    EOD
    interpreter = ["/bin/bash", "-c"]
  }
}

resource "terraform_data" "db_roles" {
  for_each = toset(var.mssql_user_roles)

  input = {
    mssql_server_fqdn = var.mssql_server_fqdn
    mssql_database    = var.mssql_database
    mssql_user        = var.mssql_user
    role              = each.key
  }

  provisioner "local-exec" {
    command     = <<EOD
    set -e

    az account get-access-token --resource https://database.windows.net --output tsv | cut -f 1 | tr -d '\n' | iconv -f ascii -t UTF-16LE > tokenFile

    sqlcmd -S ${self.input.mssql_server_fqdn} -d ${self.input.mssql_database} -G -P tokenFile -b -Q "
    ALTER ROLE [${self.input.role}] ADD MEMBER [${self.input.mssql_user}];
    "
    EOD
    interpreter = ["/bin/bash", "-c"]
  }

  provisioner "local-exec" {
    when        = destroy
    command     = <<EOD
    set -e

    az account get-access-token --resource https://database.windows.net --output tsv | cut -f 1 | tr -d '\n' | iconv -f ascii -t UTF-16LE > tokenFile

    sqlcmd -S ${self.input.mssql_server_fqdn} -d ${self.input.mssql_database} -G -P tokenFile -b -Q "
    ALTER ROLE [${self.input.role}] DROP MEMBER [${self.input.mssql_user}];
    "
    EOD
    interpreter = ["/bin/bash", "-c"]
  }

  depends_on = [
    terraform_data.main
  ]
}

resource "terraform_data" "table_grants" {
  for_each = merge([
    for table_grants in var.mssql_user_table_grants : {
      for permission in table_grants.permissions : "${permission} ON ${table_grants.table}" => {
        table      = table_grants.table
        permission = permission
      }
    }
  ]...)

  input = {
    mssql_server_fqdn = var.mssql_server_fqdn
    mssql_database    = var.mssql_database
    mssql_user        = var.mssql_user
    permission        = each.value.permission
    table             = each.value.table
  }

  provisioner "local-exec" {
    command     = <<EOD
    set -e

    az account get-access-token --resource https://database.windows.net --output tsv | cut -f 1 | tr -d '\n' | iconv -f ascii -t UTF-16LE > tokenFile

    sqlcmd -S ${self.input.mssql_server_fqdn} -d ${self.input.mssql_database} -G -P tokenFile -b -Q "
    GRANT ${self.input.permission} ON ${self.input.table} TO [${self.input.mssql_user}];

    "
    EOD
    interpreter = ["/bin/bash", "-c"]
  }

  provisioner "local-exec" {
    when        = destroy
    command     = <<EOD
    set -e

    az account get-access-token --resource https://database.windows.net --output tsv | cut -f 1 | tr -d '\n' | iconv -f ascii -t UTF-16LE > tokenFile

    sqlcmd -S ${self.input.mssql_server_fqdn} -d ${self.input.mssql_database} -G -P tokenFile -b -Q "
    REVOKE ${self.input.permission} ON ${self.input.table} TO [${self.input.mssql_user}];
    "
    EOD
    interpreter = ["/bin/bash", "-c"]
  }

  depends_on = [
    terraform_data.main
  ]
}
