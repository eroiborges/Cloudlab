# Create a resource group using the generated random name
resource "azurerm_resource_group" "rg-main" {
  location = var.resource_group_location
  name     = var.main_resource_group_name
}
