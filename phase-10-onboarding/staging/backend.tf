# Remote state in the shared d11smercurytfstate account.
# Key is phase-10-staging.tfstate, not the live mercury-tf key
# phase-7-aks-hardening.tfstate. See azure-blob.tfbackend.
terraform {
  backend "azurerm" {}
}
