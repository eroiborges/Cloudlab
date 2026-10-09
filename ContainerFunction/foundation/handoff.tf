locals {
  handoff_payload = {
    handoff = {
      schema_version = 2
      generated_by   = "container-function-foundation"

      azure = {
        subscription_id = var.azure.subscription_id
        tenant_id       = data.azurerm_client_config.current.tenant_id
        location        = azurerm_resource_group.main.location
        resource_group = {
          id   = azurerm_resource_group.main.id
          name = azurerm_resource_group.main.name
        }
      }

      naming = {
        base_name = local.base_name
      }

      managed_identities = {
        producer = {
          id           = azurerm_user_assigned_identity.producer.id
          name         = azurerm_user_assigned_identity.producer.name
          client_id    = azurerm_user_assigned_identity.producer.client_id
          principal_id = azurerm_user_assigned_identity.producer.principal_id
        }
        consumer = {
          id           = azurerm_user_assigned_identity.consumer.id
          name         = azurerm_user_assigned_identity.consumer.name
          client_id    = azurerm_user_assigned_identity.consumer.client_id
          principal_id = azurerm_user_assigned_identity.consumer.principal_id
        }
      }

      network = {
        vnet = {
          id   = azurerm_virtual_network.main.id
          name = azurerm_virtual_network.main.name
        }
        subnets = {
          azhosts = {
            id             = azurerm_subnet.subnets["azhosts"].id
            name           = azurerm_subnet.subnets["azhosts"].name
            address_prefix = var.network.subnets.azhosts.address_prefix
          }
          pgsqlnet = {
            id             = azurerm_subnet.subnets["pgsqlnet"].id
            name           = azurerm_subnet.subnets["pgsqlnet"].name
            address_prefix = var.network.subnets.pgsqlnet.address_prefix
          }
          aca = {
            id             = azurerm_subnet.subnets["acasubnet"].id
            name           = azurerm_subnet.subnets["acasubnet"].name
            address_prefix = var.network.subnets.acasubnet.address_prefix
          }
          worker_aks = {
            id             = azurerm_subnet.subnets["worker_aks"].id
            name           = azurerm_subnet.subnets["worker_aks"].name
            address_prefix = var.network.subnets.worker_aks.address_prefix
          }
        }
      }

      storage = {
        id   = azurerm_storage_account.main.id
        name = azurerm_storage_account.main.name
      }

      key_vault = {
        id   = azurerm_key_vault.main.id
        name = azurerm_key_vault.main.name
        uri  = azurerm_key_vault.main.vault_uri
      }

      service_bus = {
        namespace = {
          id       = azurerm_servicebus_namespace.main.id
          name     = azurerm_servicebus_namespace.main.name
          endpoint = azurerm_servicebus_namespace.main.endpoint
        }
        queue = {
          id   = azurerm_servicebus_queue.main.id
          name = azurerm_servicebus_queue.main.name
        }
      }

      container_registry = {
        id           = azurerm_container_registry.main.id
        name         = azurerm_container_registry.main.name
        login_server = azurerm_container_registry.main.login_server
      }
    }
  }
}

resource "local_file" "aca_handoff" {
  filename        = "${path.module}/../aca/base.auto.tfvars.json"
  content         = jsonencode(local.handoff_payload)
  file_permission = "0600"
}

resource "local_file" "aks_handoff" {
  filename        = "${path.module}/../aks/base.auto.tfvars.json"
  content         = jsonencode(local.handoff_payload)
  file_permission = "0600"
}

output "handoff" {
  description = "Non-secret infrastructure contract consumed by the ACA and AKS Terraform roots."
  value       = local.handoff_payload.handoff
}

output "handoff_files" {
  description = "Local auto.tfvars.json files generated for the ACA and AKS Terraform roots."
  value = {
    aca = local_file.aca_handoff.filename
    aks = local_file.aks_handoff.filename
  }
}
