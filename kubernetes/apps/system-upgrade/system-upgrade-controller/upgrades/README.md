---
# Upgrade Plans
#
# This directory contains system upgrade plans that can be applied manually.
# Unlike automatic upgrade systems, these plans are applied on-demand when you're
# ready to perform an upgrade.
#
# ## Usage
#
# 1. Review the upgrade plan file (e.g., talos-v1.11.5.yaml)
# 2. Change `version: "hold"` to the desired version (e.g., `version: "v1.11.5"`)
# 3. Commit and push the change
# 4. Flux will apply the plan automatically
# 5. Monitor with: `kubectl -n system-upgrade get plans,jobs,pods -w`
# 6. After upgrade completes, change version back to `"hold"` to prevent re-runs
#
# ## Creating New Upgrade Plans
#
# Copy an existing plan and update:
# - metadata.name (e.g., talos-v1-12-0)
# - spec.version (set to "hold" initially)
# - spec.upgrade.image (use the new version tag)
#
# ## Safety
#
# - Plans with `version: "hold"` will not execute
# - Only one plan should be active (not "hold") at a time
# - Monitor the upgrade process before enabling the next plan
#
# ## Example from onedr0p
#
# See: https://github.com/onedr0p/home-ops/tree/main/kubernetes/apps/system-upgrade/tuppr/upgrades
