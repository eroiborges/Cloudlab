locals {
  producer_image = "${var.handoff.container_registry.login_server}/${var.aca.producer.image_repository}:${var.aca.producer.image_tag}"

  producer_environment_variables = [
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
      value = var.handoff.managed_identities.producer.client_id
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
      value = var.handoff.managed_identities.producer.client_id
    }
  ]
}

resource "azapi_resource" "producer" {
  type      = "Microsoft.App/containerApps@${var.aca.container_app_api_version}"
  name      = local.producer_name
  parent_id = var.handoff.azure.resource_group.id
  location  = var.handoff.azure.location

  body = {
    kind = "functionapp"
    identity = {
      type = "UserAssigned"
      userAssignedIdentities = {
        (var.handoff.managed_identities.producer.id) = {}
      }
    }
    properties = {
      managedEnvironmentId = azurerm_container_app_environment.main.id
      workloadProfileName  = var.aca.environment.workload_profile_name
      configuration = {
        activeRevisionsMode = var.aca.producer.revision_mode
        registries = [
          {
            server   = var.handoff.container_registry.login_server
            identity = var.handoff.managed_identities.producer.id
          }
        ]
        ingress = {
          external      = var.aca.producer.ingress.external_enabled
          targetPort    = var.aca.producer.ingress.target_port
          transport     = title(var.aca.producer.ingress.transport)
          allowInsecure = var.aca.producer.ingress.allow_insecure_connections
          corsPolicy = {
            allowedOrigins   = var.aca.producer.cors.allowed_origins
            allowedMethods   = var.aca.producer.cors.allowed_methods
            allowedHeaders   = var.aca.producer.cors.allowed_headers
            exposeHeaders    = var.aca.producer.cors.exposed_headers
            allowCredentials = var.aca.producer.cors.allow_credentials_enabled
            maxAge           = var.aca.producer.cors.max_age_in_seconds
          }
        }
      }
      template = {
        containers = [
          {
            name  = var.aca.producer.container_name
            image = local.producer_image
            env   = local.producer_environment_variables
            resources = {
              cpu    = var.aca.producer.cpu
              memory = var.aca.producer.memory
            }
          }
        ]
        scale = {
          minReplicas = var.aca.producer.min_replicas
          maxReplicas = var.aca.producer.max_replicas
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

output "producer" {
  description = "HTTP-triggered Azure Function hosted on Azure Container Apps."
  value = {
    id                 = azapi_resource.producer.id
    name               = azapi_resource.producer.name
    image              = local.producer_image
    fqdn               = azapi_resource.producer.output.properties.configuration.ingress.fqdn
    latest_revision    = azapi_resource.producer.output.properties.latestRevisionName
    provisioning_state = azapi_resource.producer.output.properties.provisioningState
  }
}
