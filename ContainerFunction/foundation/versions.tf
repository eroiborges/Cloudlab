terraform {
  required_version = ">= 1.16.4, < 2.0.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 5.8.0, < 6.0.0"
    }

    local = {
      source  = "hashicorp/local"
      version = ">= 2.9.1, < 3.0.0"
    }

    random = {
      source  = "hashicorp/random"
      version = ">= 3.9.1, < 4.0.0"
    }
  }
}
