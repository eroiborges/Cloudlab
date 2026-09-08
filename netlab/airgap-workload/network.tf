locals {
  virtual_networks = {
    hub = {
      name          = "HUB"
      address_space = ["10.0.0.0/24"]
      hosts_subnet  = "10.0.0.0/24"
    }
    spoke_hub = {
      name          = "SpokeHub"
      address_space = ["10.2.0.0/23"]
      hosts_subnet  = "10.2.0.0/26"
    }
    spoke = {
      name          = "Spoke"
      address_space = ["100.64.0.0/24"]
      hosts_subnet  = "100.64.0.0/27"
    }
  }

  spoke_subnet_prefixes = {
    hosts     = "100.64.0.0/27"
    webapp    = "100.64.0.32/27"
    reserved1 = "100.64.0.64/27"
    reserved2 = "100.64.0.96/27"
  }

  peerings = {
    hub_to_spoke_hub = {
      source = "hub"
      target = "spoke_hub"
    }
    spoke_hub_to_hub = {
      source = "spoke_hub"
      target = "hub"
    }
    spoke_hub_to_spoke = {
      source = "spoke_hub"
      target = "spoke"
    }
    spoke_to_spoke_hub = {
      source = "spoke"
      target = "spoke_hub"
    }
  }
}

resource "azurerm_virtual_network" "main" {
  for_each = local.virtual_networks

  name                = each.value.name
  location            = azurerm_resource_group.rg-main.location
  resource_group_name = azurerm_resource_group.rg-main.name
  address_space       = each.value.address_space
}

resource "azurerm_subnet" "hosts" {
  for_each = local.virtual_networks

  name                 = "hosts"
  resource_group_name  = azurerm_resource_group.rg-main.name
  virtual_network_name = azurerm_virtual_network.main[each.key].name
  address_prefixes     = [each.value.hosts_subnet]
}

resource "azurerm_subnet" "application_gateway" {
  name                 = "ApplicationGatewaySubnet"
  resource_group_name  = azurerm_resource_group.rg-main.name
  virtual_network_name = azurerm_virtual_network.main["spoke_hub"].name
  address_prefixes     = ["10.2.0.192/26"]

  delegation {
    name = "Microsoft.Network-applicationGateways"

    service_delegation {
      name    = "Microsoft.Network/applicationGateways"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_subnet" "firewall" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.rg-main.name
  virtual_network_name = azurerm_virtual_network.main["spoke_hub"].name
  address_prefixes     = ["10.2.0.64/26"]
}

resource "azurerm_subnet" "firewall_management" {
  name                 = "AzureFirewallManagementSubnet"
  resource_group_name  = azurerm_resource_group.rg-main.name
  virtual_network_name = azurerm_virtual_network.main["spoke_hub"].name
  address_prefixes     = ["10.2.0.128/26"]
}

resource "azurerm_subnet" "webapp" {
  name                 = "webapp"
  resource_group_name  = azurerm_resource_group.rg-main.name
  virtual_network_name = azurerm_virtual_network.main["spoke"].name
  address_prefixes     = [local.spoke_subnet_prefixes.webapp]

  delegation {
    name = "Microsoft.Web-serverFarms"

    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

resource "azurerm_subnet" "private_endpoints" {
  name                 = "PESubnet"
  resource_group_name  = azurerm_resource_group.rg-main.name
  virtual_network_name = azurerm_virtual_network.main["spoke_hub"].name
  address_prefixes     = ["10.2.1.0/25"]
}

resource "azurerm_virtual_network_peering" "main" {
  for_each = local.peerings

  name                      = "${local.virtual_networks[each.value.source].name}-to-${local.virtual_networks[each.value.target].name}"
  resource_group_name       = azurerm_resource_group.rg-main.name
  virtual_network_name      = azurerm_virtual_network.main[each.value.source].name
  remote_virtual_network_id = azurerm_virtual_network.main[each.value.target].id

  allow_virtual_network_access = true
  allow_forwarded_traffic       = true
}