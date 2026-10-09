locals {
  consumer_image = "${var.handoff.container_registry.login_server}/${var.aca.consumer.image_repository}:${var.aca.consumer.image_tag}"

  consumer_environment_variables = [
    {
      name  = "AzureWebJobsSecretStorageType"
      value = "blob"
    },
    {
      name  = "AzureWebJobsStorage__blobServiceUri"
      value = "https://${var.handoff.storage.name}.blob.core.windows.net"
    },
    {
      name  = "AzureWebJobsStorage__queueServiceUri"
      value = "https://${var.handoff.storage.name}.queue.core.windows.net"
    },
    {
      name  = "AzureWebJobsStorage__tableServiceUri"
      value = "https://${var.handoff.storage.name}.table.core.windows.net"
    },
    {
      name  = "AzureWebJobsStorage__credential"
      value = "managedidentity"
    },
    {
      name  = "AzureWebJobsStorage__clientId"
      value = var.handoff.managed_identities.consumer.client_id
    },
    {
      name  = "ServiceBusConnection__fullyQualifiedNamespace"
      value = "${var.handoff.service_bus.namespace.name}.servicebus.windows.net"
    },
    {
      name  = "ServiceBusConnection__credential"
      value = "managedidentity"
    },
    {
      name  = "ServiceBusConnection__clientId"
      value = var.handoff.managed_identities.consumer.client_id
    }
  ]
}

resource "azapi_resource" "consumer" {
  type      = "Microsoft.App/containerApps@${var.aca.container_app_api_version}"
  name      = local.consumer_name
  parent_id = var.handoff.azure.resource_group.id
  location  = var.handoff.azure.location

  body = {
    kind = "functionapp"
    identity = {
      type = "UserAssigned"
      userAssignedIdentities = {
        (var.handoff.managed_identities.consumer.id) = {}
      }
    }
    properties = {
      managedEnvironmentId = azurerm_container_app_environment.main.id
      workloadProfileName  = var.aca.environment.workload_profile_name
      configuration = {
        activeRevisionsMode = var.aca.consumer.revision_mode
        registries = [
          {
            server   = var.handoff.container_registry.login_server
            identity = var.handoff.managed_identities.consumer.id
          }
        ]
        ingress = {
          external      = var.aca.consumer.ingress.external_enabled
          targetPort    = var.aca.consumer.ingress.target_port
          transport     = title(var.aca.consumer.ingress.transport)
          allowInsecure = var.aca.consumer.ingress.allow_insecure_connections
        }
      }
      template = {
        containers = [
          {
            name  = var.aca.consumer.container_name
            image = local.consumer_image
            env   = local.consumer_environment_variables
            resources = {
              cpu    = var.aca.consumer.cpu
              memory = var.aca.consumer.memory
            }
          }
        ]
        scale = {
          minReplicas = var.aca.consumer.min_replicas
          maxReplicas = var.aca.consumer.max_replicas
        }
      }
    }
  }

  response_export_values = [
    "properties.configuration.ingress.fqdn",
    "properties.latestRevisionName",
    "properties.provisioningState"
  ]
}

output "consumer" {
  description = "Service Bus-triggered Azure Function hosted on Azure Container Apps."
  value = {
    id                 = azapi_resource.consumer.id
    name               = azapi_resource.consumer.name
    image              = local.consumer_image
    fqdn               = azapi_resource.consumer.output.properties.configuration.ingress.fqdn
    latest_revision    = azapi_resource.consumer.output.properties.latestRevisionName
    provisioning_state = azapi_resource.consumer.output.properties.provisioningState
  }
}
