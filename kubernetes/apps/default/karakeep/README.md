# Karakeep Configuration

Karakeep is a self-hosted bookmarking application with AI tagging, web browsing, and search capabilities.

## Current Status

✅ **Basic Features**: Working
- Bookmark saving and management
- Full web crawling with JavaScript execution (browserless sidecar)
- Screenshot capture

✅ **Full Web Browsing**: Enabled (browserless sidecar container)
❌ **AI Tagging**: Disabled (add OPENAI_API_KEY to Bitwarden secret to enable)
❌ **Search Engine**: Disabled (no Meilisearch deployed)

## Enabling AI Tagging

### Option 1: OpenAI (Recommended for best quality)

1. Add `OPENAI_API_KEY` to your Bitwarden secret named `karakeep`:
   ```
   OPENAI_API_KEY=sk-...
   ```

2. The configuration uses GPT-4o-mini by default for both text and image inference
3. Karakeep will automatically start tagging new bookmarks with AI-generated tags

### Option 2: Ollama (Local, free)

1. Deploy Ollama to your cluster (see `MISSING_APPS.md`)
2. Uncomment the `OLLAMA_BASE_URL` line in `helmrelease.yaml`:
   ```yaml
   OLLAMA_BASE_URL: http://ollama.llm.svc.cluster.local:11434
   ```
3. Change the model names to Ollama models:
   ```yaml
   INFERENCE_TEXT_MODEL: llama3.2
   INFERENCE_IMAGE_MODEL: llava  # For image tagging
   ```

## Enabling Full Web Browsing

✅ **Already Enabled!** Karakeep is configured with a browserless Chromium sidecar container.

Web browsing features include:
- Full page screenshots with JavaScript execution
- Better content extraction from dynamic websites (SPAs)
- Video download support via yt-dlp

### Current Configuration

The browserless sidecar is already configured with:
- Image: `ghcr.io/browserless/chromium:latest`
- Port: 3001 (Karakeep uses port 3000)
- WebSocket: `ws://localhost:3001/playwright/chromium`
- Max concurrent sessions: 5
- Connection timeout: 5 minutes
- Resources: 512Mi RAM request, 2Gi limit

### Optional: Enable Full-Page Features

To store full-page screenshots and archives (uses more disk space), uncomment in `helmrelease.yaml`:
```yaml
CRAWLER_FULL_PAGE_SCREENSHOT: "true"
CRAWLER_FULL_PAGE_ARCHIVE: "true"
```

## Browser-less Mode (Not Recommended)

If you want to disable the browser sidecar and use HTTP-only crawling:

1. Remove the `browser` container from `helmrelease.yaml`
2. Comment out the `BROWSER_WEBSOCKET_URL` environment variable
3. Note: You'll lose JavaScript execution, screenshots, and video downloads

## Enabling Search Engine

Meilisearch provides fast full-text search across all your bookmarks.

1. Deploy Meilisearch (could use bjw-s app-template):
   ```yaml
   # Create a meilisearch deployment with persistent storage
   # Generate master key: openssl rand -base64 36 | tr -dc 'A-Za-z0-9'
   ```

2. Add `MEILI_MASTER_KEY` to your Bitwarden secret named `karakeep`

3. Uncomment the `MEILI_ADDR` line in `helmrelease.yaml`:
   ```yaml
   MEILI_ADDR: http://meilisearch.default.svc.cluster.local:7700
   ```

## Configuration Details

### Current Environment Variables

- `NEXTAUTH_URL`: https://karakeep.${SECRET_DOMAIN}
- `NEXTAUTH_SECRET`: From Bitwarden (required)
- `DATA_DIR`: /data (persistent volume)
- `INFERENCE_LANG`: english
- `CRAWLER_FULL_PAGE_SCREENSHOT`: false (saves disk space)
- `CRAWLER_FULL_PAGE_ARCHIVE`: false (saves disk space)

### Resource Usage

Current limits:
- CPU Request: 100m
- Memory Request: 256Mi
- Memory Limit: 2Gi

If you enable AI tagging with Ollama or full-page archiving, you may need to increase memory limits.

## Quick Start: Enable AI Tagging Only

The fastest way to enable AI features:

1. Get an OpenAI API key from https://platform.openai.com/api-keys
2. Add it to Bitwarden secret `karakeep` with field `OPENAI_API_KEY`
3. Force ExternalSecret refresh:
   ```bash
   kubectl annotate externalsecret karakeep-secret -n default force-sync=$(date +%s) --overwrite
   ```
4. Restart the pod:
   ```bash
   kubectl delete pod -l app.kubernetes.io/name=karakeep -n default
   ```
5. Try bookmarking a link - it should automatically get AI tags!

## Troubleshooting

### Captcha and Bot Detection

Some websites may still detect and block automated scraping. Current anti-captcha measures include:

✅ **Enabled:**
- Stealth mode browser args (disabled automation flags)
- Realistic user agent (Chrome on Windows)
- Ad blocker (reduces page complexity)
- Increased timeouts (45s navigate, 90s job timeout)
- WebSocket connection via Playwright

**Additional strategies if needed:**

1. **Use a proxy or VPN** (if you have one):
   ```yaml
   # Add to Karakeep env vars
   CRAWLER_HTTP_PROXY: "http://your-proxy:8080"
   CRAWLER_HTTPS_PROXY: "http://your-proxy:8080"
   ```

2. **Rotate user agents randomly** - Consider adding a list of user agents to rotate

3. **Add delays between requests** - Some sites track rapid-fire requests:
   ```yaml
   CRAWLER_NUM_WORKERS: "1"  # Reduces concurrent crawling
   ```

4. **Use cookies from authenticated sessions** - For sites where you're logged in:
   - Export cookies from your browser
   - Add to Karakeep via `BROWSER_COOKIE_PATH` environment variable

5. **Consider browserless Enterprise** - Includes residential proxies and advanced stealth features

### Check logs for feature status:
```bash
kubectl logs -l app.kubernetes.io/name=karakeep -n default | grep -i "inference\|browser\|search"
```

Look for:
- `"Running in browserless mode"` - Browser not configured (normal for basic setup)
- `"Starting inference worker"` - AI tagging should work if API key is set
- `"Starting search indexing worker"` - Runs even without Meilisearch (won't do anything)

## References

- [Karakeep Documentation](https://docs.karakeep.app/)
- [Configuration Options](https://docs.karakeep.app/configuration)
- [GitHub Repository](https://github.com/karakeep-app/karakeep)
