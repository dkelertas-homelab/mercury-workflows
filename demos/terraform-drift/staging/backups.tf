# ---------------------------------------------------------------------------
# DEMO COPY - Terraform drift walkthrough (see ../README.md)
# Copied from phase-10-onboarding/staging/backups.tf. Never run `terraform apply`
# from this folder against the real staging state. It exists to be read.
# ---------------------------------------------------------------------------

## CNPG Backup Storage
# Shared storage account for all customer backups
# Each customer gets their own container via the customer-onboarding module

resource "azurerm_storage_account" "cnpg_backups" {
  name                     = "d11smercurybakstaging"
  resource_group_name      = azurerm_resource_group.aks.name
  location                 = azurerm_resource_group.aks.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  # DEMO BASELINE (not in phase-10): explicit hardening + tags so there is
  # something for the portal to drift away from.
  allow_nested_items_to_be_public = false

  tags = {
    Environment = "staging"
    Owner       = "mercury-app-team"
    Project     = "mercury"
  }

  blob_properties {
    versioning_enabled = true
  }

  # NOISE, IGNORED: Azure Policy "Inherit CostCentre tag from resource group"
  # stamps this tag on the account. Terraform does not own it.
  lifecycle {
    ignore_changes = [tags["CostCentre"]]
  }
}

# UNMANAGED, ADOPTED: container created by hand in the portal for a brutus
# restore drill. Adopted rather than deleted (see README, "Import or delete").
import {
  to = azurerm_storage_container.brutus_manual_restore
  id = "/subscriptions/4d3581c5-8c2a-4c59-8455-f5453776eeb7/resourceGroups/rg-cloud-course-aks/providers/Microsoft.Storage/storageAccounts/d11smercurybakstaging/blobServices/default/containers/brutus-manual-restore"
}

resource "azurerm_storage_container" "brutus_manual_restore" {
  name                  = "brutus-manual-restore"
  storage_account_id    = azurerm_storage_account.cnpg_backups.id
  container_access_type = "private"
}
