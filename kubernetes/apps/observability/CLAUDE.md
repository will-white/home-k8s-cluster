# observability — domain guide (`@observability-agent`)

Loaded automatically for work under `kubernetes/apps/observability/`, and the
role to adopt for any `ServiceMonitor`, `PodMonitor`, `PrometheusRule`, `Probe`,
Loki rule, Grafana dashboard or Gatus endpoint anywhere in the repo.

## Domain

scrape → store → query → alert → dashboard → uptime

| Layer | Apps |
|---|---|
| Metrics | kube-prometheus-stack (Prometheus, Alertmanager → Pushover), blackbox-exporter, smartctl-exporter, snmp-exporter, opnsense-exporter, adguard-exporter, x509-certificate-exporter, node-exporter-lab, node-exporter-truenas |
| Logs | loki (ruler reads labelled ConfigMaps), alloy (DaemonSet collector, pipeline in its HelmRelease `configMap.content`) |
| Dashboards | grafana |
| Synthetic / uptime | gatus (discovers ConfigMaps labelled `gatus.io/enabled: "true"` cluster-wide) |

## Delivery patterns (follow exactly)

- **Scrape** via `ServiceMonitor` / `PodMonitor` selectors (app-template
  `serviceMonitor:` block), never static configs. Apps must expose a `metrics`
  port; if something has no native metrics, add an exporter.
- **Platform alerts** live in
  `kube-prometheus-stack/app/prometheusrules/<component>.yaml`; **app alerts**
  live next to the app (`prometheusrule.yaml` or `resources/lokirule.yaml`).
  Every rule sets `severity` and `summary` / `description`, justifies its
  threshold in `description`, and links a runbook when one exists.
- **Loki rules**: `resources/lokirule.yaml` in the owning app, mounted through
  `configMapGenerator` with label `loki_rule: "true"`. Loki does not validate
  them on load: run `task kubernetes:rules-lint` (promtool, lokitool, alloy
  validate) before proposing.
- **Dashboards**: ConfigMap with label `grafana_dashboard: "1"` in this
  namespace, or a pinned upstream URL / gnetId in the grafana HelmRelease (add
  the `# renovate: depName=` comment for gnetId ones). Do not set a
  `datasource:` key on mixin dashboards that template `${loki_datasource}`:
  the chart's sed would clobber it. Never edit a dashboard live and forget it.
- **Logs** carry `namespace`, `pod`, `container`, `app` labels at minimum; keep
  high-cardinality values (request IDs, users) out of labels.
- **Gatus** endpoints come from `kubernetes/templates/gatus/{guarded,external}`
  referenced in the app's kustomization; TCP checks are a ConfigMap with the
  same label.
- **Resources**: Prometheus and Loki have `resources.requests` and
  `limits.memory`; Loki retention is explicit.
- **Secrets** (Alertmanager receivers, Grafana admin, exporter credentials):
  `ExternalSecret` only.

## Heuristics

- A new app anywhere: propose (separately) a `ServiceMonitor` if it exports
  metrics, a Gatus endpoint if it has a UI/API, and a dashboard if upstream
  ships a good one.
- Every new `PrometheusRule` gets a dashboard panel showing the same
  condition; alerts without dashboards are hard to triage.
- Fewer well-tuned dashboards over imported clutter; remove ones that do not
  load or duplicate others.

## Boundaries

- You may add monitors, rules and dashboard ConfigMaps inside other namespace
  folders, but not change their `HelmRelease`, `Kustomization`,
  `ExternalSecret` or PVCs: coordinate with the owning role.
- kube-prometheus-stack, loki, grafana and alloy chart versions / CRDs go
  through `@infra-agent`.
- Never silence or delete an alert to make a dashboard green; fix the cause or
  change the rule with a written justification.

## Validate

```bash
task kubernetes:validate APP=<ns>/<app>      # wraps the checks below
kustomize build --load-restrictor=LoadRestrictionsNone kubernetes/apps/observability/<app>/app | kubeconform -strict -ignore-missing-schemas -skip Secret,ExternalSecret,ReplicationSource,ReplicationDestination,HTTPRoute -
task kubernetes:rules-lint
yamllint kubernetes/apps/observability/
kubectl -n observability get servicemonitor,prometheusrule,pods   # read-only
kubectl -n observability exec sts/prometheus-kube-prometheus-stack-prometheus -- promtool query instant http://localhost:9090 '<expr>'
```
