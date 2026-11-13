variable "environment" {
  type        = string
  description = "Environment name. Selects Flux paths and the generated apps directory."

  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "Environment must be staging or production."
  }
}

variable "location" {
  type        = string
  description = "Azure region for the resource group and cluster."
}

variable "resource_group_name" {
  type        = string
  description = "Resource group for this environment. Must not be the live mercury-tf group rg-cloud-course-aks."

  validation {
    condition     = var.resource_group_name != "rg-cloud-course-aks"
    error_message = "Refusing rg-cloud-course-aks. That group holds the live mercury-tf cluster."
  }
}

variable "cluster_name" {
  type        = string
  description = "AKS cluster name. Must not be the live cluster name mercury-staging."

  validation {
    condition     = var.cluster_name != "mercury-staging"
    error_message = "Refusing mercury-staging. That name is the live mercury-tf cluster."
  }
}

variable "dns_prefix" {
  type        = string
  description = "AKS DNS prefix. Must be unique in the region and must not be the live prefix staging."

  validation {
    condition     = var.dns_prefix != "staging"
    error_message = "Refusing dns_prefix staging. The live cluster already uses staging.<region>.azmk8s.io."
  }
}

variable "kubernetes_version" {
  type        = string
  description = "AKS Kubernetes version. Match a version Australia East still offers."
  default     = "1.34.10"
}

variable "admin_group_object_ids" {
  type        = list(string)
  description = "Entra ID group object IDs granted cluster admin."
}

variable "system_node_count" {
  type        = number
  description = "System pool size. Tainted CriticalAddonsOnly."
  default     = 2
}

variable "system_vm_size" {
  type        = string
  description = "System pool VM size."
  default     = "Standard_D2s_v3"
}

variable "user_node_count" {
  type        = number
  description = "User pool size. Customer pods, Flux, Traefik, CNPG and Prometheus schedule here."
  default     = 2
}

variable "user_vm_size" {
  type        = string
  description = "User pool VM size."
  default     = "Standard_D2s_v3"
}

variable "max_data_disks_per_node" {
  type        = number
  description = "Azure data disks the user VM size can attach. Standard_D2s_v3 allows 4. Change this if user_vm_size changes."
  default     = 4
}

variable "default_node_pool_temporary_name" {
  type        = string
  description = "temporary_name_for_rotation for the default node pool. Leave null. Set it only for the apply that rotates the default pool (VM size, zones, or other force-new pool properties), then set it back to null. A permanent value is not required to create the cluster."
  default     = null
  nullable    = true
}

variable "key_vault_name" {
  type        = string
  description = "Globally unique Key Vault name (3-24 characters)."

  validation {
    condition     = can(regex("^[a-zA-Z][-a-zA-Z0-9]{1,22}[a-zA-Z0-9]$", var.key_vault_name))
    error_message = "Key Vault name must be 3-24 characters, alphanumeric or hyphen, starting with a letter."
  }

  validation {
    condition     = var.key_vault_name != "d11s-kv-mercury-staging"
    error_message = "Refusing d11s-kv-mercury-staging. That vault belongs to the live mercury-tf cluster."
  }
}

variable "storage_account_name" {
  type        = string
  description = "Globally unique storage account name for CNPG backups."

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "Storage account name must be 3-24 lowercase letters or digits."
  }

  validation {
    condition     = var.storage_account_name != "d11smercurybakstaging"
    error_message = "Refusing d11smercurybakstaging. That account belongs to the live mercury-tf cluster."
  }
}

variable "domain" {
  type        = string
  description = "Base domain. Each customer is published at <customer>.<domain>."
}

variable "customers" {
  type        = set(string)
  description = "Customer names to onboard. Each name gets a blob container, Key Vault secrets and GitOps manifests."
}

variable "db_instances" {
  type        = number
  description = "CNPG instances per customer. 1 for a lab, 3 for HA. Each instance is one Azure disk, plus one disk for the n8n PVC."
  default     = 1
}

variable "n8n_version" {
  type        = string
  description = "n8n image tag written into the generated Deployment."
  default     = "2.35.3"
}

variable "git_repository_url" {
  type        = string
  description = "Flux Git SSH URL."
  default     = "ssh://git@github.com/dkelertas-homelab/mercury-gitops"
}

variable "git_branch" {
  type        = string
  description = "Flux Git branch. The mercury-gitops default branch is master."
  default     = "master"
}

variable "flux_ssh_private_key_path" {
  type        = string
  description = "Path to the Flux deploy key. The public half must be a deploy key on mercury-gitops."
  default     = "~/.ssh/mercury"
}

variable "gitops_repo_path" {
  type        = string
  description = "Local checkout where customer manifests are written. This repo's phase-10 gitops tree by default. Flux does not read this path; the files still have to be pushed to mercury-gitops."
}

variable "enable_azure_monitor" {
  type        = bool
  description = "Create a Log Analytics workspace, enable AKS Container Insights (oms_agent) and send the kube-audit-admin diagnostic category to that workspace. Off by default because ingestion is billed."
  default     = false
}

variable "log_analytics_daily_quota_gb" {
  type        = number
  description = "Daily ingestion cap in GB when enable_azure_monitor is true. -1 is unlimited."
  default     = 1
}
