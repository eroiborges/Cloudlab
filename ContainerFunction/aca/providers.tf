provider "azurerm" {
  features {}

  subscription_id = var.handoff.azure.subscription_id
  tenant_id       = var.handoff.azure.tenant_id
}

provider "azapi" {
  subscription_id  = var.handoff.azure.subscription_id
  tenant_id        = var.handoff.azure.tenant_id
  enable_preflight = true
}
