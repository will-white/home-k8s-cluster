# Notifier

Webhook-based notification service using [Apprise](https://github.com/caronc/apprise) to send notifications to Pushover.

## Overview

The Notifier application provides HTTP webhook endpoints that receive JSON payloads from applications (Sonarr, Radarr, Jellyseerr) and sends formatted notifications via Apprise to Pushover.

## Architecture

- **Container**: Python 3.12-slim with Apprise installed
- **Webhook Server**: Simple Python HTTP server on port 8080
- **Scripts**: Bash scripts that parse JSON and call Apprise
- **Secrets**: Pushover credentials stored in ExternalSecret

## Endpoints

- `POST /sonarr` - Sonarr download notifications
- `POST /radarr` - Radarr download notifications
- `POST /jellyseerr` - Jellyseerr request notifications
- `GET /health` - Health check endpoint

## Configuration

### 1. Set up Pushover Credentials in Bitwarden

Create a secret named `pushover` in Bitwarden with these fields:

```
PUSHOVER_USER=your_user_key
PUSHOVER_TOKEN=your_app_token
```

Get these from https://pushover.net/

### 2. Configure Sonarr Webhook

In Sonarr: Settings → Connect → Add → Webhook

- **Name**: Notifier
- **URL**: `http://notifier.default.svc.cluster.local:8080/sonarr`
- **Method**: POST
- **Events**: On Download, On Manual Interaction Required
- **Tags**: (optional)

### 3. Configure Radarr Webhook

In Radarr: Settings → Connect → Add → Webhook

- **Name**: Notifier
- **URL**: `http://notifier.default.svc.cluster.local:8080/radarr`
- **Method**: POST
- **Events**: On Download, On Manual Interaction Required
- **Tags**: (optional)

### 4. Configure Overseerr/Jellyseerr Webhook

In Overseerr: Settings → Notifications → Webhook

- **Webhook URL**: `http://notifier.default.svc.cluster.local:8080/jellyseerr`
- **JSON Payload**: (use default)
- **Events**: (select desired events)

## Supported Events

### Sonarr
- Download (new or upgraded episodes)
- ManualInteractionRequired (download requires user action)
- Test (test notification)

### Radarr
- Download (new or upgraded movies)
- ManualInteractionRequired (download requires user action)
- Test (test notification)

### Jellyseerr
- TEST_NOTIFICATION (test notification)

## Notification Format

Notifications are sent as HTML-formatted messages with:
- **Title**: Event type (e.g., "Episode Downloaded", "Movie Upgraded")
- **Message**: Details about the media (title, season/episode, quality, etc.)
- **URL**: Link back to the application
- **Priority**: low (normal) or high (manual interaction)

## Troubleshooting

### Check pod logs
```bash
kubectl logs -n default -l app.kubernetes.io/name=notifier
```

### Test webhook manually
```bash
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl -X POST \
  -H "Content-Type: application/json" \
  -d '{"eventType":"Test","applicationUrl":"http://sonarr","series":{"title":"Test Series","titleSlug":"test-series"}}' \
  http://notifier.default.svc.cluster.local:8080/sonarr
```

### Verify secret exists
```bash
kubectl get secret -n default notifier-secret
```

## Resources

- [Apprise Documentation](https://github.com/caronc/apprise)
- [Pushover API](https://pushover.net/api)
- [Sonarr Webhook Format](https://wiki.servarr.com/sonarr/settings#connections)
- [Radarr Webhook Format](https://wiki.servarr.com/radarr/settings#connections)
