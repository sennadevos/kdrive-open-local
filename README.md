# kdrive-open-local

Click a kDrive link, land on the file in your own kDrive sync folder instead of in the web app.

A Firefox extension plus a small native helper for macOS. When you open a link like `https://kdrive.infomaniak.com/app/drive/2133736/redirect/987654`, the helper looks the item up in the kDrive desktop client's own database, finds the matching file in your sync folder and shows it in the Finder. If the item is not synced, or the client is not installed, the link loads in the browser exactly as before.

## Status

**Unreleased and untested on real macOS.** The logic that reads the client databases is covered by unit tests and CI builds the helper on a macOS runner, but nobody has yet run the whole thing against an actual kDrive installation. See [What is not verified](#what-is-not-verified).

## Install

1. Download `kdrive-open-local-host-macos.zip` from the latest release, unzip it, and run `./install.sh` from inside the unzipped folder. It puts the helper in `~/Library/Application Support/kdrive-open-local` and registers it with Firefox.
2. Check it can see your sync:
   ```
   "$HOME/Library/Application Support/kdrive-open-local/kdrive-open-local" --resolve "https://kdrive.infomaniak.com/app/drive/2133736/redirect/1"
   ```
   `{"status":"notSynced"}` is a good answer — it means the databases were read and that particular id simply is not in them. `{"status":"error", ...}` is not.
3. Install the extension XPI in Firefox and restart Firefox.

`./uninstall.sh` removes both the helper and its registration.

By default a file is *selected* in a Finder window rather than opened, so an online-only file is never silently downloaded and no application is launched unasked. Folders always open. The extension's preferences have a checkbox to open files in their application instead.

## Copying a link from a local file

The desktop client already does this and we deliberately ship nothing for it. Right-click a file in your sync folder in the Finder → the **kDrive** submenu → **Copy private share link**. It produces exactly the same URL this extension consumes.

If that submenu is not there, the Finder extension is switched off: **System Settings → General → Login Items & Extensions → Finder Extensions**, and tick kDrive.

## How it works

The desktop client keeps two SQLite databases in `~/Library/Application Support/kDrive`:

- `.parms.db` — table `drive` maps the client's internal id to the real drive id, and table `sync` gives each sync's `localPath` (the sync root on disk) and `dbPath` (where that sync's own database lives).
- `.sync_<hash>.db` — table `node` holds one row per synced item with `nodeIdDrive` (the remote id that appears in links), `parentNodeId` and `nameLocal`.

So resolving a link is: drive id → syncs → find the node with that remote id → walk `parentNodeId` up to the root, collecting `nameLocal` → append to the sync root. No network call and no credentials; the private link format is a build-time constant in the client, not something the server hands out.

Both databases are opened read-only. The client holds them open in WAL mode while it runs, which permits concurrent readers.

The extension cancels the navigation only when the helper reports that the item actually opened. Everything else — not synced, no client, helper missing or crashed — lets the page load, so a link never simply dies.

## Development

The helper is a Swift package in `host/`. The parts that read the databases build and test on Linux as well as macOS, which is how they are developed:

```
cd host
swift test
```

On Linux you need SQLite headers (`libsqlite3-dev`). With podman:

```
podman run --rm -v "$PWD/host:/src:Z" -w /src docker.io/library/swift:6.4.1 \
    bash -lc "apt-get update -qq && apt-get install -y -qq libsqlite3-dev && swift test"
```

The tests build fixture databases from the schemas copied verbatim out of the client source, so they fail if our reader drifts from what the client writes.

Lint the extension with `npx web-ext@10.8.0 lint --source-dir extension`.

## What is verified

Against [Infomaniak/desktop-kDrive](https://github.com/Infomaniak/desktop-kDrive) at tag `3.8.7` (the current released version):

- the private link format, `https://kdrive.infomaniak.com/app/drive/%1/redirect/%2`, is a build constant (`infomaniak/kDrive.cmake`), used by both the Qt and the Swift client
- the databases live in `~/Library/Application Support/kDrive` and are named `.parms.db` and `.sync_<hash>.db` (`libcommonserver/db/db.cpp`, `libcommon/utility/utility_mac.mm`)
- the `sync`, `drive` and `node` schemas this tool reads (`libparms/db/parmsdb.cpp`, `libsyncengine/db/syncdb.cpp`)
- the client's Finder menu already offers "Copy private share link" (`server/comm/extensionjob.cpp`)

## What is not verified

Nobody involved has a Mac, so these are open until someone runs it:

- whether a read-only connection succeeds while the client holds the WAL database open — expected, but unproven
- what `open -R` does to an online-only (lite sync) placeholder, and whether opening one blocks while it hydrates
- whether an unsigned helper runs after `install.sh` strips the quarantine flag, or whether Gatekeeper objects anyway
- the whole Firefox ↔ native host path on macOS, including whether cancelling the navigation leaves a usable tab
- Firefox will not install an unsigned extension, so the XPI still has to be signed through addons.mozilla.org before anyone can install it permanently

## Licence

GPL-3.0-or-later, matching the client whose database layout it reads.
