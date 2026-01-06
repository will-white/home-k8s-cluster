# Missing Applications from Reference Repository

This document lists all applications found in [joryirving/home-ops](https://github.com/joryirving/home-ops) that are not currently deployed in this cluster.

**Last Updated:** November 12, 2025  
**Reference Repository:** joryirving/home-ops (main branch)  
**Total Missing Applications:** 60+

---

## 🔴 CRITICAL Priority (Deploy First)

### Authentication & SSO

### Infrastructure & Automation
2. **Actions Runner Controller** - `actions-runner-system/actions-runner-controller`
   - Self-hosted GitHub Actions runners in Kubernetes
   - Enables CI/CD workflows within the cluster
   - **Why Critical:** Automated testing and deployment pipelines

---

## 🟡 HIGH VALUE Priority (Deploy Soon)

### 📥 Downloads & Media Automation

6. **SABnzbd** - `downloads/sabnzbd`
   - Usenet newsreader and binary downloader
   - Alternative/complement to qBittorrent
   - Includes custom scripts for cross-seed integration

8. **FlareSolverr** - `downloads/flaresolverr`
   - Proxy server to bypass Cloudflare protection
   - Required for some indexers in Prowlarr/Sonarr/Radarr

9. **Kapowarr** - `downloads/kapowarr`
   - Comic/manga download manager
   - Like Sonarr but for comics and graphic novels

10. **Mylar** - `downloads/mylar`
    - Automated comic book downloader
    - Alternative to Kapowarr with different feature set

11. **Metube** - `downloads/metube`
    - Web GUI for youtube-dl/yt-dlp
    - Download videos from YouTube and 1000+ sites

### 🎬 Media Streaming

12. **ErsatzTV** - `media/ersatztv`
    - Create custom linear TV channels from your media library
    - SSO integration via Authentik
    - Stream your content like traditional TV

13. **Kyoo** - `media/kyoo`
    - Modern, feature-rich media server
    - SSO integration via Authentik
    - Alternative to Plex/Jellyfin with unique features

### 🤖 LLM & AI

14. **Ollama** - `llm/ollama`
    - Run large language models locally
    - Supports Llama, Mistral, and many other models
    - Privacy-focused AI without cloud dependencies

15. **Open-WebUI** - `llm/open-webui`
    - Beautiful web interface for LLMs
    - Works with Ollama, OpenAI, and other providers
    - SSO integration via Authentik

16. **SearXNG** - `llm/searxng`
    - Privacy-respecting metasearch engine
    - Aggregates results from multiple search engines
    - No tracking or profiling

---

## 🟢 NICE TO HAVE Priority

### 🎮 Gaming Servers

28. **RomM** - `games/romm`
    - ROM library manager
    - SSO integration via Authentik
    - Organize retro game collections

### 🏠 Self-Hosted Applications

30. **Actual Budget** - `self-hosted/actual`
    - Privacy-focused budgeting application
    - Local-first with sync capabilities

32. **IT-Tools** - `self-hosted/it-tools`
    - Collection of handy developer tools
    - Encoding, hashing, formatting, etc.
    - All client-side, privacy-focused

### 🏡 Home Automation

42. **Matter Server** - `home-automation/matter-server`
    - Matter smart home protocol server
    - Next-gen smart home standard

44. **rtlamr2mqtt** - `home-automation/rtlamr2mqtt`
    - RTL-SDR to MQTT bridge
    - Read smart utility meters

### 📥 Additional Download Tools

46. **Spotizerr** - `downloads/spotizerr`
    - Spotify playlist downloader
    - Integration with *arr stack

---

## 🔗 Useful References

- **Reference Repository:** https://github.com/joryirving/home-ops
- **Cluster Template:** https://github.com/onedr0p/cluster-template
- **KubeSearch:** https://kubesearch.dev/ (search for app configurations)
- **Home Operations Discord:** https://discord.gg/home-operations

---

## 📝 Notes

### Application Counts by Category
- 🎮 **Gaming:** 5 apps
- 📥 **Downloads:** 9 additional apps (you have 10 already)
- 🤖 **LLM/AI:** 3 apps
- 🏠 **Self-Hosted:** 13 apps
- 🏡 **Home Automation:** 3 additional apps
- 🔧 **Kube-Tools:** 2 additional apps
- 💾 **Storage:** 5 additional apps
- 🎬 **Media:** 2 additional apps
- 🔐 **Security/Auth:** 1 app (Authentik)
- ☁️ **Infrastructure:** 4 apps
- 📊 **Observability:** 1 additional app

### Custom Scripts & Automations
The reference repo includes several custom scripts:
- **Sonarr codec tagging** - Automatically tag series by video codec
- **Sonarr series refresh** - Auto-refresh series with TBA/TBD episodes
- **Certificate extraction** - Extract certs for external services (Caddy, UniFi, PiKVM)

Consider adapting these for your own use cases.

---

**Generated:** November 12, 2025  
**Source Analysis:** joryirving/home-ops @ main branch
