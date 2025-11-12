# Cluster TODO List

## Observability Enhancements

### High Priority

- [ ] **Talos Node Metrics**
  - Add ScrapeConfig for Talos kubelet metrics (port 10250)
  - Configure TLS certificates for secure scraping
  - Add Talos-specific Grafana dashboard
  - File: `kubernetes/apps/observability/kube-prometheus-stack/app/scrapeconfig.yaml`

- [ ] **Custom Prometheus Alerts**
  - Create PrometheusRules for media app metrics
    - Alert on stuck download queues (> 24 hours)
    - Alert on failed downloads
    - Alert on indexer failures (Prowlarr)
  - Create alerts for Home Assistant
    - Entity unavailable alerts
    - Automation failure alerts
  - Create alerts for Frigate
    - Camera offline alerts
    - Low FPS warnings
  - File: `kubernetes/apps/observability/kube-prometheus-stack/app/prometheusrules/`

### Medium Priority

- [ ] **Enable Blackbox Exporter**
  - Uncomment blackbox-exporter in kustomization
  - Configure probes for critical endpoints
  - Add ServiceMonitors for external services
  - File: `kubernetes/apps/observability/kustomization.yaml`

- [ ] **PostgreSQL Query Performance Metrics**
  - Enable pg_stat_statements in PostgreSQL
  - Create custom queries for slow query monitoring
  - Add queries to CloudNative-PG monitoring configmap
  - Import PostgreSQL performance dashboard
  - File: `kubernetes/apps/database/cloudnative-pg/cluster/cluster16.yaml`

- [ ] **Autobrr Metrics** (if supported in future)
  - Check if Autobrr adds `/api/metrics` endpoint
  - Add ServiceMonitor for metrics collection
  - Create or import Autobrr dashboard
  - File: `kubernetes/apps/media/autobrr/app/helmrelease.yaml`

### Low Priority

- [ ] **Custom Frigate Dashboard**
  - Create dashboard with camera-specific panels
  - Add object detection breakdown by camera
  - Include clip and snapshot storage metrics
  - Add detection zone heatmaps
  - File: `kubernetes/apps/observability/grafana/app/resources/dashboards/`

- [ ] **Media Stack Composite Dashboard**
  - Create unified dashboard showing:
    - All *arr app queue status
    - qBittorrent active torrents
    - Storage utilization for media
    - Recent activity timeline
  - File: `kubernetes/apps/observability/grafana/app/resources/dashboards/`

- [ ] **Application Uptime Monitoring**
  - Add ServiceMonitors for less-critical apps:
    - Mealie
    - Tandoor
    - Homebox
    - Stirling-PDF
    - Plant-it
  - Even without Prometheus metrics, monitor HTTP availability
  - Use Blackbox Exporter for HTTP probes

- [ ] **EMQX MQTT Metrics**
  - Verify EMQX Prometheus endpoint configuration
  - Create custom dashboard for MQTT topics
  - Monitor Zigbee2MQTT message rates via EMQX
  - File: `kubernetes/apps/database/emqx/cluster/cluster.yaml`

- [ ] **Storage Performance Metrics**
  - Add NFS mount performance monitoring
  - Monitor CEPH client latency
  - Track PVC usage growth rate
  - Create storage performance dashboard

## Infrastructure Improvements

- [ ] **Rclone RGW to Garage Migration**
  - Configure rclone to sync from Ceph RGW to Garage instance on TrueNAS
  - Set up Garage S3-compatible storage on TrueNAS box
  - Create rclone configuration for both endpoints
  - Test sync performance and reliability
  - Document sync schedule and retention policy

- [ ] **Cluster Backup Validation**
  - Verify VolSync backups are working
  - Test restoration procedures
  - Document recovery process

- [ ] **Security Scanning**
  - Add Trivy for container vulnerability scanning
  - Configure automated scan reports
  - Create dashboard for vulnerability tracking

- [ ] **Resource Optimization**
  - Review pod resource requests/limits
  - Identify over/under-provisioned pods
  - Adjust based on actual usage patterns

- [ ] **Network Policies**
  - Audit current network policies
  - Add policies for namespace isolation
  - Document network flow requirements

## Application Enhancements

- [ ] **High Availability**
  - Review single-point-of-failure services
  - Consider multi-replica for critical apps
  - Implement pod disruption budgets

- [ ] **Backup Strategy**
  - Document backup schedule for each app
  - Verify S3 backup destinations
  - Test restore procedures quarterly

## Documentation

- [ ] **Architecture Diagram**
  - Create visual cluster topology
  - Document ingress flow
  - Map storage architecture

- [ ] **Runbook**
  - Common troubleshooting procedures
  - Disaster recovery steps
  - Scaling guidelines

- [ ] **Monitoring Guide**
  - Document what each dashboard shows
  - Define alert response procedures
  - Create metrics glossary

---

## Completed Items

- [x] **2025-11-12**: Add Prometheus monitoring for media namespace
  - Added Exportarr sidecars for Radarr, Sonarr, Prowlarr, Bazarr
  - Added qBittorrent Prometheus exporter
  - Coverage improved from 10% to 67%

- [x] **2025-11-12**: Add Prometheus monitoring for home automation
  - Added Home Assistant ServiceMonitor
  - Added Frigate ServiceMonitor
  - Coverage improved from 0% to 67%

- [x] **2025-11-12**: Enable CloudNative-PG operator monitoring
  - Enabled podMonitorEnabled in HelmRelease
  - Coverage improved from 67% to 100%

- [x] **2025-11-12**: Import Grafana dashboards
  - CloudNative-PG (gnetId: 20417)
  - Exportarr (gnetId: 19817)
  - qBittorrent (gnetId: 15080)
  - Home Assistant (gnetId: 15309)

---

## Notes

- When adding new metrics, always consider:
  - Scrape interval (balance between freshness and load)
  - Resource impact (CPU/memory for exporters)
  - Alert thresholds (avoid alert fatigue)
  - Dashboard placement (logical grouping)

- Priority levels:
  - **High**: Critical for operations or security
  - **Medium**: Improves observability or efficiency
  - **Low**: Nice-to-have or convenience features
