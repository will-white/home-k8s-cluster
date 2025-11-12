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

## CI/CD Pipeline Enhancements

### High Priority

- [ ] **Security Scanning Workflows**
  - [ ] Container Image Vulnerability Scanning (Trivy)
    - Scan images in HelmReleases for CVEs
    - Run on PRs that change image tags
    - Create security advisories for critical issues
    - Integrate with GitHub Security tab
    - File: `.github/workflows/trivy-scan.yaml`
  - [ ] SOPS Secret Validation
    - Verify all secrets are properly encrypted
    - Check for accidentally committed unencrypted data
    - Validate SOPS metadata integrity
    - Ensure age keys are properly referenced
    - File: `.github/workflows/sops-validation.yaml`
  - [ ] Kubernetes Security Policy Scanning (Polaris/Datree)
    - Validate security contexts, resource limits
    - Check for deprecated API versions
    - Enforce pod security standards
    - Scan for misconfigurations
    - File: `.github/workflows/k8s-security.yaml`

- [ ] **Helm Chart Testing**
  - [ ] Validate Helm values schema
  - [ ] Test chart rendering with different values
  - [ ] Check for required values
  - [ ] Validate against chart JSON schemas
  - [ ] File: `.github/workflows/helm-test.yaml`

- [ ] **Link Checking & Documentation**
  - [ ] Broken Link Checker
    - Check for broken URLs in documentation
    - Validate Helm chart repository URLs
    - Check external dependencies availability
    - Verify container registry accessibility
    - File: `.github/workflows/link-checker.yaml`
  - [ ] Documentation Generation
    - Auto-generate application inventory
    - Create cluster topology diagrams
    - Generate resource usage reports
    - Update README with current versions
    - File: `.github/workflows/docs-generation.yaml`

- [ ] **OPA/Kyverno Policy Validation**
  - [ ] Enforce naming conventions
  - [ ] Validate label requirements
  - [ ] Check namespace isolation
  - [ ] Verify network policies
  - [ ] File: `.github/workflows/policy-validation.yaml`

### Medium Priority

- [ ] **Testing Workflows**
  - [ ] End-to-End Smoke Tests
    - Deploy to ephemeral test cluster (kind/k3s)
    - Run basic health checks
    - Test critical ingress routes
    - Validate DNS configuration
    - File: `.github/workflows/e2e-tests.yaml`
  - [ ] Flux Health Checks
    - Validate Flux source configurations
    - Check for reconciliation issues
    - Test Flux notification providers
    - Validate image automation configs
    - File: `.github/workflows/flux-health.yaml`

- [ ] **Release Management**
  - [ ] Changelog Generation
    - Auto-generate changelogs from commits
    - Categorize changes (apps, infra, security)
    - Track version bumps
    - Generate release notes
    - File: `.github/workflows/changelog.yaml`
  - [ ] Semantic Versioning
    - Enforce semantic commit messages
    - Auto-tag releases
    - Track major/minor/patch changes
    - Generate version badges

- [ ] **Resource & Cost Analysis**
  - [ ] Resource Recommendations (Goldilocks/VPA)
    - Analyze resource requests/limits
    - Suggest optimizations
    - Track resource trends over time
    - Detect over/under-provisioned resources
  - [ ] Cost Estimation
    - Calculate cluster resource costs
    - Track changes in resource allocation
    - Alert on significant cost increases

- [ ] **Backup & Disaster Recovery**
  - [ ] Backup Validation
    - Verify backup configurations exist
    - Test restore procedures (in staging)
    - Validate VolSync configurations
    - Check PVC backup coverage
  - [ ] ETCD/Talos Backup Validation
    - Verify backup schedules
    - Test backup accessibility
    - Validate encryption keys

### Low Priority

- [ ] **Performance & Observability**
  - [ ] Manifest Size & Complexity Analysis
    - Track manifest growth over time
    - Detect overly complex resources
    - Identify duplicate configurations
    - Suggest refactoring opportunities
  - [ ] Dependency Graph Generation
    - Visualize service dependencies
    - Detect circular dependencies
    - Generate component diagrams
    - Track dependency changes

- [ ] **Integration Testing**
  - [ ] External Service Health Checks
    - Validate external integrations (Bitwarden, Cloudflare)
    - Test webhook endpoints
    - Check API rate limits
    - Verify DNS resolution
  - [ ] Application-Specific Tests
    - Test media stack integration (Radarr → qBittorrent)
    - Validate monitoring stack (Prometheus → Grafana)
    - Check ingress routing
    - Test cert-manager certificate issuance

- [ ] **Notifications & Reporting**
  - [ ] Slack/Discord/Email Notifications
    - PR status summaries
    - Deployment notifications
    - Security alerts
    - Failed workflow alerts
  - [ ] Weekly/Monthly Reports
    - Cluster health summary
    - Resource usage trends
    - Security findings
    - Dependency update summary

- [ ] **Configuration Drift Detection**
  - [ ] Compare cluster state with Git
  - [ ] Detect manual changes
  - [ ] Alert on out-of-sync resources
  - [ ] Generate drift reports

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

- [x] **2025-11-12**: CI/CD Pipeline Quick Wins
  - Implemented GitHub Actions caching for workflow tools
    - Added tool caching to kubeconform, agent-validation, and flux-diff workflows
    - Reduces execution time by ~30-50% on cache hits
  - Enabled parallel job execution in flux-diff workflow
    - Matrix jobs now run simultaneously (fail-fast: false, max-parallel: 2)
    - Cuts PR feedback time in half
  - Created reusable workflow templates
    - New setup-tools.yaml for consistent tool installation
    - Supports configurable tool lists and built-in caching
  - Optimized tool installation
    - Replaced Homebrew with direct binary downloads (faster, more reliable)
    - Pinned tool versions for reproducibility

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
