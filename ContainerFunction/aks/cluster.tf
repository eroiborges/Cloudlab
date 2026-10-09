resource "azurerm_kubernetes_cluster" "main" {
  name                = local.cluster_name
  location            = var.handoff.azure.location
  resource_group_name = var.handoff.azure.resource_group.name
  dns_prefix          = var.aks.cluster.dns_prefix
  kubernetes_version  = var.aks.cluster.kubernetes_version
  sku_tier            = var.aks.cluster.sku_tier

  automatic_upgrade_channel         = var.aks.cluster.automatic_upgrade_channel
  node_os_upgrade_channel           = var.aks.cluster.node_os_upgrade_channel
  local_account_disabled            = var.aks.cluster.local_account_disabled
  role_based_access_control_enabled = var.aks.cluster.role_based_access_control_enabled
  oidc_issuer_enabled               = var.aks.features.oidc_issuer_enabled
  workload_identity_enabled         = var.aks.features.workload_identity_enabled

  default_node_pool {
    name                   = var.aks.system_node_pool.name
    node_count             = var.aks.system_node_pool.node_count
    vm_size                = var.aks.system_node_pool.vm_size
    vnet_subnet_id         = var.handoff.network.subnets.worker_aks.id
    os_disk_type           = var.aks.system_node_pool.os_disk_type
    os_disk_size_gb        = var.aks.system_node_pool.os_disk_size_gb
    os_sku                 = var.aks.system_node_pool.os_sku
    max_pods               = var.aks.system_node_pool.max_pods
    zones                  = var.aks.system_node_pool.zones
    node_public_ip_enabled = var.aks.system_node_pool.node_public_ip_enabled

    upgrade_settings {
      max_surge                     = var.aks.system_node_pool.upgrade_settings.max_surge
      drain_timeout_in_minutes      = var.aks.system_node_pool.upgrade_settings.drain_timeout_in_minutes
      node_soak_duration_in_minutes = var.aks.system_node_pool.upgrade_settings.node_soak_duration_in_minutes
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.control_plane.id]
  }

  linux_profile {
    admin_username = var.aks.cluster.ssh_admin_username

    ssh_key {
      key_data = trimspace(file(pathexpand(var.aks.cluster.ssh_public_key_path)))
    }
  }

  network_profile {
    network_plugin      = var.aks.network.network_plugin
    network_plugin_mode = var.aks.network.network_plugin_mode
    network_policy      = var.aks.network.network_policy
    load_balancer_sku   = var.aks.network.load_balancer_sku
    outbound_type       = var.aks.network.outbound_type
    pod_cidr            = var.aks.network.pod_cidr
    service_cidr        = var.aks.network.service_cidr
    dns_service_ip      = var.aks.network.dns_service_ip
  }

  node_provisioning_profile {
    mode = var.aks.cluster.node_provisioning_mode
  }

  workload_autoscaler_profile {
    keda_enabled = var.aks.features.keda_enabled
  }

  tags = var.aks.cluster.tags

  depends_on = [azurerm_role_assignment.control_plane_network]
}

output "cluster" {
  description = "AKS cluster details required by the deployment workflow."
  value = {
    id                 = azurerm_kubernetes_cluster.main.id
    name               = azurerm_kubernetes_cluster.main.name
    kubernetes_version = azurerm_kubernetes_cluster.main.kubernetes_version
    oidc_issuer_url    = azurerm_kubernetes_cluster.main.oidc_issuer_url
    kubelet_object_id  = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
  }
}
