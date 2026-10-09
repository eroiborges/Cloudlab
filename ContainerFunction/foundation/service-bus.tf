resource "azurerm_servicebus_namespace" "main" {
  name                          = local.service_bus_namespace_name
  location                      = azurerm_resource_group.main.location
  resource_group_name           = azurerm_resource_group.main.name
  sku                           = var.service_bus.sku
  public_network_access_enabled = var.service_bus.public_network_access_enabled
}

resource "azurerm_servicebus_queue" "main" {
  name         = var.service_bus.queue_name
  namespace_id = azurerm_servicebus_namespace.main.id
}
