/*
 * Copyright (C) 2026 WraithLink
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package com.android.providers.media.util;

import android.content.Context;
import android.media.ExifInterface;
import android.provider.Settings;
import android.util.Log;

import java.io.File;
import java.io.IOException;
import java.io.RandomAccessFile;

/**
 * WraithLink: strip sensitive metadata from media files as soon as MediaProvider
 * indexes them (camera, downloads, messaging, USB copy, etc.).
 *
 * Controlled by Settings.Secure {@link #SETTING_KEY} (default enabled).
 */
public final class MetadataStripUtils {
    private static final String TAG = "WraithLinkMetaStrip";

    /** Settings.Secure: 1 = strip on scan (default), 0 = leave metadata intact. */
    public static final String SETTING_KEY = "wraithlink_strip_media_metadata";

    private static final String[] STRIP_EXIF_TAGS = new String[] {
            ExifInterface.TAG_GPS_ALTITUDE,
            ExifInterface.TAG_GPS_ALTITUDE_REF,
            ExifInterface.TAG_GPS_AREA_INFORMATION,
            ExifInterface.TAG_GPS_DOP,
            ExifInterface.TAG_GPS_DATESTAMP,
            ExifInterface.TAG_GPS_DEST_BEARING,
            ExifInterface.TAG_GPS_DEST_BEARING_REF,
            ExifInterface.TAG_GPS_DEST_DISTANCE,
            ExifInterface.TAG_GPS_DEST_DISTANCE_REF,
            ExifInterface.TAG_GPS_DEST_LATITUDE,
            ExifInterface.TAG_GPS_DEST_LATITUDE_REF,
            ExifInterface.TAG_GPS_DEST_LONGITUDE,
            ExifInterface.TAG_GPS_DEST_LONGITUDE_REF,
            ExifInterface.TAG_GPS_DIFFERENTIAL,
            ExifInterface.TAG_GPS_IMG_DIRECTION,
            ExifInterface.TAG_GPS_IMG_DIRECTION_REF,
            ExifInterface.TAG_GPS_LATITUDE,
            ExifInterface.TAG_GPS_LATITUDE_REF,
            ExifInterface.TAG_GPS_LONGITUDE,
            ExifInterface.TAG_GPS_LONGITUDE_REF,
            ExifInterface.TAG_GPS_MAP_DATUM,
            ExifInterface.TAG_GPS_MEASURE_MODE,
            ExifInterface.TAG_GPS_PROCESSING_METHOD,
            ExifInterface.TAG_GPS_SATELLITES,
            ExifInterface.TAG_GPS_SPEED,
            ExifInterface.TAG_GPS_SPEED_REF,
            ExifInterface.TAG_GPS_STATUS,
            ExifInterface.TAG_GPS_TIMESTAMP,
            ExifInterface.TAG_GPS_TRACK,
            ExifInterface.TAG_GPS_TRACK_REF,
            ExifInterface.TAG_GPS_VERSION_ID,
            ExifInterface.TAG_MAKE,
            ExifInterface.TAG_MODEL,
            ExifInterface.TAG_SOFTWARE,
            ExifInterface.TAG_ARTIST,
            ExifInterface.TAG_COPYRIGHT,
            ExifInterface.TAG_IMAGE_DESCRIPTION,
            ExifInterface.TAG_USER_COMMENT,
            ExifInterface.TAG_MAKER_NOTE,
            ExifInterface.TAG_IMAGE_UNIQUE_ID,
            ExifInterface.TAG_DATETIME,
            ExifInterface.TAG_DATETIME_ORIGINAL,
            ExifInterface.TAG_DATETIME_DIGITIZED,
            ExifInterface.TAG_OFFSET_TIME,
            ExifInterface.TAG_OFFSET_TIME_ORIGINAL,
            ExifInterface.TAG_OFFSET_TIME_DIGITIZED,
            ExifInterface.TAG_SUBSEC_TIME,
            ExifInterface.TAG_SUBSEC_TIME_ORIGINAL,
            ExifInterface.TAG_SUBSEC_TIME_DIGITIZED,
    };

    private MetadataStripUtils() {}

    public static boolean isEnabled(Context context) {
        if (context == null) {
            return true;
        }
        try {
            return Settings.Secure.getInt(context.getContentResolver(), SETTING_KEY, 1) == 1;
        } catch (Throwable t) {
            return true;
        }
    }

    public static void stripIfEnabled(Context context, File file) {
        if (!isEnabled(context) || file == null || !file.isFile() || !file.canWrite()) {
            return;
        }
        final String mime = MimeUtils.resolveMimeType(file);
        if (mime == null) {
            return;
        }
        try {
            if (ExifInterface.isSupportedMimeType(mime)) {
                stripExif(file);
            }
            if (ExifInterface.isSupportedMimeType(mime)
                    || IsoInterface.isSupportedMimeType(mime)) {
                zeroRedactionRanges(file);
            }
        } catch (Throwable t) {
            Log.w(TAG, "metadata strip failed for " + file.getName() + ": " + t);
        }
    }

    private static void stripExif(File file) throws IOException {
        final ExifInterface exif = new ExifInterface(file.getAbsolutePath());
        final String orientation = exif.getAttribute(ExifInterface.TAG_ORIENTATION);
        boolean changed = false;
        for (String tag : STRIP_EXIF_TAGS) {
            if (exif.getAttribute(tag) != null) {
                exif.setAttribute(tag, null);
                changed = true;
            }
        }
        if (!changed) {
            return;
        }
        if (orientation != null) {
            exif.setAttribute(ExifInterface.TAG_ORIENTATION, orientation);
        }
        exif.saveAttributes();
    }

    private static void zeroRedactionRanges(File file) throws IOException {
        final long[] ranges = RedactionUtils.getRedactionRanges(file);
        if (ranges == null || ranges.length < 2) {
            return;
        }
        try (RandomAccessFile raf = new RandomAccessFile(file, "rw")) {
            final long length = raf.length();
            final byte[] zeros = new byte[4096];
            for (int i = 0; i + 1 < ranges.length; i += 2) {
                long start = ranges[i];
                long end = ranges[i + 1];
                if (start < 0 || end <= start || start >= length) {
                    continue;
                }
                if (end > length) {
                    end = length;
                }
                long pos = start;
                long remaining = end - start;
                while (remaining > 0) {
                    int chunk = (int) Math.min(remaining, zeros.length);
                    raf.seek(pos);
                    raf.write(zeros, 0, chunk);
                    pos += chunk;
                    remaining -= chunk;
                }
            }
        }
    }
}
