# WraithLink OTA update server

The WraithLink Updater app (repointed at `WL_OTA_URL` during rebrand) polls a plain
**static** web server for updates. No application server is required - just HTTPS static
hosting (nginx, Caddy, S3+CDN, GitHub Pages behind your domain, etc.).

## Layout

Upload the outputs of `script/generate-release.sh` to the web root:

```
/<device>-stable                      # channel metadata (points to latest build)
/<device>-beta                        # optional beta channel
/<device>-testing                     # optional internal channel
/<build>/<device>-ota_update-<build>.zip   # full OTA package
/<build>/<device>-incremental-<from>-<to>.zip  # optional delta updates
```

Example for Pixel 9 (`tokay`):

```
tokay-stable
2026080400/tokay-ota_update-2026080400.zip
```

## Rules that matter

- **Never** point the Updater at grapheneos.org - a build signed with your keys will be
  rejected as tampered and the client will loop forever (a DoS on their server). This is
  why `rebrand.sh` rewrites `packages/apps/Updater/res/values/config.xml`.
- Serve over HTTPS. The update is verified by *your* signing key regardless, but TLS
  avoids leaking which version a device runs.
- To ship a new release: upload the new `<build>/` dir + OTA zip, then update the
  `<device>-stable` metadata file. The Updater picks it up automatically; if a matching
  incremental (delta) exists it uses that instead of the full zip.

## Delta (incremental) updates

Keep past signed `target_files` around and run `script/generate-delta.sh <device>
<from_build> <to_build>` to produce much smaller updates. Upload alongside the full zip;
no extra metadata needed.
