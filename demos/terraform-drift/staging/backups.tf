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
}
