resource "azurerm_public_ip" "firewall" {
  name                = "pip-fw-spokehub"
  location            = azurerm_resource_group.rg-main.location
  resource_group_name = azurerm_resource_group.rg-main.name
  allocation_method   = "Static"
  sku                 = "Standard"

  lifecycle {
    ignore_changes  = [ip_tags]
    prevent_destroy = false
  }
}

resource "azurerm_public_ip" "firewall_management" {
  name                = "pip-fw-spokehub-management"
  location            = azurerm_resource_group.rg-main.location
  resource_group_name = azurerm_resource_group.rg-main.name
  allocation_method   = "Static"
  sku                 = "Standard"

  lifecycle {
    ignore_changes  = [ip_tags]
    prevent_destroy = false
  }
}

resource "azurerm_firewall_policy" "spoke_hub" {
  name                = "fwpolicy-spokehub"
  location            = azurerm_resource_group.rg-main.location
  resource_group_name = azurerm_resource_group.rg-main.name
  sku                  = "Basic"
  private_ip_ranges    = ["255.255.255.255/32"]
}

resource "azurerm_firewall_policy_rule_collection_group" "default_network" {
  name               = "DefaultNetworkRuleCollectionGroup"
  firewall_policy_id = azurerm_firewall_policy.spoke_hub.id
  priority           = 200

  network_rule_collection {
    name     = "NETLAB"
    priority = 100
    action   = "Allow"

    rule {
      name                  = "AllowAll"
      protocols             = ["Any"]
      source_addresses      = ["*"]
      destination_addresses = ["*"]
      destination_ports     = ["*"]
    }
  }
}

resource "azurerm_firewall" "spoke_hub" {
  name                = "fw-spokehub"
  location            = azurerm_resource_group.rg-main.location
  resource_group_name = azurerm_resource_group.rg-main.name
  sku_name            = "AZFW_VNet"
  sku_tier            = "Basic"
  firewall_policy_id  = azurerm_firewall_policy.spoke_hub.id

  ip_configuration {
    name                 = "ipconfig-data"
    subnet_id            = azurerm_subnet.firewall.id
    public_ip_address_id = azurerm_public_ip.firewall.id
  }

  management_ip_configuration {
    name                 = "ipconfig-management"
    subnet_id            = azurerm_subnet.firewall_management.id
    public_ip_address_id = azurerm_public_ip.firewall_management.id
  }
}

output "firewall_private_ip_address" {
  description = "Private IP address of the Azure Firewall in SpokeHub."
  value       = azurerm_firewall.spoke_hub.ip_configuration[0].private_ip_address
}

output "firewall_public_ip_address" {
  description = "Public IP address used by the Azure Firewall."
  value       = azurerm_public_ip.firewall.ip_address
}