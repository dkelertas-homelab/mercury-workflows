data "azurerm_client_config" "current" {}

locals {
  # One Azure disk per CNPG instance, one for the n8n PVC, plus the
  # Prometheus PVC from kube-prometheus-stack (it schedules on the user pool).
  disks_per_customer  = var.db_instances + 1
  required_data_disks = length(var.customers) * local.disks_per_customer + 1
  customers_sorted    = sort(tolist(var.customers))
}

resource "azurerm_resource_group" "aks" {
  name     = var.resource_group_name
  location = var.location
}

## AKS
# System pool is CriticalAddonsOnly. User workloads land on the user pool.
# temporary_name_for_rotation is unset unless an apply is rotating the default pool.

resource "azurerm_kubernetes_cluster" "main" {
  name                = var.cluster_name
  location            = azurerm_resource_group.aks.location
  resource_group_name = azurerm_resource_group.aks.name
  dns_prefix          = var.dns_prefix
  kubernetes_version  = var.kubernetes_version

  azure_active_directory_role_based_access_control {
    admin_group_object_ids = var.admin_group_object_ids
  }

  automatic_upgrade_channel = "patch"
  node_os_upgrade_channel   = "NodeImage"

  default_node_pool {
    name                         = "agentpool"
    node_count                   = var.system_node_count
    vm_size                      = var.system_vm_size
    only_critical_addons_enabled = true
    temporary_name_for_rotation  = var.default_node_pool_temporary_name

    upgrade_settings {
      max_surge = "33%"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin     = "azure"
    network_policy     = "cilium"
    network_data_plane = "cilium"
  }

  key_vault_secrets_provider {
    secret_rotation_enabled = false
  }

  dynamic "oms_agent" {
    for_each = var.enable_azure_monitor ? [1] : []
    content {
      log_analytics_workspace_id      = azurerm_log_analytics_workspace.main[0].id
      msi_auth_for_monitoring_enabled = true
    }
  }

  maintenance_window_auto_upgrade {
    frequency   = "Weekly"
    interval    = 1
    duration    = 4
    day_of_week = "Sunday"
    start_time  = "02:00"
    utc_offset  = "+00:00"
  }

  maintenance_window_node_os {
    frequency   = "Weekly"
    interval    = 1
    duration    = 4
    day_of_week = "Sunday"
    start_time  = "02:00"
    utc_offset  = "+00:00"
  }

  lifecycle {
    ignore_changes = [
      oidc_issuer_enabled,
      default_node_pool[0].upgrade_settings,
    ]
  }

  depends_on = [azurerm_log_analytics_solution.container_insights]
}

resource "azurerm_kubernetes_cluster_node_pool" "user" {
  name                  = "userpool"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = var.user_vm_size
  node_count            = var.user_node_count

  upgrade_settings {
    max_surge = "33%"
  }

  lifecycle {
    precondition {
      condition     = local.required_data_disks <= var.user_node_count * var.max_data_disks_per_node
      error_message = "User pool has ${var.user_node_count * var.max_data_disks_per_node} Azure disk slots (${var.user_node_count} x ${var.user_vm_size}, ${var.max_data_disks_per_node} disks each) but this environment needs ${local.required_data_disks}: ${length(var.customers)} customers x (${var.db_instances} DB replicas + 1 n8n PVC) plus 1 Prometheus PVC. Standard_D2s_v3 allows 4 data disks. Raise user_node_count, or lower customers / db_instances."
    }
  }
}

## GitOps with Flux
# Register the provider once per subscription:
#   az provider register --namespace Microsoft.KubernetesConfiguration
# The extension must wait for the user pool. The system pool cannot run Flux.

resource "azurerm_kubernetes_cluster_extension" "flux" {
  name           = "mercury-flux"
  cluster_id     = azurerm_kubernetes_cluster.main.id
  extension_type = "microsoft.flux"

  depends_on = [azurerm_kubernetes_cluster_node_pool.user]
}

resource "azurerm_kubernetes_flux_configuration" "main" {
  name       = var.cluster_name
  cluster_id = azurerm_kubernetes_cluster.main.id
  namespace  = "flux-system"

  git_repository {
    url             = var.git_repository_url
    reference_type  = "branch"
    reference_value = var.git_branch

    ssh_private_key_base64 = base64encode(file(var.flux_ssh_private_key_path))
  }

  kustomizations {
    name                       = "infra-controllers"
    path                       = "./infrastructure/controllers/${var.environment}"
    sync_interval_in_seconds   = 300
    garbage_collection_enabled = true
  }

  kustomizations {
    name                       = "infra-configs"
    path                       = "./infrastructure/configs/${var.environment}"
    sync_interval_in_seconds   = 300
    depends_on                 = ["infra-controllers"]
    garbage_collection_enabled = true
  }

  # The Barman Cloud plugin webhook needs cert-manager, which lands with infra-configs.
  kustomizations {
    name                       = "cnpg-plugin"
    path                       = "./infrastructure/cnpg-plugin/${var.environment}"
    sync_interval_in_seconds   = 300
    depends_on                 = ["infra-configs"]
    garbage_collection_enabled = true
  }

  # Monitoring does not wait on apps, so a broken customer rollout still leaves Grafana up.
  kustomizations {
    name                       = "monitoring-controllers"
    path                       = "./monitoring/controllers/${var.environment}"
    sync_interval_in_seconds   = 300
    depends_on                 = ["infra-controllers"]
    garbage_collection_enabled = true
  }

  kustomizations {
    name                       = "monitoring-configs"
    path                       = "./monitoring/configs/${var.environment}"
    sync_interval_in_seconds   = 300
    depends_on                 = ["monitoring-controllers"]
    garbage_collection_enabled = true
  }

  kustomizations {
    name                       = "apps"
    path                       = "./apps/${var.environment}"
    sync_interval_in_seconds   = 300
    depends_on                 = ["cnpg-plugin"]
    garbage_collection_enabled = true
  }

  scope = "cluster"

  depends_on = [azurerm_kubernetes_cluster_extension.flux]
}

## Key Vault

resource "azurerm_key_vault" "mercury_vault" {
  name                = var.key_vault_name
  location            = azurerm_resource_group.aks.location
  resource_group_name = azurerm_resource_group.aks.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  soft_delete_retention_days = 7
  purge_protection_enabled   = false

  rbac_authorization_enabled = true
  depends_on                 = [azurerm_kubernetes_cluster.main]
}

resource "azurerm_role_assignment" "kv_admin" {
  scope                = azurerm_key_vault.mercury_vault.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "aks_keyvault_secrets_provider" {
  scope                = azurerm_key_vault.mercury_vault.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_kubernetes_cluster.main.key_vault_secrets_provider[0].secret_identity[0].object_id
}

resource "random_password" "grafana_admin" {
  length  = 24
  special = false

  lifecycle {
    ignore_changes = all
  }
}

resource "azurerm_key_vault_secret" "grafana_admin_password" {
  name         = "grafana-admin-password"
  value        = random_password.grafana_admin.result
  key_vault_id = azurerm_key_vault.mercury_vault.id

  depends_on = [azurerm_role_assignment.kv_admin]
}

resource "azurerm_key_vault_secret" "grafana_admin_user" {
  name         = "grafana-admin-user"
  value        = "admin"
  key_vault_id = azurerm_key_vault.mercury_vault.id

  depends_on = [azurerm_role_assignment.kv_admin]
}

resource "azurerm_key_vault_secret" "grafana_telegram_bot_token" {
  name         = "grafana-telegram-bot-token"
  value        = "DEMO:dummy-bot-token-replace-me"
  key_vault_id = azurerm_key_vault.mercury_vault.id

  lifecycle {
    ignore_changes = [value]
  }

  depends_on = [azurerm_role_assignment.kv_admin]
}

resource "azurerm_key_vault_secret" "grafana_telegram_chat_id" {
  name         = "grafana-telegram-chat-id"
  value        = "000000000"
  key_vault_id = azurerm_key_vault.mercury_vault.id

  lifecycle {
    ignore_changes = [value]
  }

  depends_on = [azurerm_role_assignment.kv_admin]
}

## CNPG backup storage
# One account per environment. The customer module adds a private container per customer.

resource "azurerm_storage_account" "cnpg_backups" {
  name                     = var.storage_account_name
  resource_group_name      = azurerm_resource_group.aks.name
  location                 = azurerm_resource_group.aks.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  blob_properties {
    versioning_enabled = true
  }
}

resource "azurerm_key_vault_secret" "storage_account_name" {
  name         = "storage-account-name"
  value        = azurerm_storage_account.cnpg_backups.name
  key_vault_id = azurerm_key_vault.mercury_vault.id

  depends_on = [azurerm_role_assignment.kv_admin]
}

## Azure Monitor
# One switch creates the workspace, Container Insights and the kube-audit-admin diagnostic setting.

resource "azurerm_log_analytics_workspace" "main" {
  count               = var.enable_azure_monitor ? 1 : 0
  name                = "law-d11s-p10-${var.environment}"
  location            = azurerm_resource_group.aks.location
  resource_group_name = azurerm_resource_group.aks.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  daily_quota_gb      = var.log_analytics_daily_quota_gb
}

resource "azurerm_log_analytics_solution" "container_insights" {
  count                 = var.enable_azure_monitor ? 1 : 0
  solution_name         = "ContainerInsights"
  location              = azurerm_resource_group.aks.location
  resource_group_name   = azurerm_resource_group.aks.name
  workspace_resource_id = azurerm_log_analytics_workspace.main[0].id
  workspace_name        = azurerm_log_analytics_workspace.main[0].name

  plan {
    publisher = "Microsoft"
    product   = "OMSGallery/ContainerInsights"
  }
}

resource "azurerm_monitor_diagnostic_setting" "aks" {
  count                      = var.enable_azure_monitor ? 1 : 0
  name                       = "aks-kube-audit-admin"
  target_resource_id         = azurerm_kubernetes_cluster.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id

  enabled_log {
    category = "kube-audit-admin"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_role_assignment" "oms_publisher" {
  count                            = var.enable_azure_monitor ? 1 : 0
  scope                            = azurerm_log_analytics_workspace.main[0].id
  role_definition_name             = "Monitoring Metrics Publisher"
  principal_id                     = azurerm_kubernetes_cluster.main.oms_agent[0].oms_agent_identity[0].object_id
  skip_service_principal_aad_check = true
}
