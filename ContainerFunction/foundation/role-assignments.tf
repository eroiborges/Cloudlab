locals {
  role_assignments = {
    producer_acr_pull = {
      principal_id         = azurerm_user_assigned_identity.producer.principal_id
      role_definition_name = var.rbac.acr_pull_role_name
      scope                = azurerm_container_registry.main.id
    }
    producer_storage_blob = {
      principal_id         = azurerm_user_assigned_identity.producer.principal_id
      role_definition_name = var.rbac.storage_blob_data_role_name
      scope                = azurerm_storage_account.main.id
    }
    producer_storage_queue = {
      principal_id         = azurerm_user_assigned_identity.producer.principal_id
      role_definition_name = var.rbac.storage_queue_data_role_name
      scope                = azurerm_storage_account.main.id
    }
    producer_storage_table = {
      principal_id         = azurerm_user_assigned_identity.producer.principal_id
      role_definition_name = var.rbac.storage_table_data_role_name
      scope                = azurerm_storage_account.main.id
    }
    producer_service_bus_sender = {
      principal_id         = azurerm_user_assigned_identity.producer.principal_id
      role_definition_name = var.rbac.service_bus_data_sender_role_name
      scope                = azurerm_servicebus_queue.main.id
    }
    consumer_acr_pull = {
      principal_id         = azurerm_user_assigned_identity.consumer.principal_id
      role_definition_name = var.rbac.acr_pull_role_name
      scope                = azurerm_container_registry.main.id
    }
    consumer_storage_blob = {
      principal_id         = azurerm_user_assigned_identity.consumer.principal_id
      role_definition_name = var.rbac.storage_blob_data_role_name
      scope                = azurerm_storage_account.main.id
    }
    consumer_storage_queue = {
      principal_id         = azurerm_user_assigned_identity.consumer.principal_id
      role_definition_name = var.rbac.storage_queue_data_role_name
      scope                = azurerm_storage_account.main.id
    }
    consumer_storage_table = {
      principal_id         = azurerm_user_assigned_identity.consumer.principal_id
      role_definition_name = var.rbac.storage_table_data_role_name
      scope                = azurerm_storage_account.main.id
    }
    consumer_service_bus_receiver = {
      principal_id         = azurerm_user_assigned_identity.consumer.principal_id
      role_definition_name = var.rbac.service_bus_data_receiver_role_name
      scope                = azurerm_servicebus_queue.main.id
    }
  }
}

resource "azurerm_role_assignment" "managed_identities" {
  for_each = local.role_assignments

  scope                            = each.value.scope
  role_definition_name             = each.value.role_definition_name
  principal_id                     = each.value.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}
