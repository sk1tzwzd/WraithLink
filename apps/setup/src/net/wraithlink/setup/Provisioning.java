package net.wraithlink.setup;

import android.app.WallpaperManager;
import android.content.ContentResolver;
import android.content.Context;
import android.content.pm.UserInfo;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.os.UserManager;
import android.provider.Settings;
import android.util.Log;

/**
 * First-boot provisioning helpers. Runs inside the platform-signed WraithLink
 * Setup app (system_app domain), which is the AOSP-sanctioned place for this -
 * unlike an init shell service, it has a real SELinux domain and the framework
 * permissions ({@code WRITE_SECURE_SETTINGS}, {@code MANAGE_USERS}) granted by
 * platform-signature match.
 */
public final class Provisioning {
    static final String TAG = "WraithLinkSetup";
    /** Settings.Secure flag: wizard finished. */
    static final String DONE_FLAG = "wraithlink_setup_done";
    /** Settings.Global: user id of the hidden WraithVault profile (-1 if none). */
    static final String VAULT_USER_ID = "wraithlink_vault_user_id";
    /** Settings.Secure one-shot flag: we've applied the default wallpaper once. */
    static final String WALLPAPER_FLAG = "wraithlink_wallpaper_set";

    private Provisioning() {}

    /** Settings.Secure: strip EXIF/GPS/XMP from media when MediaStore indexes it. */
    static final String STRIP_MEDIA_METADATA = "wraithlink_strip_media_metadata";

    /** Safe, connectivity-neutral defaults applied automatically on first boot. */
    static void applyDefaults(Context ctx) {
        ContentResolver cr = ctx.getContentResolver();
        // Hide sensitive notification content on the lockscreen.
        putSecureInt(cr, "lock_screen_allow_private_notifications", 0);
        // Strip GPS/device/timestamp metadata from photos & videos as soon as they
        // land on the device (camera, downloads, messages, USB). Default ON.
        putSecureInt(cr, STRIP_MEDIA_METADATA, 1);
        // The encrypted-DNS default is applied by the netpriv RRO (not here) so we
        // never break first-boot connectivity before Wi-Fi/mobile data is up.
        setDefaultWallpaper(ctx);
    }

    /**
     * Apply the WraithLink carbon-fibre wallpaper to home + lock screens exactly once,
     * on first boot. Guarded by a one-shot flag so we never stomp a wallpaper the user
     * chooses later. Best-effort: failure here must never block boot provisioning.
     */
    private static void setDefaultWallpaper(Context ctx) {
        ContentResolver cr = ctx.getContentResolver();
        if (Settings.Secure.getInt(cr, WALLPAPER_FLAG, 0) == 1) {
            return;
        }
        Bitmap bmp = null;
        try {
            WallpaperManager wm = WallpaperManager.getInstance(ctx);
            if (wm == null) {
                return;
            }
            int resId = ctx.getResources().getIdentifier(
                    "wraithlink_wallpaper", "drawable", ctx.getPackageName());
            if (resId == 0) {
                return;
            }
            bmp = BitmapFactory.decodeResource(ctx.getResources(), resId);
            if (bmp == null) {
                return;
            }
            wm.setBitmap(bmp, null, true, WallpaperManager.FLAG_SYSTEM);
            wm.setBitmap(bmp, null, true, WallpaperManager.FLAG_LOCK);
            Settings.Secure.putInt(cr, WALLPAPER_FLAG, 1);
            Log.i(TAG, "applied default WraithLink wallpaper");
        } catch (Throwable t) {
            Log.e(TAG, "setDefaultWallpaper failed", t);
        } finally {
            if (bmp != null) {
                bmp.recycle();
            }
        }
    }

    static boolean isDone(Context ctx) {
        return Settings.Secure.getInt(ctx.getContentResolver(), DONE_FLAG, 0) == 1;
    }

    static void markDone(Context ctx) {
        putSecureInt(ctx.getContentResolver(), DONE_FLAG, 1);
    }

    /**
     * Creates the WraithVault secondary profile if it does not already exist.
     * @return the vault user id, or -1 on failure.
     */
    static int ensureVault(Context ctx) {
        int existing = Settings.Global.getInt(ctx.getContentResolver(), VAULT_USER_ID, -1);
        if (existing >= 0) {
            return existing;
        }
        try {
            UserManager um = ctx.getSystemService(UserManager.class);
            UserInfo info = um.createUser("WraithVault", UserManager.USER_TYPE_FULL_SECONDARY, 0);
            if (info != null) {
                Settings.Global.putInt(ctx.getContentResolver(), VAULT_USER_ID, info.id);
                Log.i(TAG, "created WraithVault user id=" + info.id);
                return info.id;
            }
            Log.e(TAG, "createUser(WraithVault) returned null");
        } catch (Throwable t) {
            Log.e(TAG, "createUser(WraithVault) failed", t);
        }
        return -1;
    }

    private static void putSecureInt(ContentResolver cr, String key, int value) {
        try {
            Settings.Secure.putInt(cr, key, value);
        } catch (Throwable t) {
            Log.e(TAG, "putSecureInt(" + key + ") failed", t);
        }
    }
}
