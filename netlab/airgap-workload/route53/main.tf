data "aws_route53_zone" "public" {
  name         = var.handoff.route53.public_zone_name
  private_zone = false
}

locals {
  dns_records = {
    for record in var.handoff.route53.records :
    "${record.type}:${record.fqdn}" => record
  }
}

resource "aws_route53_record" "webapp" {
  for_each = local.dns_records

  zone_id = data.aws_route53_zone.public.zone_id
  name    = each.value.fqdn
  type    = each.value.type
  ttl     = each.value.ttl
  records = each.value.values
}
