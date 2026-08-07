terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = "4d3581c5-8c2a-4c59-8455-f5453776eeb7"
}

# Customer 1: CATO Corporation
module "cato" {
  source = "./modules/customer-infrastructure"

  customer_name           = "cato01"
  location                = "northeurope"
  vnet_cidr               = "10.1.0.0/16"
  ssh_public_key          = file("~/.ssh/mercury.pub")
  postgres_admin_password = "CatoP@ssw0rd123!"
}

# Customer 2: Cicero Ltd
module "cicero" {
  source = "./modules/customer-infrastructure"

  customer_name           = "cicero01"
  location                = "northeurope"
  vnet_cidr               = "10.2.0.0/16"
  ssh_public_key          = file("~/.ssh/mercury.pub")
  postgres_admin_password = "CiceroP@ssw0rd123!"
}

# Outputs for Customer 1
output "cato_vm_ip" {
  description = "CATO VM public IP"
  value       = module.cato.vm_public_ip
}

output "cato_ssh" {
  description = "CATO SSH connection"
  value       = module.cato.ssh_connection
}

output "cato_postgres" {
  description = "CATO PostgreSQL FQDN"
  value       = module.cato.postgres_fqdn
}

# # Outputs for Customer 2
output "cicero_vm_ip" {
  description = "Cicero VM public IP"
  value       = module.cicero.vm_public_ip
}

output "cicero_ssh" {
  description = "Cicero SSH connection"
  value       = module.cicero.ssh_connection
}

output "cicero_postgres" {
  description = "Cicero PostgreSQL FQDN"
  value       = module.cicero.postgres_fqdn
}
