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

resource "azurerm_resource_group" "aks" {
  name     = "rg-cloud-course-aks"
  location = "Australia East"
}

resource "azurerm_kubernetes_cluster" "main" {
  name                = "mercury-cluster"
  location            = azurerm_resource_group.aks.location
  resource_group_name = azurerm_resource_group.aks.name
  dns_prefix          = "mercury"
  kubernetes_version  = "1.35.0"
  # Standard_A4_v2
  default_node_pool {
    name       = "default"
    node_count = 1
    vm_size    = "Standard_D2s_v3"
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin     = "azure"
    network_policy     = "cilium"
    network_data_plane = "cilium"
  }
  lifecycle {
    ignore_changes = [
      oidc_issuer_enabled,
      default_node_pool[0].upgrade_settings
    ]
  }
}

resource "azurerm_resource_group" "pgsql" {
  name     = "rg-cloud-course-pgsql"
  location = "Australia East"
}

resource "azurerm_virtual_network" "pgsql" {
  name                = "pgsql-vn"
  location            = azurerm_resource_group.pgsql.location
  resource_group_name = azurerm_resource_group.pgsql.name
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "pgsql" {
  name                 = "pgsql-sn"
  resource_group_name  = azurerm_resource_group.pgsql.name
  virtual_network_name = azurerm_virtual_network.pgsql.name
  address_prefixes     = ["10.0.2.0/24"]
  #service_endpoint {
  #service = "Microsoft.Storage"
  #}
  delegation {
    name = "fs"
    service_delegation {
      name = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}

resource "azurerm_private_dns_zone" "pgsql" {
  name                = "pgsql.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.pgsql.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "pgsql" {
  name                = "pgsqlVnetZone.com"
  #private_dns_zone_id = azurerm_private_dns_zone.pgsql.id
  private_dns_zone_name = azurerm_private_dns_zone.pgsql.name
  virtual_network_id  = azurerm_virtual_network.pgsql.id
  resource_group_name = azurerm_resource_group.pgsql.name
  depends_on          = [azurerm_subnet.pgsql]
}

resource "azurerm_postgresql_flexible_server" "pgsql" {
  name                          = "pgsql-psqlflexibleserver"
  resource_group_name           = azurerm_resource_group.pgsql.name
  location                      = azurerm_resource_group.pgsql.location
  version                       = "12"
  delegated_subnet_id           = azurerm_subnet.pgsql.id
  private_dns_zone_id           = azurerm_private_dns_zone.pgsql.id
  public_network_access_enabled = false
  administrator_login           = "psqladmin"
  administrator_password        = "H@Sh1CoR3!"
  zone                          = "1"

  storage_mb   = 32768
  storage_tier = "P4"

  sku_name   = "B_Standard_B1ms"
  depends_on = [azurerm_private_dns_zone_virtual_network_link.pgsql]

}


























# DB

#resource "azurerm_postgresql_flexible_server" "n8n_db" {
#
#  name                = "psql-n8n-mercury"
#  resource_group_name = azurerm_resource_group.aks.name
#  location            = azurerm_resource_group.aks.location
#  zone                = "2"
#
#  administrator_login    = "n8nadmin"
#  administrator_password = "n8n-password-123"
#
#  sku_name   = "B_Standard_B1ms"
#  storage_mb = 32768
#  version    = "16"
#
#  backup_retention_days = 7
#
#  # Allow Azure services to access (needed for AKS)
#  public_network_access_enabled = true
#}
#
#resource "azurerm_postgresql_flexible_server_configuration" "disable_ssl" {
#  name      = "require_secure_transport"
#  server_id = azurerm_postgresql_flexible_server.n8n_db.id
#  value     = "OFF"
#}
#
#resource "azurerm_postgresql_flexible_server_database" "n8n" {
#  name      = "n8n"
#  server_id = azurerm_postgresql_flexible_server.n8n_db.id
#}
#
#resource "azurerm_postgresql_flexible_server_firewall_rule" "allow_azure_services" {
#  name             = "AllowAzureServices"
#  server_id        = azurerm_postgresql_flexible_server.n8n_db.id
#  start_ip_address = "0.0.0.0"
#  end_ip_address   = "0.0.0.0"
#}
#
#output "db_host" {
#  value = azurerm_postgresql_flexible_server.n8n_db.fqdn
#}
#
#output "db_name" {
#  value = azurerm_postgresql_flexible_server_database.n8n.name
#}
#
#output "db_user" {
#  value = azurerm_postgresql_flexible_server.n8n_db.administrator_login
#}
#
