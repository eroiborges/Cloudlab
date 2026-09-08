locals {
  linux_virtual_machines = {
    hub = {
      name       = "vm-hub"
      private_ip = "10.0.0.10"
    }
    spoke = {
      name       = "vm-spoke"
      private_ip = "100.64.0.10"
    }
  }
}

resource "azurerm_network_security_group" "hosts" {
  for_each = local.linux_virtual_machines

  name                = "nsg-${each.key}-hosts"
  location            = azurerm_resource_group.rg-main.location
  resource_group_name = azurerm_resource_group.rg-main.name

  security_rule {
    name                       = "Allow-SSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "hosts" {
  for_each = local.linux_virtual_machines

  subnet_id                 = azurerm_subnet.hosts[each.key].id
  network_security_group_id = azurerm_network_security_group.hosts[each.key].id
}

resource "azurerm_public_ip" "linux_vm" {
  for_each = local.linux_virtual_machines

  name                = "pip-${each.value.name}"
  location            = azurerm_resource_group.rg-main.location
  resource_group_name = azurerm_resource_group.rg-main.name
  allocation_method   = "Static"
  sku                 = "Standard"

  lifecycle {
    ignore_changes  = [ip_tags]
    prevent_destroy = false
  }
}

resource "azurerm_network_interface" "linux_vm" {
  for_each = local.linux_virtual_machines

  name                = "nic-${each.value.name}"
  location            = azurerm_resource_group.rg-main.location
  resource_group_name = azurerm_resource_group.rg-main.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.hosts[each.key].id
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value.private_ip
    public_ip_address_id          = azurerm_public_ip.linux_vm[each.key].id
  }
}

resource "azurerm_linux_virtual_machine" "main" {
  for_each = local.linux_virtual_machines

  name                            = each.value.name
  location                        = azurerm_resource_group.rg-main.location
  resource_group_name             = azurerm_resource_group.rg-main.name
  size                            = "Standard_B2s"
  admin_username                  = var.vm_admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.linux_vm[each.key].id]

  admin_ssh_key {
    username   = var.vm_admin_username
    public_key = var.vm_ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }
}

output "linux_vm_public_ip_addresses" {
  description = "Public IP addresses of the Linux virtual machines."
  value = {
    for key, public_ip in azurerm_public_ip.linux_vm : key => public_ip.ip_address
  }
}