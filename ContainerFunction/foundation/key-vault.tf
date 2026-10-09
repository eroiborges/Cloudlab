data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "main" {
  name                       = local.key_vault_name
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = var.key_vault.sku_name
  rbac_authorization_enabled = var.key_vault.rbac_authorization_enabled
  soft_delete_retention_days = var.key_vault.retention_days
}
