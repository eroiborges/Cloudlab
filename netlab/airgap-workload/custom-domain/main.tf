resource "azurerm_app_service_custom_hostname_binding" "custom_domain" {
  hostname            = var.handoff.custom_domain
  app_service_name    = var.handoff.azure.web_app_name
  resource_group_name = var.handoff.azure.resource_group_name

  lifecycle {
    precondition {
      condition     = var.dns_validation_confirmed
      error_message = "DNS validation is not confirmed. Create and verify the Route 53 TXT and CNAME records, then set dns_validation_confirmed=true."
    }

    ignore_changes = [ssl_state, thumbprint]
  }
}

resource "azurerm_app_service_certificate_binding" "custom_domain" {
  hostname_binding_id = azurerm_app_service_custom_hostname_binding.custom_domain.id
  certificate_id      = var.handoff.azure.certificate_id
  ssl_state           = "SniEnabled"
}

output "custom_domain_url" {
  description = "Private Web App URL secured by the uploaded public certificate."
  value       = "https://${var.handoff.custom_domain}"
}

output "certificate_thumbprint" {
  description = "Thumbprint reported by the completed App Service certificate binding."
  value       = azurerm_app_service_certificate_binding.custom_domain.thumbprint
}