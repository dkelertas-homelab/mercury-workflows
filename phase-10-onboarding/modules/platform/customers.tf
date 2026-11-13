module "customer" {
  source   = "../customer-onboarding"
  for_each = var.customers

  customer_name = each.key
  environment   = var.environment

  key_vault_id                              = azurerm_key_vault.mercury_vault.id
  storage_account_id                        = azurerm_storage_account.cnpg_backups.id
  storage_account_name                      = azurerm_storage_account.cnpg_backups.name
  storage_account_primary_connection_string = azurerm_storage_account.cnpg_backups.primary_connection_string

  keyvault_name                   = azurerm_key_vault.mercury_vault.name
  keyvault_tenant_id              = data.azurerm_client_config.current.tenant_id
  aks_keyvault_identity_client_id = azurerm_kubernetes_cluster.main.key_vault_secrets_provider[0].secret_identity[0].client_id

  gitops_repo_path = var.gitops_repo_path
  domain           = var.domain
  db_instances     = var.db_instances
  n8n_version      = var.n8n_version

  depends_on = [azurerm_role_assignment.kv_admin]
}

resource "local_file" "apps_kustomization" {
  filename = "${var.gitops_repo_path}/apps/${var.environment}/kustomization.yaml"
  content = yamlencode({
    apiVersion = "kustomize.config.k8s.io/v1beta1"
    kind       = "Kustomization"
    resources  = local.customers_sorted
  })

  depends_on = [module.customer]
}
