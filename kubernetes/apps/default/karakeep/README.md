# Karakeep Configuration

Karakeep is a self-hosted bookmarking application with AI tagging, web browsing, and search capabilities.

## Current Status

✅ **Basic Features**: Working
- Bookmark saving and management
- Basic web crawling (HTTP only, no JavaScript execution)
- Screenshot capture (partial page only)

❌ **AI Tagging**: Disabled (no API key configured)
❌ **Full Web Browsing**: Disabled (no browser service)
❌ **Search Engine**: Disabled (no Meilisearch)

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

Web browsing enables:
- Full page screenshots
- JavaScript execution
- Better content extraction from dynamic websites

### Option 1: Browserless (Recommended)

1. Deploy browserless service:
   ```bash
   # Add browserless to your cluster
   kubectl create deployment browserless --image=browserless/chrome:latest -n default
   kubectl expose deployment browserless --port=3000 -n default
   ```

2. Uncomment the `BROWSER_WEBSOCKET_URL` line in `helmrelease.yaml`:
   ```yaml
   BROWSER_WEBSOCKET_URL: ws://browserless.default.svc.cluster.local:3000
   ```

3. Optional: Enable full-page features:
   ```yaml
   CRAWLER_FULL_PAGE_SCREENSHOT: "true"
   CRAWLER_FULL_PAGE_ARCHIVE: "true"
   ```

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

Check logs for feature status:
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
