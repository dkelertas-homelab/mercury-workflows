output "resource_group_name" {
  value = module.platform.resource_group_name
}

output "cluster_name" {
  value = module.platform.cluster_name
}

output "key_vault_name" {
  value = module.platform.key_vault_name
}

output "key_vault_uri" {
  value = module.platform.key_vault_uri
}

output "aks_keyvault_secrets_provider_client_id" {
  value = module.platform.aks_keyvault_secrets_provider_client_id
}

output "tenant_id" {
  value = module.platform.tenant_id
}

output "storage_account_name" {
  value = module.platform.storage_account_name
}

output "log_analytics_workspace_id" {
  value = module.platform.log_analytics_workspace_id
}

output "grafana_admin_password" {
  value     = module.platform.grafana_admin_password
  sensitive = true
}

output "customer_urls" {
  value = module.platform.customer_urls
}

output "customer_namespaces" {
  value = module.platform.customer_namespaces
}

output "customer_gitops_paths" {
  value = module.platform.customer_gitops_paths
}

output "gitops_identity_reminder" {
  value = module.platform.gitops_identity_reminder
}
