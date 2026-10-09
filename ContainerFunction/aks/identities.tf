resource "azurerm_user_assigned_identity" "control_plane" {
  name                = local.control_plane_identity_name
  location            = var.handoff.azure.location
  resource_group_name = var.handoff.azure.resource_group.name
  tags                = var.aks.cluster.tags
}

resource "azurerm_role_assignment" "control_plane_network" {
  scope                            = var.handoff.network.subnets.worker_aks.id
  role_definition_name             = var.aks.rbac.network_contributor_role_name
  principal_id                     = azurerm_user_assigned_identity.control_plane.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}
