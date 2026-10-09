resource "azurerm_federated_identity_credential" "producer" {
  name                      = var.aks.federation.producer_credential_name
  user_assigned_identity_id = var.handoff.managed_identities.producer.id
  audience                  = [var.aks.federation.audience]
  issuer                    = azurerm_kubernetes_cluster.main.oidc_issuer_url
  subject                   = "system:serviceaccount:${var.aks.kubernetes.namespace}:${var.aks.kubernetes.producer.service_account_name}"
}

resource "azurerm_federated_identity_credential" "consumer" {
  name                      = var.aks.federation.consumer_credential_name
  user_assigned_identity_id = var.handoff.managed_identities.consumer.id
  audience                  = [var.aks.federation.audience]
  issuer                    = azurerm_kubernetes_cluster.main.oidc_issuer_url
  subject                   = "system:serviceaccount:${var.aks.kubernetes.namespace}:${var.aks.kubernetes.consumer.service_account_name}"
}

resource "azurerm_federated_identity_credential" "keda_consumer" {
  name                      = var.aks.federation.keda_credential_name
  user_assigned_identity_id = var.handoff.managed_identities.consumer.id
  audience                  = [var.aks.federation.audience]
  issuer                    = azurerm_kubernetes_cluster.main.oidc_issuer_url
  subject                   = "system:serviceaccount:kube-system:keda-operator"
}
