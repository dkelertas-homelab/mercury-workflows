# Staging lab cluster. Same module as production; only these values differ.
# Names and the state key are deliberately not the live mercury-tf cluster
# (rg-cloud-course-aks / mercury-staging / phase-7-aks-hardening.tfstate).

module "platform" {
  source = "../modules/platform"

  environment = "staging"
  location    = "Australia East"

  resource_group_name = "rg-mercury-phase10-staging"
  cluster_name        = "mercury-p10-staging"
  dns_prefix          = "d11s-p10-staging"
  kubernetes_version  = "1.34.10"

  admin_group_object_ids = ["155dc92c-768e-4abe-924c-a00fb09c68f3"]

  # 2 + 2 Standard_D2s_v3, same shape as the live cluster, not the course 2 + 4.
  system_node_count = 2
  system_vm_size    = "Standard_D2s_v3"
  user_node_count   = 2
  user_vm_size      = "Standard_D2s_v3"

  key_vault_name       = "d11s-kv-p10-staging"
  storage_account_name = "d11sp10bakstaging"

  domain       = "p10-staging.d11s.space"
  customers    = ["julius"]
  db_instances = 1

  git_repository_url = "ssh://git@github.com/dkelertas-homelab/mercury-gitops"
  git_branch         = "master"
  gitops_repo_path   = abspath("${path.root}/../gitops")

  # Flip to true when using this cluster for Azure Monitor practice.
  enable_azure_monitor         = false
  log_analytics_daily_quota_gb = 1
}
