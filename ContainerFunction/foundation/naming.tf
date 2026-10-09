resource "random_string" "resource_suffix" {
  length  = var.naming.random_length
  lower   = true
  numeric = true
  special = false
  upper   = false
}

locals {
  base_name                  = "${var.naming.base_prefix}${random_string.resource_suffix.result}"
  storage_account_name       = local.base_name
  container_registry_name    = local.base_name
  key_vault_name             = "${var.naming.key_vault_prefix}${local.base_name}"
  service_bus_namespace_name = "${var.naming.service_bus_prefix}${local.base_name}"
  producer_identity_name     = "${var.managed_identities.producer.name_prefix}${local.base_name}"
  consumer_identity_name     = "${var.managed_identities.consumer.name_prefix}${local.base_name}"
}
