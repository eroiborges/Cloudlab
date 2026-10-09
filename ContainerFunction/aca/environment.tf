resource "azurerm_container_app_environment" "main" {
  name                           = local.environment_name
  location                       = var.handoff.azure.location
  resource_group_name            = var.handoff.azure.resource_group.name
  infrastructure_subnet_id       = var.handoff.network.subnets.aca.id
  internal_load_balancer_enabled = var.aca.environment.internal_load_balancer_enabled
  zone_redundancy_enabled        = var.aca.environment.zone_redundancy_enabled
  logs_destination               = var.aca.environment.logs_destination == "none" ? null : var.aca.environment.logs_destination

  workload_profile {
    name                  = var.aca.environment.workload_profile_name
    workload_profile_type = var.aca.environment.workload_profile_type
  }
}

output "environment" {
  description = "Azure Container Apps Environment deployed by this Terraform root."
  value = {
    id             = azurerm_container_app_environment.main.id
    name           = azurerm_container_app_environment.main.name
    default_domain = azurerm_container_app_environment.main.default_domain
    static_ip      = azurerm_container_app_environment.main.static_ip_address
  }
}
