output "client_id" {
  description = "Client ID of the OIDC service principal. Store as GitHub secret {ENV}_CLIENT_ID."
  value       = azuread_application.main.client_id
}

output "service_principal_object_id" {
  description = "Object ID of the service principal."
  value       = azuread_service_principal.main.object_id
}
