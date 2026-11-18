# Reduce a refresh-only plan (terraform show -json) to attribute-level drift.
# Input : terraform show -json drift.tfplan
# Output: [{address, attribute, before, after}, ...]  - small enough to hand to an AI triage step.
# Sensitive values are dropped using the plan's own before_sensitive/after_sensitive markers.
[ .resource_drift[]
  | . as $r
  | ($r.change.before // {}) as $b
  | ($r.change.after  // {}) as $a
  | ($r.change.after_sensitive // {}) as $s
  | ([ ($b|keys[]), ($a|keys[]) ] | unique[]) as $k
  | select($b[$k] != $a[$k])
  | select(($s[$k] // false) != true)
  | { address: $r.address, attribute: $k, before: $b[$k], after: $a[$k] }
]
