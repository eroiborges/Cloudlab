resource "azurerm_container_registry" "main" {
  name                                         = local.container_registry_name
  resource_group_name                          = azurerm_resource_group.main.name
  location                                     = azurerm_resource_group.main.location
  sku                                          = var.container_registry.sku
  admin_enabled                                = var.container_registry.admin_enabled
  azuread_authentication_as_arm_policy_enabled = var.container_registry.arm_audience_authentication_enabled
}
