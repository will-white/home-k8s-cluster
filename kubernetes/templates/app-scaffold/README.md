# Application Scaffold Template

This directory contains templates for quickly scaffolding new applications.

## Usage

### Using the Template

1. **Copy the template**:
   ```bash
   cp -r kubernetes/templates/app-scaffold kubernetes/apps/<namespace>/<app-name>
   ```

2. **Replace placeholders**:
   - `<APP-NAME>`: Your application name (e.g., `my-app`)
   - `<NAMESPACE>`: Target namespace (e.g., `default`, `media`, `database`)
   - `<CHART-NAME>`: Helm chart name
   - `<CHART-VERSION>`: Helm chart version
   - `<REPO-NAME>`: Helm repository name (e.g., `bjw-s`, `prometheus-community`)

3. **Customize the configuration**:
   - Edit `app/helmrelease.yaml` with your chart values
   - Remove optional files you don't need (externalsecret.yaml, pvc.yaml, etc.)
   - Update `app/kustomization.yaml` to reference only the files you're using

4. **Add to namespace kustomization**:
   ```bash
   # Edit kubernetes/apps/<namespace>/kustomization.yaml
   # Add: - ./<app-name>/ks.yaml
   ```

5. **Validate**:
   ```bash
   task kubernetes:kubeconform
   ```

## Template Files

### Required Files
- `ks.yaml` - Flux Kustomization (entry point)
- `app/helmrelease.yaml` - Helm chart deployment
- `app/kustomization.yaml` - Kustomize configuration

### Optional Files
- `app/externalsecret.yaml` - For Bitwarden secrets
- `app/pvc.yaml` - For persistent storage
- `app/configmap.yaml` - For configuration data
- `app/networkpolicy.yaml` - For network isolation
- `app/servicemonitor.yaml` - For Prometheus metrics

## Example: Adding a New App

```bash
# 1. Ask user for namespace (CRITICAL - never assume!)
echo "Which namespace should this app be deployed to?"

# 2. Copy template
cp -r kubernetes/templates/app-scaffold kubernetes/apps/media/bazarr

# 3. Edit files (replace placeholders)
cd kubernetes/apps/media/bazarr

# 4. Customize for your app
# - Edit app/helmrelease.yaml
# - Remove unused optional files
# - Update app/kustomization.yaml

# 5. Add to namespace kustomization
# Edit kubernetes/apps/media/kustomization.yaml
# Add: - ./bazarr/ks.yaml

# 6. Validate
task kubernetes:kubeconform
```

## Template Variations

### Standard App (bjw-s app-template)
Use the base template in this directory for most applications using the bjw-s app-template chart.

### Database App
For database applications, consider:
- Using `cloudnative-pg` for PostgreSQL
- Adding backup configuration (VolSync)
- Network policies for security

### Stateful App with Storage
For apps requiring persistent storage:
- Include `app/pvc.yaml`
- Set appropriate storage class (`ceph-block`, `ceph-filesystem`)
- Configure backup strategy

### Monitored App
For apps with Prometheus metrics:
- Include `app/servicemonitor.yaml`
- Configure scrape interval and timeout
- Import or create Grafana dashboard

## Pre-Configured Templates

Additional specialized templates available:

- **volsync**: Backup configuration template
- **gatus**: Health monitoring template

See respective directories for usage instructions.
