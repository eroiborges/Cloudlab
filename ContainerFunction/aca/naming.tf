locals {
  environment_name = "${var.aca.environment.name_prefix}${var.handoff.naming.base_name}"
  producer_name    = "${var.aca.producer.name_prefix}${var.handoff.naming.base_name}"
  consumer_name    = "${var.aca.consumer.name_prefix}${var.handoff.naming.base_name}"
}
