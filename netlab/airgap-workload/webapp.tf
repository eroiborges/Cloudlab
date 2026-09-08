resource "random_string" "web_app_suffix" {
  length  = 6
  upper   = false
  special = false
}

resource "azurerm_service_plan" "webapp" {
  name                = "asp-${var.workload_name}-p1v3"
  location            = azurerm_resource_group.rg-main.location
  resource_group_name = azurerm_resource_group.rg-main.name
  os_type             = "Linux"
  sku_name            = "P1v3"
}

resource "azurerm_linux_web_app" "webapp" {
  name                = "app-${var.workload_name}-${random_string.web_app_suffix.result}"
  location            = azurerm_resource_group.rg-main.location
  resource_group_name = azurerm_resource_group.rg-main.name
  service_plan_id     = azurerm_service_plan.webapp.id

  public_network_access_enabled = false
  virtual_network_subnet_id     = azurerm_subnet.webapp.id

  site_config {
    always_on = true
  }
}

resource "azurerm_app_service_certificate" "custom_domain" {
  name                = "cert-${replace(var.custom_domain_name, ".", "-")}"
  resource_group_name = azurerm_resource_group.rg-main.name
  location            = azurerm_resource_group.rg-main.location
  app_service_plan_id = azurerm_service_plan.webapp.id
  pfx_blob            = filebase64("${path.module}/${var.certificate_pfx_path}")
  password            = var.certificate_pfx_password
}

resource "azapi_update_resource" "webapp_outbound_routing" {
  type        = "Microsoft.Web/sites@2024-11-01"
  resource_id = azurerm_linux_web_app.webapp.id

  depends_on = [azurerm_subnet_route_table_association.webapp]

  body = {
    properties = {
      outboundVnetRouting = {
        allTraffic = true
      }
    }
  }
}

resource "azurerm_private_dns_zone" "webapp" {
  name                = "privatelink.azurewebsites.net"
  resource_group_name = azurerm_resource_group.rg-main.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "webapp_hub" {
  name                  = "link-webapp-hub"
  resource_group_name   = azurerm_resource_group.rg-main.name
  private_dns_zone_name = azurerm_private_dns_zone.webapp.name
  virtual_network_id    = azurerm_virtual_network.main["hub"].id
}

resource "azurerm_private_dns_zone_virtual_network_link" "webapp_spoke_hub" {
  name                  = "link-webapp-spokehub"
  resource_group_name   = azurerm_resource_group.rg-main.name
  private_dns_zone_name = azurerm_private_dns_zone.webapp.name
  virtual_network_id    = azurerm_virtual_network.main["spoke_hub"].id
}

resource "azurerm_private_dns_zone_virtual_network_link" "webapp_spoke" {
  name                  = "link-webapp-spoke"
  resource_group_name   = azurerm_resource_group.rg-main.name
  private_dns_zone_name = azurerm_private_dns_zone.webapp.name
  virtual_network_id    = azurerm_virtual_network.main["spoke"].id
}

resource "azurerm_private_endpoint" "webapp" {
  name                = "pe-${azurerm_linux_web_app.webapp.name}"
  location            = azurerm_resource_group.rg-main.location
  resource_group_name = azurerm_resource_group.rg-main.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "psc-${azurerm_linux_web_app.webapp.name}"
    private_connection_resource_id = azurerm_linux_web_app.webapp.id
    subresource_names              = ["sites"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "webapp-private-dns"
    private_dns_zone_ids = [azurerm_private_dns_zone.webapp.id]
  }
}

output "web_app_name" {
  description = "Globally unique name of the Linux Web App."
  value       = azurerm_linux_web_app.webapp.name
}

output "web_app_private_endpoint_ip" {
  description = "Private IP address of the Web App private endpoint in SpokeHub."
  value       = azurerm_private_endpoint.webapp.private_service_connection[0].private_ip_address
}

locals {
  custom_domain_relative_name = trimsuffix(var.custom_domain_name, ".eroicloud.com.br")
  custom_domain_handoff = {
    handoff = {
      schema_version = 1
      generated_by   = "azure-webapp-terraform"
      custom_domain  = var.custom_domain_name
      azure = {
        resource_group_name = azurerm_resource_group.rg-main.name
        web_app_name        = azurerm_linux_web_app.webapp.name
        default_hostname    = azurerm_linux_web_app.webapp.default_hostname
        certificate_id      = nonsensitive(azurerm_app_service_certificate.custom_domain.id)
      }
      route53 = {
        public_zone_name = "eroicloud.com.br"
        records = [
          {
            purpose = "app-service-domain-verification"
            name    = "asuid.${local.custom_domain_relative_name}"
            fqdn    = "asuid.${var.custom_domain_name}"
            type    = "TXT"
            ttl     = 300
            values  = [azurerm_linux_web_app.webapp.custom_domain_verification_id]
          },
          {
            purpose = "app-service-routing"
            name    = local.custom_domain_relative_name
            fqdn    = var.custom_domain_name
            type    = "CNAME"
            ttl     = 300
            values  = [azurerm_linux_web_app.webapp.default_hostname]
          }
        ]
      }
    }
  }
}

resource "local_file" "custom_domain_handoff" {
  filename        = "${path.module}/custom-domain/pilot.auto.tfvars.json"
  content         = jsonencode(nonsensitive(local.custom_domain_handoff))
  file_permission = "0600"
}

output "custom_domain_handoff_file" {
  description = "Local JSON artifact that simulates the pipeline handoff."
  value       = local_file.custom_domain_handoff.filename
}