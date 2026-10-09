resource "azurerm_resource_group" "main" {
  name     = var.azure.resource_group_name
  location = var.azure.location
}
