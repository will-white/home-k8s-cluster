# Seerr Migration Canary

This phase keeps Overseerr intact and gives Seerr its own PVC: [app/pvc.yaml](app/pvc.yaml).

Before the first real migration start, back up Overseerr, stop Overseerr, copy `/app/config` from the Overseerr PVC into the Seerr PVC, then start Seerr and validate the automatic migration on the Seerr hostname.

Only remove Overseerr after the migrated Seerr instance has been validated.
