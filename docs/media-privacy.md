# Media privacy: strip metadata on capture and receive

## What gets removed
When a photo or video is indexed by MediaStore (camera save, download, MMS/RCS
attachment, share-to-Files, USB copy, etc.), WraithLink rewrites the file at rest:

- **Images (JPEG / PNG / WebP):** GPS, device make/model/software, artist,
  copyright, unique IDs, maker notes, user comments, and EXIF timestamps.
  Display orientation is kept so photos stay upright.
- **Video / HEIF (ISO-BMFF):** location boxes and XMP ranges are zeroed using the
  same ranges AOSP already uses for read-time redaction.

PDF/Office documents are not rewritten (out of scope for the MediaProvider hook).

## Defaults
- Framework patch is applied when `WL_ENABLE_MEDIA_PRIVACY=true` (default).
- Runtime toggle: `Settings.Secure` key `wraithlink_strip_media_metadata`
  (`1` = on, `0` = off). First-boot Setup sets it to `1`.
- Product property `ro.wraithlink.strip_media_metadata=1` advertises the capability.

## Capture path
GrapheneOS Camera (prebuilt) already clears EXIF after capture and keeps
geo-tagging off. The MediaProvider hook is a second line of defense for any app
that writes media with metadata, and for everything received from elsewhere.

## Implementation
- `overlays/apply-media-privacy.sh`
- `overlays/framework-patches/apply-media-privacy.py`
- `overlays/framework-patches/mediaprovider/MetadataStripUtils.java`
- Hooked from `ModernMediaScanner.scanItemImage` / `scanItemVideo`
- Setup default in `apps/setup/.../Provisioning.java`
