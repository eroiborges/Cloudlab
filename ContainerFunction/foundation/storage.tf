locals {
  storage_skus = {
    Standard_LRS = {
      account_tier             = "Standard"
      account_replication_type = "LRS"
    }
    Standard_GRS = {
      account_tier             = "Standard"
      account_replication_type = "GRS"
    }
    Standard_RAGRS = {
      account_tier             = "Standard"
      account_replication_type = "RAGRS"
    }
    Standard_ZRS = {
      account_tier             = "Standard"
      account_replication_type = "ZRS"
    }
    Premium_LRS = {
      account_tier             = "Premium"
      account_replication_type = "LRS"
    }
  }
}

resource "azurerm_storage_account" "main" {
  name                      = local.storage_account_name
  resource_group_name       = azurerm_resource_group.main.name
  location                  = azurerm_resource_group.main.location
  account_tier              = local.storage_skus[var.storage.sku_name].account_tier
  account_replication_type  = local.storage_skus[var.storage.sku_name].account_replication_type
  min_tls_version           = var.storage.min_tls_version
  shared_access_key_enabled = var.storage.shared_access_key_enabled
}
