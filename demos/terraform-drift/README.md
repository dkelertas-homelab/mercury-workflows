# Terraform drift walkthrough: mixed intended and unwanted drift

> **Teaching example. Nothing here ran against Azure.** Every `terraform`, `kubectl` and `az` output under
> [`outputs/`](outputs/) is **example output (mocked)**, written by hand to match the real Mercury staging code.
> The folder is self-contained and touches nothing outside `demos/terraform-drift/`.
> The PR that carries it is a demo and is **never merged**.

## What this shows

Real drift is rarely all good or all bad. During an incident someone scales a node pool in the portal (good,
keep it), someone else flips two settings they should not have (bad, revert them), Azure Policy stamps a tag
(noise, ignore it) and a hand-made blob container appears (unmanaged, adopt or delete it). One scheduled scan finds
all of it, and the lesson is to **sort drift attribute by attribute**, not resource by resource, then fix it in
**one PR through the normal pipeline**.

The code is the real Mercury **staging** stack from `phase-10-onboarding/staging` (AKS `mercury-staging` in
`rg-cloud-course-aks`, Australia East, `azurerm ~> 4.0`; customers julius, cicero, crassus, brutus; Key Vault
`d11s-kv-mercury-staging`; backup account `d11smercurybakstaging`).

## Layout

| Path | What it is |
| --- | --- |
| `staging/` | Copy of `phase-10-onboarding/staging/*.tf`. Commit 1 is the pre-incident baseline, commit 2 is the fix. `git diff` between them is the code change. The module source points at the real `phase-10-onboarding/modules/customer-onboarding`. |
| `outputs/01..08` | Mocked command output, in story order |
| `example-workflows/` | Scheduled drift detection (GitHub Actions and Azure DevOps flavours) and the `jq` filter that cuts a plan down to drifted attributes. Not under `.github/workflows/`, so they never run. |

Two small additions to the copy that are **not** in `phase-10` (the real storage account sets neither): explicit
`allow_nested_items_to_be_public = false` and a `tags` block on the backup account, so there is something to drift from.
`required_version` is bumped to `>= 1.5` because `import` blocks need it. The configuration passes `terraform validate`.

## Timeline (all times AEDT, scenario dates)

| When | What happened |
| --- | --- |
| Tue 10 Nov ~13:30 | Staging pods go Pending: 4 customers x (3 CNPG + 1 n8n PVC) = 16 disks, plus 3 monitoring PVCs = 19, but `Standard_D2s_v3` allows 4 data disks per node and 4 user nodes give 16 slots ([01](outputs/01-kubectl-during-incident.txt)) |
| ~14:10 | Engineer scales `userpool` 4 to 5 in the portal. Pods schedule ([02](outputs/02-kubectl-after-scale.txt)) |
| ~14:15 | While in the portal, the AKS upgrade channel is set to `none` and nested blob public access is switched on for the backup account (someone "trying to get a restore test working") |
| ~15:20 | Someone creates blob container `brutus-manual-restore` by hand for a restore drill |
| any time | Azure Policy adds tag `CostCentre = CC-4471` to the backup account |
| Wed 11 Nov 13:00 | Nightly scan (02:00 UTC) reports exit code 2 ([03](outputs/03-terraform-plan-refresh-only.txt)) |

## Step 1: detect

```bash
terraform plan -refresh-only -detailed-exitcode -lock=false -out=drift.tfplan   # exit 0 = clean, 1 = error, 2 = drift
```

Run it nightly with a **read-only scanner identity** ([example workflow](example-workflows/drift-detection.github-actions.yml)).
Output: [`03`](outputs/03-terraform-plan-refresh-only.txt). Note what it does *not* show: the unmanaged container. A
refresh-only plan only looks at objects already in state, so unmanaged objects need a separate inventory
([`05`](outputs/05-unmanaged-container-inventory.txt)).

## Step 2: triage, per attribute

`terraform show -json drift.tfplan | jq -f example-workflows/drift-attrs.jq` gives four attribute changes
([`04`](outputs/04-terraform-show-json-excerpt.txt)). Send **only that** to the AI (a few hundred tokens), not the state
of ~160 resources. The AI suggests, the app team that owns the resource decides.

| # | Resource / attribute | Terraform thinks | Azure now | Verdict | Fix |
| --- | --- | --- | --- | --- | --- |
| 1 | `azurerm_kubernetes_cluster_node_pool.user` `node_count` | 4 | 5 | **Keep** (intended) | Change code to `5` |
| 2 | `azurerm_kubernetes_cluster.main` `automatic_upgrade_channel` | `patch` | `none` | **Revert** (unwanted) | Leave code, normal apply |
| 3 | `azurerm_storage_account.cnpg_backups` `allow_nested_items_to_be_public` | `false` | `true` | **Revert** (unwanted, security) | Leave code, normal apply |
| 4 | `azurerm_storage_account.cnpg_backups` `tags["CostCentre"]` | absent | `CC-4471` (Azure Policy) | **Ignore** (noise) | `lifecycle { ignore_changes = [tags["CostCentre"]] }` |
| 5 | Container `brutus-manual-restore` (not in state) | n/a | exists | **Import** (see below) | `import` block plus a resource |

### Import or delete (row 5)

* **Delete** is right if the container is a leftover copy and nobody needs it. It also fixes a hidden risk: the
  customer containers are meant to be private and exactly one per customer.
* **Import** is right if it is still in use and will recur. Here the brutus team confirmed they run restore drills
  into it (it holds a `base/` and `wals/` copy, see `05`), so deleting would break a live process.
* Chosen: **import** (the owner confirmed). Its `container_access_type` is `private`, so the import plan is a no-change import. If
  the owner had said "throwaway", the fix would be `az storage container delete`, not Terraform.

## Step 3: fix the code, then plan

Code change (commit 2): `node_count = 5`, `ignore_changes = [tags["CostCentre"]]`, an `import` block and a
`azurerm_storage_container.brutus_manual_restore` resource. The two reverts need **no code**: the code already says the
right thing.

```bash
terraform plan -out=fix.tfplan
```

[`06`](outputs/06-terraform-plan-after-fix.txt) must show **only** the reverts and the import: upgrade channel back to
`patch`, public access back to `false`, 1 import. No `node_count`, no `CostCentre`, no `-/+`.
Result: `Plan: 1 to import, 0 to add, 2 to change, 0 to destroy.`

## Step 4: apply, then prove it is clean

[`07`](outputs/07-terraform-apply.txt): `Apply complete! Resources: 1 imported, 0 added, 2 changed, 0 destroyed.`
Next night's scan: [`08`](outputs/08-terraform-plan-clean.txt) returns `No changes` and exit code 0.

## Why not `terraform apply -refresh-only` here?

It accepts **everything** Azure currently has into state, the two bad changes included. State would then say
`automatic_upgrade_channel = none`, the plan would show a diff the next time someone looks, and the unwanted changes
would be hidden until then. Use `-refresh-only` apply only when *all* drift is intended. For mixed drift, fix the code for the
keepers and let a normal apply revert the rest.

## Caveats

* **Replacements.** If a revert showed `-/+` or `# forces replacement` (for example, hypothetically, someone had
  rebuilt the node pool with another `vm_size`, so reverting would destroy and recreate it), do **not** let it ride in the same apply.
  Hold that change back and raise a separate PR with a maintenance window. This scenario has none.
* **`-target`.** If you must use `-target` once to unblock the rest, do it by hand as a one-off. Never leave
  `-target` in the pipeline: it skips dependencies and quietly leaves the rest of the drift in place.
* **Read-only scanner.** Refresh of the backup account via `primary_connection_string` needs `listKeys`, which the built-in
  Reader role lacks. In practice this means a custom role for the scanner, or a design that avoids key-based reads.

## Prevention

* **No standing write access in the portal.** Fixes go through the app team's pipeline. Break-glass changes use PIM
  (Entra P2) for time-limited, scoped access, which also leaves an audit trail.
* **Azure Policy** to deny or audit changes that bypass the pipeline (public blob access, upgrade channel). It is the
  only control that stops the change at the moment someone tries it.
* **Read-only scanner identity** with workload identity federation (no secrets). Remediation runs under the app
  team's pipeline identity, not the scanner's.
* **Cost control:** only drifted attributes go to the AI, never full state.
* Fix orphaned state files (no repo or pipeline linked) first: nobody owns them, so they drift the longest.
