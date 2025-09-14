# External-DNS Migration to AdGuard Webhook

## Migration Summary

The migration from ingress-nginx external-dns to AdGuard external-dns webhook has been completed. The changes preserve the existing Cloudflare DNS configuration while adding new AdGuard webhook support.

## Changes Made

### 1. Directory Restructure
- **Renamed**: `kubernetes/apps/network/external-dns/` → `kubernetes/apps/network/cloudflare-dns/`
- **Created**: New `kubernetes/apps/network/external-dns/` with AdGuard webhook configuration

### 2. Cloudflare DNS (preserved existing functionality)
- **Location**: `kubernetes/apps/network/cloudflare-dns/`
- **Provider**: Cloudflare with CF_API_TOKEN
- **Sources**: CRD, ingress
- **Ingress Class**: external
- **Secret**: `cloudflare-dns-secret`

### 3. AdGuard DNS (new webhook implementation)
- **Location**: `kubernetes/apps/network/external-dns/`
- **Provider**: webhook (`ghcr.io/muhlba91/external-dns-provider-adguard:v9.1.0`)
- **Sources**: gateway-httproute, service
- **Ingress Class**: internal
- **Secret**: `adguard-dns-secret`
- **Managed Record Types**: A, AAAA, TXT, SRV

### 4. Updated References
- Network kustomization includes both configurations
- Cloudflared dependency updated to reference `cloudflare-dns`
- Helm repository remains shared between both implementations

## Next Steps Required

### 1. Configure AdGuard Credentials
The AdGuard secret template needs to be populated with real credentials:

```yaml
# In kubernetes/apps/network/external-dns/app/secret.sops.yaml
stringData:
    ADGUARD_URL: https://your-adguard-home-instance.local
    ADGUARD_USER: your-adguard-username  
    ADGUARD_PASSWORD: your-adguard-password
```

Then encrypt with SOPS:
```bash
sops -e -i kubernetes/apps/network/external-dns/app/secret.sops.yaml
```

### 2. Test Configuration
1. Apply configurations to cluster
2. Verify both DNS providers are running
3. Test DNS record creation/management
4. Monitor webhook health endpoints

### 3. Optional: Remove Cloudflare DNS
If AdGuard webhook works correctly and you want to fully migrate:
1. Remove `cloudflare-dns` directory
2. Update network kustomization
3. Update cloudflared dependencies if needed

## Configuration Differences

| Aspect | Cloudflare DNS | AdGuard DNS |
|--------|----------------|-------------|
| Provider | cloudflare | webhook |
| Sources | crd, ingress | gateway-httproute, service |
| Ingress Class | external | internal |
| Authentication | CF_API_TOKEN | ADGUARD_URL/USER/PASSWORD |
| Proxy Support | --cloudflare-proxied | N/A |
| Records | All types | A, AAAA, TXT, SRV |

Both configurations use the same domain filter (`${SECRET_DOMAIN}`) and txt ownership settings.