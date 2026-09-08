output "hosted_zone_id" {
  description = "ID of the existing public Route 53 hosted zone."
  value       = data.aws_route53_zone.public.zone_id
}

output "created_dns_records" {
  description = "DNS records created from the Azure App Service handoff."
  value = {
    for key, record in aws_route53_record.webapp :
    key => {
      fqdn    = record.fqdn
      type    = record.type
      records = record.records
    }
  }
}

output "custom_domain" {
  description = "Custom domain prepared for the Azure App Service binding."
  value       = var.handoff.custom_domain
}
