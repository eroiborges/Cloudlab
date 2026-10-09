locals {
  manifest_values = {
    namespace                     = var.aks.kubernetes.namespace
    acr_login_server              = var.handoff.container_registry.login_server
    storage_name                  = var.handoff.storage.name
    service_bus_namespace         = var.handoff.service_bus.namespace.name
    service_bus_queue             = var.handoff.service_bus.queue.name
    key_vault_uri                 = var.handoff.key_vault.uri
    producer_client_id            = var.handoff.managed_identities.producer.client_id
    consumer_client_id            = var.handoff.managed_identities.consumer.client_id
    producer_deployment_name      = var.aks.kubernetes.producer.deployment_name
    producer_service_account_name = var.aks.kubernetes.producer.service_account_name
    producer_container_name       = var.aks.kubernetes.producer.container_name
    producer_image_repository     = var.aks.kubernetes.producer.image_repository
    producer_image_tag            = var.aks.kubernetes.producer.image_tag
    producer_host_id              = var.aks.kubernetes.producer.host_id
    producer_replicas             = var.aks.kubernetes.producer.replicas
    producer_min_replicas         = var.aks.kubernetes.producer.min_replicas
    producer_max_replicas         = var.aks.kubernetes.producer.max_replicas
    producer_cpu_request          = var.aks.kubernetes.producer.cpu_request
    producer_memory_request       = var.aks.kubernetes.producer.memory_request
    producer_cpu_limit            = var.aks.kubernetes.producer.cpu_limit
    producer_memory_limit         = var.aks.kubernetes.producer.memory_limit
    producer_container_port       = var.aks.kubernetes.producer.container_port
    producer_service_type         = var.aks.kubernetes.producer.service_type
    producer_hpa_cpu_utilization  = var.aks.kubernetes.producer.hpa_cpu_utilization
    consumer_deployment_name      = var.aks.kubernetes.consumer.deployment_name
    consumer_service_account_name = var.aks.kubernetes.consumer.service_account_name
    consumer_container_name       = var.aks.kubernetes.consumer.container_name
    consumer_image_repository     = var.aks.kubernetes.consumer.image_repository
    consumer_image_tag            = var.aks.kubernetes.consumer.image_tag
    consumer_host_id              = var.aks.kubernetes.consumer.host_id
    consumer_replicas             = var.aks.kubernetes.consumer.replicas
    consumer_min_replicas         = var.aks.kubernetes.consumer.min_replicas
    consumer_max_replicas         = var.aks.kubernetes.consumer.max_replicas
    consumer_cpu_request          = var.aks.kubernetes.consumer.cpu_request
    consumer_memory_request       = var.aks.kubernetes.consumer.memory_request
    consumer_cpu_limit            = var.aks.kubernetes.consumer.cpu_limit
    consumer_memory_limit         = var.aks.kubernetes.consumer.memory_limit
    consumer_container_port       = var.aks.kubernetes.consumer.container_port
    polling_interval_seconds      = var.aks.kubernetes.consumer.polling_interval_seconds
    cooldown_period_seconds       = var.aks.kubernetes.consumer.cooldown_period_seconds
    message_count                 = var.aks.kubernetes.consumer.message_count
    activation_message_count      = var.aks.kubernetes.consumer.activation_message_count
    fallback_failure_threshold    = var.aks.kubernetes.consumer.fallback_failure_threshold
    fallback_replicas             = var.aks.kubernetes.consumer.fallback_replicas
    scale_down_stabilization      = var.aks.kubernetes.consumer.scale_down_stabilization_seconds
    startup_period_seconds        = var.aks.kubernetes.probes.startup_period_seconds
    startup_failure_threshold     = var.aks.kubernetes.probes.startup_failure_threshold
    readiness_period_seconds      = var.aks.kubernetes.probes.readiness_period_seconds
    readiness_timeout_seconds     = var.aks.kubernetes.probes.readiness_timeout_seconds
    readiness_failure_threshold   = var.aks.kubernetes.probes.readiness_failure_threshold
    liveness_period_seconds       = var.aks.kubernetes.probes.liveness_period_seconds
    liveness_timeout_seconds      = var.aks.kubernetes.probes.liveness_timeout_seconds
    liveness_failure_threshold    = var.aks.kubernetes.probes.liveness_failure_threshold
  }

  manifest_templates = fileset("${path.module}/../k8s/yaml", "*.yaml.tftpl")
}

resource "local_file" "kubernetes_manifests" {
  for_each = local.manifest_templates

  filename = "${path.module}/../k8s/rendered/${trimsuffix(each.value, ".tftpl")}"
  content = templatefile(
    "${path.module}/../k8s/yaml/${each.value}",
    local.manifest_values
  )

  file_permission = "0644"
}

output "rendered_manifests" {
  description = "Kubernetes manifests rendered from the AKS Terraform variables and foundation handoff."
  value = {
    for name, manifest in local_file.kubernetes_manifests :
    name => manifest.filename
  }
}
