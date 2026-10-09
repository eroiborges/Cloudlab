resource "azurerm_role_assignment" "kubelet_acr_pull" {
  scope                            = var.handoff.container_registry.id
  role_definition_name             = var.aks.rbac.acr_pull_role_name
  principal_id                     = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "producer_key_vault_secrets" {
  scope                            = var.handoff.key_vault.id
  role_definition_name             = var.aks.rbac.key_vault_secrets_officer_role_name
  principal_id                     = var.handoff.managed_identities.producer.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}
