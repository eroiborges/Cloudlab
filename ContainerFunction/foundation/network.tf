resource "azurerm_network_security_group" "azhosts" {
  name                = var.network.nsg_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_virtual_network" "main" {
  name                = var.network.vnet_name
  address_space       = var.network.address_space
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_subnet" "subnets" {
  for_each = var.network.subnets

  name                 = each.value.name
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [each.value.address_prefix]

  dynamic "delegation" {
    for_each = each.key == "acasubnet" ? [true] : []

    content {
      name = "Microsoft.App.environments"

      service_delegation {
        name    = "Microsoft.App/environments"
        actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
      }
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "azhosts" {
  subnet_id                 = azurerm_subnet.subnets["azhosts"].id
  network_security_group_id = azurerm_network_security_group.azhosts.id
}
