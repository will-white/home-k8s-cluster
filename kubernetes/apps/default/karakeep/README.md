# Karakeep

Bookmarking with web crawling, full-text search and optional AI tagging.

| Feature | State |
|---|---|
| Crawling with JavaScript, screenshots, yt-dlp | on: `browser` sidecar (browserless chromium, `ws://localhost:3001/playwright/chromium`) |
| Full-text search | on: `meilisearch` app in this namespace (`MEILI_ADDR`), master key from the `karakeep` Bitwarden secret |
| AI tagging | off until `OPENAI_API_KEY` exists in the `karakeep` Bitwarden secret (or point `OLLAMA_BASE_URL` at a local model) |
| Full-page screenshot / archive | off (`CRAWLER_FULL_PAGE_*`, disk cost) |

Storage is the Volsync-backed `/data` PVC; the database is SQLite inside it
(Karakeep has no Postgres path worth the migration, unlike the *arr apps).

## Enable AI tagging

1. Add `OPENAI_API_KEY` to the `karakeep` secret in Bitwarden Secrets Manager.
2. Refresh and restart:

```bash
kubectl -n default annotate externalsecret karakeep-secret force-sync=$(date +%s) --overwrite
kubectl -n default rollout restart deploy/karakeep
```

The HelmRelease sets `INFERENCE_TEXT_MODEL` / `INFERENCE_IMAGE_MODEL`; change
them there for a different model or for Ollama.

## Crawling blocked by a site

The sidecar already runs with stealth args, a desktop user agent, an ad
blocker and long timeouts. If a site still blocks it: lower
`CRAWLER_NUM_WORKERS` to `1`, route through a proxy with
`CRAWLER_HTTP_PROXY` / `CRAWLER_HTTPS_PROXY`, or supply logged-in cookies via
`BROWSER_COOKIE_PATH`.

Worker status in the logs:

```bash
kubectl -n default logs deploy/karakeep | grep -iE 'inference|browser|search'
```

## References

- https://docs.karakeep.app/configuration
