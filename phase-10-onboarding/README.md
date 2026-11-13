# Phase 10: Customer Onboarding

Staging and production are two roots of the same module, `modules/platform`. They differ by the values in each root's `main.tf` (names, node counts, customers, whether Azure Monitor is on). `modules/customer-onboarding` still creates one blob container, the Key Vault secrets and the GitOps manifests for each customer.

These clusters are a lab beside the live `mercury-tf` cluster. They do not reuse its resource group, cluster name, DNS prefix, Key Vault, backup storage account or state key.

| | Live `mercury-tf` | Phase 10 staging | Phase 10 production |
|---|---|---|---|
| State key | `phase-7-aks-hardening.tfstate` | `phase-10-staging.tfstate` | `phase-10-production.tfstate` |
| Resource group | `rg-cloud-course-aks` | `rg-mercury-phase10-staging` | `rg-mercury-phase10-prod` |
| Cluster | `mercury-staging` | `mercury-p10-staging` | `mercury-p10-prod` |
| Region | Australia East | Australia East | Australia East |
| Nodes | 2 + 2 `Standard_D2s_v3` | 2 + 2 `Standard_D2s_v3` | 2 + 4 `Standard_D2s_v3` |
| Customers | `customer1` (in mercury-gitops, not this module) | `julius`, 1 DB replica | `julius`, `cicero`, `crassus`, 3 DB replicas |
| Azure Monitor | off | off (`enable_azure_monitor`) | on, 1 GB/day cap |
| Flux | `dkelertas-homelab/mercury-gitops` `master` | same | same |

`temporary_name_for_rotation` is not set. The previous production file did not set it either. Leave `default_node_pool_temporary_name` null. Set it only for the one apply that has to rotate the default node pool, then set it back to null.

## What was unfinished

The course copies were not deployable on this subscription:

- North Europe, the course subscription, and Flux pointed at `mischavandenburg/mercury-gitops` on `main`
- No remote state. A destroy of the cluster resource group would have taken the state with it
- Staging and production were two full copies of the stack, and staging used the same 2 + 4 nodes as production
- Key Vault and storage names (`kv-mercury-staging`, `mercurybackupsstaging`) are the course names, not the globally unique `d11s*` names
- Customer manifests were written to `/workspaces/mercury-gitops`, which is not this machine and not mercury-gitops
- `gitops/apps` had a single partial `julius` Deployment and no production app path
- Grafana hostnames and the cert-manager email were still the course values. The monitoring identity patches were course client IDs

`mercury-tf/staging` is a separate unfinished copy. It points the customer module at a path that does not exist, its backend symlink is broken (`../backends` from inside `mercury-tf/staging`), and applying it would use the live state key. This phase does not change `mercury-tf`.

## Disk budget

`Standard_D2s_v3` attaches 4 data disks. Each customer needs one disk per CNPG instance plus one for the n8n volume. kube-prometheus-stack adds one Prometheus volume on the user pool.

| Environment | Customers | DB replicas | Disks needed | User nodes | Slots |
|---|---|---|---|---|---|
| Staging | 1 (`julius`) | 1 | 1×2 + 1 Prometheus = 3 | 2 | 8 |
| Production | 3 | 3 | 3×4 + 1 Prometheus = 13 | 4 | 16 |

A fourth HA customer (the course list also had `brutus`) would be 4×4 + 1 = 17 disks, which does not fit on 4 nodes. The module refuses the apply when the disk sum exceeds the slots. Adding `cicero` to staging at 1 replica is 5 disks and still fits. Adding a fourth staging customer at 1 replica is 9 disks and does not.

## Bring-up

Prerequisites: `az login` to subscription `4d3581c5-8c2a-4c59-8455-f5453776eeb7`, Storage Blob Data Contributor on `d11smercurytfstate`, and the Flux deploy key at `~/.ssh/mercury`.

```bash
az provider register --namespace Microsoft.KubernetesConfiguration

cd phase-10-onboarding/staging
terraform init -backend-config=azure-blob.tfbackend
terraform apply

# production, when you want the larger cluster
cd ../production
terraform init -backend-config=azure-blob.tfbackend
terraform apply
```

Apply writes customer manifests under `phase-10-onboarding/gitops/apps/<environment>/<customer>/` and rewrites `apps/<environment>/kustomization.yaml`. It does not push them.

Confirm the version is still offered before the first apply:

```bash
az aks get-versions -l australiaeast --output table
```

The roots pin `1.34.10`, which is what `mercury-tf` runs. If Australia East has dropped that patch, change `kubernetes_version` in the root you are applying.

### Azure Monitor

Staging leaves Container Insights and diagnostic settings off. Set `enable_azure_monitor = true` in `staging/main.tf` before apply (or a later apply) to create:

- Log Analytics workspace `law-d11s-p10-<environment>` (30 day retention, daily cap from `log_analytics_daily_quota_gb`)
- Container Insights (`oms_agent` with managed identity, plus the ContainerInsights solution)
- An AKS diagnostic setting for `kube-audit-admin` and AllMetrics

Production turns that on with a 1 GB/day cap. Full `kube-audit` is not enabled. Set `enable_azure_monitor = false` in `production/main.tf` if you want the cluster without the workspace. If the first apply errors on the Monitoring Metrics Publisher role assignment, run apply again after the Container Insights identity exists.

Alert rules, action groups and least-privilege remediation runbooks are not in this phase.

## Customer pods

Terraform does not apply Kubernetes manifests. Flux on the new cluster reads `dkelertas-homelab/mercury-gitops` branch `master`. That repo currently has `apps/staging/customer1` only (`customer1-n8n`). It does not have `julius`, `cicero`, `crassus` or `brutus`, and it does not have `infrastructure/cnpg-plugin/` or any `production` path. Do not commit those from this pull request. Until a follow-up adds them, Flux on the new cluster will be unhealthy and no phase-10 customer pod will start.

The first apply still installs Flux against `master`. On that branch `apps/staging` is the live `customer1` app, aimed at Key Vault `d11s-kv-mercury-staging` and the live cluster's identity. The new staging cluster will try to sync that app, and it will fail the secret mount. It will also fail `infrastructure/cnpg-plugin/staging`, which is not in the repo. That does not change the live cluster. Expect Flux to stay unhealthy until the follow-up below replaces those paths.

After apply, copy the generated tree and the phase-10 paths Flux expects:

- `gitops/apps/<environment>/` (generated customers)
- `gitops/infrastructure/cnpg-plugin/<environment>` (the live repo still installs the Barman plugin inside `infrastructure/controllers/staging/cnpg/`)
- `gitops/infrastructure/controllers/production` and `configs/production`
- `gitops/monitoring/controllers/production` and `configs/production`

Then set the Grafana SecretProviderClass identity. `terraform output gitops_identity_reminder` prints the client ID. The committed patch uses `00000000-0000-0000-0000-000000000000` on purpose. Customer SecretProviderClasses are generated with the real client ID.

### Check that they are running

```bash
az aks get-credentials -g rg-mercury-phase10-staging -n mercury-p10-staging
kubelogin convert-kubeconfig -l azurecli

flux get kustomizations -A
kubectl get pods -n julius
kubectl get cluster,objectstore,scheduledbackup -n julius
kubectl get ingress -n julius
```

Production uses resource group `rg-mercury-phase10-prod`, cluster `mercury-p10-prod`, and namespaces `julius`, `cicero`, `crassus`.

`julius` is up when `julius-n8n` is Ready and `julius-db` instances are Ready. The URL is `https://julius.p10-staging.d11s.space` (production: `https://julius.p10-prod.d11s.space`). DNS records are not created by Terraform. Grafana is `https://grafana.p10-staging.d11s.space` and `https://grafana.p10-prod.d11s.space`.

## Tear-down

Destroy production first if both exist. State stays in `d11smercurytfstate`.

```bash
cd phase-10-onboarding/production
terraform destroy

cd ../staging
terraform destroy
```

Key Vault soft-delete is 7 days and purge protection is off, so a second apply after destroy can reuse the vault name once the soft-deleted vault is purged (`az keyvault purge`). The live `mercury-tf` state is a different key and is not part of this destroy.

## Telegram placeholders

Each customer and Grafana get dummy Telegram secrets (`DEMO:dummy-bot-token-replace-me`, chat id `000000000`). `lifecycle { ignore_changes = [value] }` keeps a later manual update.

```bash
az keyvault secret set --vault-name d11s-kv-p10-staging \
  --name julius-telegram-bot-token \
  --value "YOUR_REAL_BOT_TOKEN"
```

## Adding a customer

Add the name to `customers` in that environment's `main.tf` and apply. Stay inside the disk budget above. Apply rewrites the manifests locally; Flux picks them up only after they are on `master` of mercury-gitops.
