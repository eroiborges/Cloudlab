variable "resource_group_location" {
  type        = string
  default     = "centralus"
  description = "Location of the resource group."
}

variable "main_resource_group_name" {
  type        = string
  default     = "rg-labhub"
  description = "resource group name"
}

variable "workload_name" {
  type        = string
  default     = "demolab"
  description = "Short name used to compose workload resource names."

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.workload_name))
    error_message = "workload_name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "custom_domain_name" {
  type        = string
  default     = "appdemo.eroicloud.com.br"
  description = "Public custom hostname that will be bound to the Web App after DNS validation."
}

variable "certificate_pfx_path" {
  type        = string
  default     = "certs/appdemo.eroicloud.com.br.pfx"
  description = "Path to the public CA-issued PFX file, relative to this Terraform root."
}

variable "certificate_pfx_password" {
  type        = string
  sensitive   = true
  description = "Password that protects the PFX private key. Supply it through TF_VAR_certificate_pfx_password."
}

variable "vm_admin_username" {
  type        = string
  default     = "azureuser"
  description = "Administrator username for the Linux virtual machines."
}

variable "vm_ssh_public_key" {
  type        = string
  default     = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCxwF6b5iC009pSTLHYiN7J1UIoft66izcWQfAX/obwYw6JxWp/dxVAfaBAAdKiKxC1CTX3+5id+ofls3FfJgxRlBGF+F+ffupW+NVLT6fsmRudA6JP4oG1kHO0jraUFlPc0LcA4Gjpbg7T/XkJAZuWR7+V24iVsMyFK4xLDV8RDsrVmmD3PGA3QWL31+jpd1xdCwrW3BRlO6xVh+Aay8BUAbUXWFaisoplrynURoEbsm6y2oPXBvId9iWZAHwkcj6uFodReqOf4d5AzmBVy8Opsez6EFUwZEq4k1FINmTDEYuP9Kvf4lARib0ClL7Cjydv1mlj809AxQ/lG+ieKyh7"
  description = "SSH public key used to access the Linux virtual machines."
}
