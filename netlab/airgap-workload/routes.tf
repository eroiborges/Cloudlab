locals {
  rfc1918_routes = {
    rfc1918-10 = "10.0.0.0/8"
    rfc1918-172 = "172.16.0.0/12"
    rfc1918-192 = "192.168.0.0/16"
  }
}

resource "azurerm_route_table" "spoke" {
  name                = "rt-spoke-to-firewall"
  location            = azurerm_resource_group.rg-main.location
  resource_group_name = azurerm_resource_group.rg-main.name
}

resource "azurerm_route" "spoke_rfc1918" {
  for_each = local.rfc1918_routes

  name                   = each.key
  resource_group_name    = azurerm_resource_group.rg-main.name
  route_table_name       = azurerm_route_table.spoke.name
  address_prefix         = each.value
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = azurerm_firewall.spoke_hub.ip_configuration[0].private_ip_address
}

resource "azurerm_subnet_route_table_association" "spoke_hosts" {
  subnet_id      = azurerm_subnet.hosts["spoke"].id
  route_table_id = azurerm_route_table.spoke.id
}

resource "azurerm_route_table" "webapp" {
  name                = "rt-webapp-to-firewall"
  location            = azurerm_resource_group.rg-main.location
  resource_group_name = azurerm_resource_group.rg-main.name
}

resource "azurerm_route" "webapp_default" {
  name                   = "default-to-firewall"
  resource_group_name    = azurerm_resource_group.rg-main.name
  route_table_name       = azurerm_route_table.webapp.name
  address_prefix         = "0.0.0.0/0"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = azurerm_firewall.spoke_hub.ip_configuration[0].private_ip_address
}

resource "azurerm_subnet_route_table_association" "webapp" {
  subnet_id      = azurerm_subnet.webapp.id
  route_table_id = azurerm_route_table.webapp.id
}