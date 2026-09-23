# Remote state in Azure Blob (durable RG outside phase-7 destroy blast radius).
# Shared values: azure-blob.tfbackend -> ../backends/azure-blob.tfbackend
terraform {
  backend "azurerm" {}
}
