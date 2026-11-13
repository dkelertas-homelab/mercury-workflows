output "resource_group_name" {
  value = azurerm_resource_group.aks.name
}

output "cluster_name" {
  value = azurerm_kubernetes_cluster.main.name
}

output "key_vault_name" {
  value = azurerm_key_vault.mercury_vault.name
}

output "key_vault_uri" {
  value = azurerm_key_vault.mercury_vault.vault_uri
}

output "aks_keyvault_secrets_provider_client_id" {
  value       = azurerm_kubernetes_cluster.main.key_vault_secrets_provider[0].secret_identity[0].client_id
  description = "AKS Key Vault Secrets Provider client ID. Paste this into the monitoring SecretProviderClass after apply."
}

output "tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}

output "storage_account_name" {
  value = azurerm_storage_account.cnpg_backups.name
}

output "log_analytics_workspace_id" {
  value       = try(azurerm_log_analytics_workspace.main[0].id, null)
  description = "Null when enable_azure_monitor is false."
}

output "grafana_admin_password" {
  value       = random_password.grafana_admin.result
  sensitive   = true
  description = "Grafana admin password. Also stored in Key Vault as grafana-admin-password."
}

output "customer_urls" {
  value = {
    for name, customer in module.customer : name => customer.n8n_url
  }
}

output "customer_namespaces" {
  value = {
    for name, customer in module.customer : name => customer.namespace
  }
}

output "customer_gitops_paths" {
  value = {
    for name, customer in module.customer : name => customer.gitops_path
  }
}

output "gitops_identity_reminder" {
  value = <<-EOT
    Update the AKS Key Vault identity in the GitOps SecretProviderClass after apply.

    File: monitoring/controllers/${var.environment}/kube-prometheus-stack/kustomization.yaml
    userAssignedIdentityID: ${azurerm_kubernetes_cluster.main.key_vault_secrets_provider[0].secret_identity[0].client_id}
    tenantId: ${data.azurerm_client_config.current.tenant_id}
    keyvaultName: ${azurerm_key_vault.mercury_vault.name}

    Customer SecretProviderClasses are generated with this identity already.
    Copy apps/${var.environment}/ into mercury-gitops before Flux can deploy the customers.
    The committed monitoring patch still has a placeholder identity until you update it.
  EOT
}
