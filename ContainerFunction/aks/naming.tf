locals {
  cluster_name                = "${var.aks.cluster.name_prefix}${var.handoff.naming.base_name}"
  control_plane_identity_name = "${var.aks.cluster.control_plane_identity_name_prefix}${var.handoff.naming.base_name}"
}
