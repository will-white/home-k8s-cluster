# Plex smart "Next Up" lists and reset

Kometa builds the static watch-order playlists (`playlists.yml`). Rolling
"what is left" lists are **smart playlists** driven by Plex labels, managed by
the `plex-lists` CronJob (`kubernetes/apps/media/kometa/app/resources/lists/plex-smart-lists.py`).

## How it works

- `plex-smart-lists.json` defines each list: playlist name, label, source file
  (Kometa `tvdb_episode:<show>_<season>_<episode>` lines), library.
- Weekly (Sunday 05:00) the job labels every listed episode (`List: One Piece Canon`)
  and removes the label from episodes no longer listed. Episodes not yet in
  Plex are skipped and get labelled on a later run.
- It then makes sure the owner and every shared user has a smart playlist
  `<name>` = label + unwatched, sorted show/season/episode. Watch state is
  per user, so each user's list shrinks as that user watches.
- Plex capitalises the first letter of labels; keep label names in that form.
- A new list is one more JSON entry (+ source file in the `kometa-lists`
  ConfigMap). Any episode order that follows season/episode numbering works;
  lists whose order differs from season/episode order stay Kometa playlists.

## Reset (start from scratch)

Marks every item of the list unwatched for one user; the smart playlist
refills at once. Needs the Plex admin token; shared users' tokens are taken
from plex.tv automatically.

```bash
export KOMETA_PLEX_TOKEN=$(kubectl -n media get secret kometa-secret -o jsonpath='{.data.KOMETA_PLEX_TOKEN}' | base64 -d)
f=kubernetes/apps/media/kometa/app/resources/lists/plex-smart-lists.py
DRY_RUN=1 python3 -I $f reset "One Piece - Next Up" --user owner   # preview
python3 -I $f reset "One Piece - Next Up" --user owner             # do it
```

`--user` is `owner` or the Plex username. Only items in the list are touched
(not the rest of the show), and the other users are unaffected.

## Changing a filter or sort

Existing playlists are left alone; after editing the URI in the script run
`RECREATE=1 python3 -I $f sync` (same token export) once.
