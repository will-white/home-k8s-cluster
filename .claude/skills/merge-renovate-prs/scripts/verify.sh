#!/usr/bin/env bash
# Bounded post-merge verification for one app (SKILL.md §8).
#
#   verify.sh -n <namespace> <app> [--chart <version>] [--image <substring>] [--timeout <sec>]
#             [--label <selector>] [--commit <sha>]
#
# Succeeds (exit 0) when the app's Flux Kustomization has applied --commit (default:
# origin/main after a fetch — i.e. the merge you just made) or a later commit, the
# HelmRelease is Ready for its current generation, its attempted revision matches
# --chart (if given), every pod matching the label selector is Running with all
# containers ready, every container image contains --image (if given), and no
# container restarted during the wait. Without --label the selector is
# app.kubernetes.io/name=<app>, else app.kubernetes.io/instance=<app>; if neither
# matches any pod the pod checks are skipped with a WARN (pass --label).
# Exit 1 on timeout, exit 2 on a detected failure (HelmRelease Ready=False with a
# failure reason, CrashLoopBackOff, ImagePullBackOff). Prints the last events on
# failure. Read-only; never reconciles.
set -uo pipefail
ns="" app="" chart="" image="" timeout=600 label="" commit=""
while [ $# -gt 0 ]; do
  case "$1" in
    -n|--namespace) ns="$2"; shift 2 ;;
    --chart) chart="$2"; shift 2 ;;
    --image) image="$2"; shift 2 ;;
    --timeout) timeout="$2"; shift 2 ;;
    --label) label="$2"; shift 2 ;;
    --commit) commit="$2"; shift 2 ;;
    -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
    *) app="$1"; shift ;;
  esac
done
[ -n "$ns" ] && [ -n "$app" ] || { echo "usage: verify.sh -n <ns> <app> [--chart v] [--image s] [--timeout s] [--label sel] [--commit sha]" >&2; exit 64; }
root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
export KUBECONFIG="${KUBECONFIG:-$root/kubeconfig}"
K="kubectl --request-timeout=10s"

# The commit Flux must have applied before anything else counts: without it, a check
# run right after the merge passes on the *old* rollout (no --image/--chart to tell).
if [ -z "$commit" ]; then
  git -C "$root" fetch -q origin main 2>/dev/null
  commit="$(git -C "$root" rev-parse origin/main 2>/dev/null)"
fi
# the app's Kustomization: by path, else by name
ks="$($K get ks -n flux-system -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.path}{"\n"}{end}' 2>/dev/null \
      | awk -F'\t' -v p="./kubernetes/apps/$ns/$app/app" '$2==p {print $1; exit}')"
[ -n "$ks" ] || ks="$($K get ks -n flux-system "$app" -o name 2>/dev/null | cut -d/ -f2)"
[ -n "$ks" ] || echo "WARN: no Flux Kustomization found for $ns/$app — cannot confirm commit ${commit:0:8} was applied"

if [ -z "$label" ]; then
  for cand in "app.kubernetes.io/name=$app" "app.kubernetes.io/instance=$app"; do
    [ -n "$($K get pods -n "$ns" -l "$cand" -o name 2>/dev/null | head -1)" ] && { label="$cand"; break; }
  done
  [ -n "$label" ] || echo "WARN: no pods labelled app.kubernetes.io/{name,instance}=$app — checking the HelmRelease only; pass --label to check pods"
fi

restarts_now() {
  [ -n "$label" ] || { echo 0; return; }
  $K get pods -n "$ns" -l "$label" -o jsonpath='{range .items[*]}{range .status.containerStatuses[*]}{.restartCount}{" "}{end}{end}' 2>/dev/null | awk '{s=0; for(i=1;i<=NF;i++) s+=$i; print s+0}'
}
start_restarts="$(restarts_now)"
deadline=$(( $(date +%s) + timeout ))
echo "verify $ns/$app commit=${commit:0:8} ks=${ks:-none} chart='${chart:-any}' image='${image:-any}' label='${label:-none}' timeout=${timeout}s (restarts at start: ${start_restarts:-0})"

applied() {  # has the Kustomization applied $commit or a descendant of it?
  [ -n "$ks" ] && [ -n "$commit" ] || return 0
  local rev; rev="$($K get ks -n flux-system "$ks" -o jsonpath='{.status.lastAppliedRevision}' 2>/dev/null)"; rev="${rev##*:}"
  [ -n "$rev" ] || return 1
  [ "$rev" = "$commit" ] && return 0
  git -C "$root" cat-file -e "$rev" 2>/dev/null || git -C "$root" fetch -q origin main 2>/dev/null
  git -C "$root" merge-base --is-ancestor "$commit" "$rev" 2>/dev/null
}

while :; do
  hr="$($K get hr -n "$ns" "$app" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}|{.status.lastAttemptedRevision}|{.metadata.generation}/{.status.observedGeneration}|{.status.conditions[?(@.type=="Ready")].reason}|{.status.conditions[?(@.type=="Ready")].message}' 2>/dev/null)"
  hr_ready="${hr%%|*}"; rest="${hr#*|}"; hr_rev="${rest%%|*}"; rest="${rest#*|}"; hr_gen="${rest%%|*}"; rest="${rest#*|}"; hr_reason="${rest%%|*}"; hr_msg="${rest#*|}"
  pods=""
  [ -z "$label" ] || pods="$($K get pods -n "$ns" -l "$label" -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.phase}{"\t"}{range .status.containerStatuses[*]}{.ready}{","}{end}{"\t"}{range .spec.containers[*]}{.image}{","}{end}{"\t"}{range .status.containerStatuses[*]}{.state.waiting.reason}{","}{end}{"\n"}{end}' 2>/dev/null)"
  now_restarts="$(restarts_now)"

  ok=1; why=""
  applied || { ok=0; why+="ks/$ks has not applied ${commit:0:8} yet; "; }
  [ "${hr_gen%/*}" = "${hr_gen#*/}" ] || { ok=0; why+="hr generation $hr_gen not observed yet; "; }
  [ "$hr_ready" = "True" ] || { ok=0; why+="hr not ready (${hr_reason}: ${hr_msg:0:120}); "; }
  if [ -n "$chart" ]; then case "$hr_rev" in "$chart"*) ;; *) ok=0; why+="hr revision '$hr_rev' != '$chart'; ";; esac; fi
  [ -z "$label" ] || [ -n "$pods" ] || { ok=0; why+="no pods for $label; "; }
  while IFS=$'\t' read -r name phase readies images waiting; do
    [ -n "$name" ] || continue
    [ "$phase" = "Running" ] || { ok=0; why+="$name $phase; "; }
    case "$readies" in *false*) ok=0; why+="$name container not ready; ";; esac
    if [ -n "$image" ]; then case "$images" in *"$image"*) ;; *) ok=0; why+="$name image lacks '$image' (${images%,}); ";; esac; fi
    case "$waiting" in *CrashLoopBackOff*|*ImagePullBackOff*|*ErrImagePull*|*CreateContainerConfigError*)
      echo "FAIL: $name waiting: ${waiting%,}"; $K get events -n "$ns" --sort-by=.lastTimestamp 2>/dev/null | grep -i "$app" | tail -8; exit 2 ;;
    esac
  done <<< "$pods"
  if [ "${now_restarts:-0}" -gt "${start_restarts:-0}" ]; then
    ok=0; why+="restarts ${start_restarts}→${now_restarts}; "
  fi
  case "$hr_reason" in *Failed*|*failed*)
    echo "FAIL: HelmRelease $ns/$app $hr_reason: $hr_msg"; $K get events -n "$ns" --sort-by=.lastTimestamp 2>/dev/null | grep -i "$app" | tail -8; exit 2 ;;
  esac

  if [ "$ok" = 1 ]; then
    echo "OK: ks/${ks:-?} applied ${commit:0:8}; hr Ready rev=$hr_rev; pods:${label:+ ($label)}"
    [ -n "$pods" ] && printf '%s\n' "$pods" | awk -F'\t' '{print "  " $1 " " $2 " images=" $4}'
    [ -n "$label" ] || echo "  (pod checks skipped — no pods matched; pass --label)"
    exit 0
  fi
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "TIMEOUT after ${timeout}s: $why"; $K get events -n "$ns" --sort-by=.lastTimestamp 2>/dev/null | grep -i "$app" | tail -8; exit 1
  fi
  echo "$(date +%H:%M:%S) waiting: $why"
  sleep 20
done
