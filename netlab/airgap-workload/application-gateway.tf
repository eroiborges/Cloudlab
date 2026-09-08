locals {
  application_gateway = {
    name                 = "agw-${var.workload_name}-private"
    frontend_ip          = "10.2.0.196"
    frontend_ip_name     = "frontend-private"
    frontend_port_name   = "frontend-http-80"
    https_port_name      = "frontend-https-443"
    listener_name        = "listener-http-private"
    https_listener_name  = "listener-https-private"
    ssl_certificate_name = "ssl-appdemo-eroicloud"
    backend_pool_name    = "backend-webapp"
    backend_setting_name = "backend-http-webapp"
    probe_name           = "probe-http-webapp"
    routing_rule_name    = "rule-http-webapp"
    https_rule_name      = "rule-https-webapp"
  }
}

resource "azurerm_application_gateway" "private" {
  name                = local.application_gateway.name
  location            = azurerm_resource_group.rg-main.location
  resource_group_name = azurerm_resource_group.rg-main.name

  sku {
    name = "Standard_v2"
    tier = "Standard_v2"
  }

  autoscale_configuration {
    min_capacity = 0
    max_capacity = 2
  }

  gateway_ip_configuration {
    name      = "gateway-ip-configuration"
    subnet_id = azurerm_subnet.application_gateway.id
  }

  frontend_ip_configuration {
    name                          = local.application_gateway.frontend_ip_name
    private_ip_address            = local.application_gateway.frontend_ip
    private_ip_address_allocation = "Static"
    subnet_id                     = azurerm_subnet.application_gateway.id
  }

  frontend_port {
    name = local.application_gateway.frontend_port_name
    port = 80
  }

  frontend_port {
    name = local.application_gateway.https_port_name
    port = 443
  }

  ssl_certificate {
    name     = local.application_gateway.ssl_certificate_name
    data     = filebase64("${path.module}/${var.certificate_pfx_path}")
    password = var.certificate_pfx_password
  }

  backend_address_pool {
    name  = local.application_gateway.backend_pool_name
    fqdns = [azurerm_linux_web_app.webapp.default_hostname]
  }

  probe {
    name                                      = local.application_gateway.probe_name
    protocol                                  = "Https"
    path                                      = "/"
    interval                                  = 30
    timeout                                   = 30
    unhealthy_threshold                       = 3
    pick_host_name_from_backend_http_settings = true

    match {
      status_code = ["200-399"]
    }
  }

  backend_http_settings {
    name                                = local.application_gateway.backend_setting_name
    cookie_based_affinity               = "Disabled"
    port                                = 443
    protocol                            = "Https"
    request_timeout                     = 30
    probe_name                          = local.application_gateway.probe_name
    pick_host_name_from_backend_address = true
  }

  http_listener {
    name                           = local.application_gateway.listener_name
    frontend_ip_configuration_name = local.application_gateway.frontend_ip_name
    frontend_port_name             = local.application_gateway.frontend_port_name
    protocol                       = "Http"
  }

  http_listener {
    name                           = local.application_gateway.https_listener_name
    frontend_ip_configuration_name = local.application_gateway.frontend_ip_name
    frontend_port_name             = local.application_gateway.https_port_name
    protocol                       = "Https"
    host_name                      = var.custom_domain_name
    ssl_certificate_name           = local.application_gateway.ssl_certificate_name
  }

  request_routing_rule {
    name                       = local.application_gateway.routing_rule_name
    priority                   = 100
    rule_type                  = "Basic"
    http_listener_name         = local.application_gateway.listener_name
    backend_address_pool_name  = local.application_gateway.backend_pool_name
    backend_http_settings_name = local.application_gateway.backend_setting_name
  }

  request_routing_rule {
    name                       = local.application_gateway.https_rule_name
    priority                   = 110
    rule_type                  = "Basic"
    http_listener_name         = local.application_gateway.https_listener_name
    backend_address_pool_name  = local.application_gateway.backend_pool_name
    backend_http_settings_name = local.application_gateway.backend_setting_name
  }

  depends_on = [
    azurerm_private_endpoint.webapp,
    azurerm_private_dns_zone_virtual_network_link.webapp_spoke_hub
  ]
}

output "application_gateway_private_ip" {
  description = "Private frontend IP address of the Application Gateway."
  value       = local.application_gateway.frontend_ip
}