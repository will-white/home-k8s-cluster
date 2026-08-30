#!/usr/bin/env bash
# Bounded post-merge verification for one app (SKILL.md §8).
#
#   verify.sh -n <namespace> <app> [--chart <version>] [--image <substring>] [--timeout <sec>] [--label <selector>]
#
# Succeeds (exit 0) when the HelmRelease is Ready, its attempted revision matches
# --chart (if given), every pod matching the label selector is Running with all
# containers ready, every container image contains --image (if given), and no
# container restarted during the wait. Exit 1 on timeout, exit 2 on a detected
# failure (HelmRelease Ready=False with a failure reason, CrashLoopBackOff,
# ImagePullBackOff). Prints the last events on failure. Read-only; never
# reconciles.
set -uo pipefail
ns="" app="" chart="" image="" timeout=600 label=""
while [ $# -gt 0 ]; do
  case "$1" in
    -n|--namespace) ns="$2"; shift 2 ;;
    --chart) chart="$2"; shift 2 ;;
    --image) image="$2"; shift 2 ;;
    --timeout) timeout="$2"; shift 2 ;;
    --label) label="$2"; shift 2 ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) app="$1"; shift ;;
  esac
done
[ -n "$ns" ] && [ -n "$app" ] || { echo "usage: verify.sh -n <ns> <app> [--chart v] [--image s] [--timeout s] [--label sel]" >&2; exit 64; }
label="${label:-app.kubernetes.io/name=$app}"
root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
export KUBECONFIG="${KUBECONFIG:-$root/kubeconfig}"
K="kubectl --request-timeout=10s"

restarts_now() {
  $K get pods -n "$ns" -l "$label" -o jsonpath='{range .items[*]}{range .status.containerStatuses[*]}{.restartCount}{" "}{end}{end}' 2>/dev/null | awk '{s=0; for(i=1;i<=NF;i++) s+=$i; print s+0}'
}
start_restarts="$(restarts_now)"
deadline=$(( $(date +%s) + timeout ))
echo "verify $ns/$app chart='${chart:-any}' image='${image:-any}' label='$label' timeout=${timeout}s (restarts at start: ${start_restarts:-0})"

while :; do
  hr="$($K get hr -n "$ns" "$app" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}|{.status.lastAttemptedRevision}|{.status.conditions[?(@.type=="Ready")].reason}|{.status.conditions[?(@.type=="Ready")].message}' 2>/dev/null)"
  hr_ready="${hr%%|*}"; rest="${hr#*|}"; hr_rev="${rest%%|*}"; rest="${rest#*|}"; hr_reason="${rest%%|*}"; hr_msg="${rest#*|}"
  pods="$($K get pods -n "$ns" -l "$label" -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.phase}{"\t"}{range .status.containerStatuses[*]}{.ready}{","}{end}{"\t"}{range .spec.containers[*]}{.image}{","}{end}{"\t"}{range .status.containerStatuses[*]}{.state.waiting.reason}{","}{end}{"\n"}{end}' 2>/dev/null)"
  now_restarts="$(restarts_now)"

  ok=1; why=""
  [ "$hr_ready" = "True" ] || { ok=0; why+="hr not ready (${hr_reason}: ${hr_msg:0:120}); "; }
  if [ -n "$chart" ]; then case "$hr_rev" in "$chart"*) ;; *) ok=0; why+="hr revision '$hr_rev' != '$chart'; ";; esac; fi
  [ -n "$pods" ] || { ok=0; why+="no pods for $label; "; }
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
  case "$hr_reason" in *Failed*|*failed*|UpgradeFailed|InstallFailed)
    echo "FAIL: HelmRelease $ns/$app $hr_reason: $hr_msg"; $K get events -n "$ns" --sort-by=.lastTimestamp 2>/dev/null | grep -i "$app" | tail -8; exit 2 ;;
  esac

  if [ "$ok" = 1 ]; then
    echo "OK: hr Ready rev=$hr_rev; pods:"; printf '%s\n' "$pods" | awk -F'\t' '{print "  " $1 " " $2 " images=" $4}'
    exit 0
  fi
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "TIMEOUT after ${timeout}s: $why"; $K get events -n "$ns" --sort-by=.lastTimestamp 2>/dev/null | grep -i "$app" | tail -8; exit 1
  fi
  echo "$(date +%H:%M:%S) waiting: $why"
  sleep 20
done
