variable "azure" {
  description = "Azure subscription, resource group, and region used by the base deployment."

  type = object({
    subscription_id     = string
    resource_group_name = string
    location            = string
  })

  nullable = false

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.azure.subscription_id))
    error_message = "azure.subscription_id must be a valid Azure subscription UUID."
  }

  validation {
    condition = (
      length(var.azure.resource_group_name) >= 1 &&
      length(var.azure.resource_group_name) <= 90 &&
      can(regex("^[A-Za-z0-9_().-]+$", var.azure.resource_group_name)) &&
      !endswith(var.azure.resource_group_name, ".")
    )
    error_message = "azure.resource_group_name must be 1-90 characters, use only Azure-supported characters, and not end with a period."
  }

  validation {
    condition     = length(trimspace(var.azure.location)) > 0
    error_message = "azure.location must not be empty."
  }
}

variable "naming" {
  description = "Parameters used to generate globally unique resource names."

  type = object({
    base_prefix        = string
    random_length      = number
    key_vault_prefix   = string
    service_bus_prefix = string
  })

  nullable = false

  validation {
    condition     = can(regex("^[a-z0-9]+$", var.naming.base_prefix))
    error_message = "naming.base_prefix must contain only lowercase letters and numbers."
  }

  validation {
    condition     = var.naming.random_length >= 1 && floor(var.naming.random_length) == var.naming.random_length
    error_message = "naming.random_length must be a positive whole number."
  }

  validation {
    condition = (
      length(var.naming.base_prefix) + var.naming.random_length >= 5 &&
      length(var.naming.base_prefix) + var.naming.random_length <= 24
    )
    error_message = "The generated base name must be 5-24 characters to satisfy Storage Account and Container Registry limits."
  }

  validation {
    condition = (
      can(regex("^[a-z][a-z0-9-]*-$", var.naming.key_vault_prefix)) &&
      length(var.naming.key_vault_prefix) + length(var.naming.base_prefix) + var.naming.random_length <= 24
    )
    error_message = "naming.key_vault_prefix must start with a letter, end with a hyphen, and keep the generated Key Vault name within 24 characters."
  }

  validation {
    condition = (
      can(regex("^[a-z][a-z0-9-]*-$", var.naming.service_bus_prefix)) &&
      length(var.naming.service_bus_prefix) + length(var.naming.base_prefix) + var.naming.random_length <= 50
    )
    error_message = "naming.service_bus_prefix must start with a letter, end with a hyphen, and keep the generated Service Bus namespace name within 50 characters."
  }
}

variable "managed_identities" {
  description = "Names of the producer and consumer user-assigned managed identities."

  type = object({
    producer = object({
      name_prefix = string
    })
    consumer = object({
      name_prefix = string
    })
  })

  nullable = false

  validation {
    condition = alltrue([
      for identity in values(var.managed_identities) :
      can(regex("^[A-Za-z0-9][A-Za-z0-9_-]*-$", identity.name_prefix))
    ])
    error_message = "Each managed identity prefix must start with an alphanumeric character, contain only alphanumeric characters, hyphens, or underscores, and end with a hyphen."
  }

  validation {
    condition = alltrue([
      for identity in values(var.managed_identities) :
      length(identity.name_prefix) + length(var.naming.base_prefix) + var.naming.random_length <= 128
    ])
    error_message = "Each generated managed identity name must be at most 128 characters."
  }

  validation {
    condition     = var.managed_identities.producer.name_prefix != var.managed_identities.consumer.name_prefix
    error_message = "Producer and consumer managed identity prefixes must be different."
  }
}

variable "rbac" {
  description = "Least-privilege built-in roles assigned to the producer and consumer managed identities."

  type = object({
    acr_pull_role_name                  = string
    storage_blob_data_role_name         = string
    storage_queue_data_role_name        = string
    storage_table_data_role_name        = string
    service_bus_data_sender_role_name   = string
    service_bus_data_receiver_role_name = string
  })

  nullable = false

  validation {
    condition = (
      var.rbac.acr_pull_role_name == "AcrPull" &&
      var.rbac.storage_blob_data_role_name == "Storage Blob Data Owner" &&
      var.rbac.storage_queue_data_role_name == "Storage Queue Data Contributor" &&
      var.rbac.storage_table_data_role_name == "Storage Table Data Contributor" &&
      var.rbac.service_bus_data_sender_role_name == "Azure Service Bus Data Sender" &&
      var.rbac.service_bus_data_receiver_role_name == "Azure Service Bus Data Receiver"
    )
    error_message = "The RBAC roles must match the approved least-privilege producer and consumer role matrix."
  }
}

variable "network" {
  description = "Virtual network, NSG, and subnet configuration."

  type = object({
    vnet_name     = string
    address_space = list(string)
    nsg_name      = string
    subnets = object({
      azhosts = object({
        name           = string
        address_prefix = string
      })
      pgsqlnet = object({
        name           = string
        address_prefix = string
      })
      acasubnet = object({
        name           = string
        address_prefix = string
      })
      worker_aks = object({
        name           = string
        address_prefix = string
      })
    })
  })

  nullable = false

  validation {
    condition     = length(var.network.vnet_name) >= 2 && length(var.network.vnet_name) <= 64
    error_message = "network.vnet_name must be 2-64 characters."
  }

  validation {
    condition     = length(var.network.nsg_name) >= 1 && length(var.network.nsg_name) <= 80
    error_message = "network.nsg_name must be 1-80 characters."
  }

  validation {
    condition = alltrue([
      for cidr in concat(
        var.network.address_space,
        [for subnet in values(var.network.subnets) : subnet.address_prefix]
      ) : can(cidrnetmask(cidr))
    ])
    error_message = "Every network address space and subnet address prefix must be valid CIDR notation."
  }

  validation {
    condition = alltrue([
      for subnet in values(var.network.subnets) :
      can(regex("^[A-Za-z0-9][A-Za-z0-9_.-]{0,78}[A-Za-z0-9_]$|^[A-Za-z0-9]$", subnet.name))
    ])
    error_message = "Each subnet name must be 1-80 characters, start with an alphanumeric character, and end with an alphanumeric character or underscore."
  }

  validation {
    condition     = length(distinct([for subnet in values(var.network.subnets) : subnet.name])) == length(var.network.subnets)
    error_message = "Each subnet name must be unique within the virtual network."
  }
}

variable "storage" {
  description = "Shared Storage Account configuration."

  type = object({
    sku_name                  = string
    min_tls_version           = string
    shared_access_key_enabled = bool
  })

  nullable = false

  validation {
    condition = contains([
      "Standard_LRS",
      "Standard_GRS",
      "Standard_RAGRS",
      "Standard_ZRS",
      "Premium_LRS"
    ], var.storage.sku_name)
    error_message = "storage.sku_name must be a supported Storage Account replication SKU."
  }

  validation {
    condition     = var.storage.min_tls_version == "TLS1_2"
    error_message = "storage.min_tls_version must be TLS1_2."
  }
}

variable "key_vault" {
  description = "Shared Key Vault configuration."

  type = object({
    sku_name                   = string
    rbac_authorization_enabled = bool
    retention_days             = number
  })

  nullable = false

  validation {
    condition     = contains(["standard", "premium"], var.key_vault.sku_name)
    error_message = "key_vault.sku_name must be standard or premium."
  }

  validation {
    condition = (
      var.key_vault.retention_days >= 7 &&
      var.key_vault.retention_days <= 90 &&
      floor(var.key_vault.retention_days) == var.key_vault.retention_days
    )
    error_message = "key_vault.retention_days must be a whole number from 7 through 90."
  }
}

variable "service_bus" {
  description = "Shared Service Bus namespace and queue configuration."

  type = object({
    sku                           = string
    public_network_access_enabled = bool
    queue_name                    = string
  })

  nullable = false

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.service_bus.sku)
    error_message = "service_bus.sku must be Basic, Standard, or Premium."
  }

  validation {
    condition = (
      length(var.service_bus.queue_name) >= 1 &&
      length(var.service_bus.queue_name) <= 260 &&
      can(regex("^[^/\\\\#?]+$", var.service_bus.queue_name))
    )
    error_message = "service_bus.queue_name must be 1-260 characters and must not contain slash, backslash, #, or ?."
  }
}

variable "container_registry" {
  description = "Shared Azure Container Registry configuration."

  type = object({
    sku                                 = string
    admin_enabled                       = bool
    arm_audience_authentication_enabled = bool
  })

  nullable = false

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.container_registry.sku)
    error_message = "container_registry.sku must be Basic, Standard, or Premium."
  }
}
