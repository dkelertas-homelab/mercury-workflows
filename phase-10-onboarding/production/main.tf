# Production sibling of staging. Same module; only these values differ.
# Nothing here is the live mercury-tf cluster.

module "platform" {
  source = "../modules/platform"

  environment = "production"
  location    = "Australia East"

  resource_group_name = "rg-mercury-phase10-prod"
  cluster_name        = "mercury-p10-prod"
  dns_prefix          = "d11s-p10-prod"
  kubernetes_version  = "1.34.10"

  admin_group_object_ids = ["155dc92c-768e-4abe-924c-a00fb09c68f3"]

  # 4 user nodes: 3 HA customers need 12 disks, Prometheus needs 1,
  # Standard_D2s_v3 attaches 4 disks, 4 x 4 = 16.
  system_node_count = 2
  system_vm_size    = "Standard_D2s_v3"
  user_node_count   = 4
  user_vm_size      = "Standard_D2s_v3"

  key_vault_name       = "d11s-kv-p10-prod"
  storage_account_name = "d11sp10bakprod"

  domain       = "p10-prod.d11s.space"
  customers    = ["julius", "cicero", "crassus"]
  db_instances = 3

  git_repository_url = "ssh://git@github.com/dkelertas-homelab/mercury-gitops"
  git_branch         = "master"
  gitops_repo_path   = abspath("${path.root}/../gitops")

  # Audit logs for the remediation lab, capped so a chatty cluster cannot run the bill up.
  enable_azure_monitor         = true
  log_analytics_daily_quota_gb = 1
}
