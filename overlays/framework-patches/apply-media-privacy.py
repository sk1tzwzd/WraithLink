#!/usr/bin/env python3
"""Apply WraithLink media-metadata stripping to MediaProvider.

Idempotent. Copies MetadataStripUtils.java into MediaProvider and hooks
ModernMediaScanner so every newly indexed image/video is sanitized at rest
(camera, downloads, MMS, share-to-storage, USB copy, etc.).

Usage: apply-media-privacy.py <SRC_DIR>
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
IMAGE_MARKER = "WraithLink: strip sensitive metadata"
VIDEO_MARKER = "WraithLink: strip video location metadata"


def die(msg):
    sys.stderr.write("ERROR: " + msg + "\n")
    sys.exit(1)


def read(path):
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def write(path, text):
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def insert_after(text, anchor, addition, marker):
    if marker in text:
        return text, False
    idx = text.find(anchor)
    if idx == -1:
        die("anchor not found: " + repr(anchor[:100]))
    end = idx + len(anchor)
    return text[:end] + addition + text[end:], True


def main():
    if len(sys.argv) != 2:
        die("usage: apply-media-privacy.py <SRC_DIR>")
    src = sys.argv[1]

    util_dir = os.path.join(
        src, "packages/providers/MediaProvider/src/com/android/providers/media/util"
    )
    scanner = os.path.join(
        src,
        "packages/providers/MediaProvider/src/com/android/providers/media/scan/"
        "ModernMediaScanner.java",
    )
    if not os.path.isdir(util_dir):
        die("MediaProvider util dir missing: " + util_dir)
    if not os.path.isfile(scanner):
        die("ModernMediaScanner.java missing: " + scanner)

    dest = os.path.join(util_dir, "MetadataStripUtils.java")
    write(dest, read(os.path.join(HERE, "mediaprovider", "MetadataStripUtils.java")))
    print("  + MetadataStripUtils.java")

    t = read(scanner)

    # Import (ModernMediaScanner is in .scan; helper is in .util).
    import_marker = "import com.android.providers.media.util.MetadataStripUtils;"
    import_anchor = "import com.android.providers.media.util.FileUtils;"
    if import_marker not in t:
        if import_anchor not in t:
            # Fallback: after package util imports block via MimeUtils.
            import_anchor = "import com.android.providers.media.util.MimeUtils;"
        if import_anchor not in t:
            die("could not find import anchor for MetadataStripUtils")
        t = t.replace(import_anchor, import_anchor + "\n" + import_marker, 1)
        print("  + import MetadataStripUtils")

    # Image: strip after DESCRIPTION nulling, before EXIF read.
    image_anchor = (
        "        withGenericValues(op, file, attrs, mimeType, mediaType);\n"
        "\n"
        "        op.withValue(ImageColumns.DESCRIPTION, null);\n"
    )
    image_hook = (
        "\n        // " + IMAGE_MARKER + " from the file at rest before indexing.\n"
        "        MetadataStripUtils.stripIfEnabled(mContext, file);\n"
    )
    t, c1 = insert_after(t, image_anchor, image_hook, IMAGE_MARKER)

    # Video: strip immediately after generic values, before retriever read.
    video_anchor = (
        "    private @NonNull ContentProviderOperation.Builder scanItemVideo(long existingId,\n"
        "            File file, BasicFileAttributes attrs, String mimeType, int mediaType,\n"
        "            String volumeName) {\n"
        "        final ContentProviderOperation.Builder op = newUpsert(volumeName, existingId);\n"
        "        withGenericValues(op, file, attrs, mimeType, mediaType);\n"
    )
    video_hook = (
        "\n        // " + VIDEO_MARKER + " before indexing.\n"
        "        MetadataStripUtils.stripIfEnabled(mContext, file);\n"
    )
    t, c2 = insert_after(t, video_anchor, video_hook, VIDEO_MARKER)

    if c1 or c2:
        write(scanner, t)
        print("  ~ ModernMediaScanner.java (image=%s video=%s)" % (c1, c2))
    else:
        print("  = ModernMediaScanner.java already patched")

    print("OK media-privacy patch applied")


if __name__ == "__main__":
    main()
