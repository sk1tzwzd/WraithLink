package net.wraithlink.setup;

import android.content.ContentResolver;
import android.content.Context;
import android.content.pm.UserInfo;
import android.os.UserManager;
import android.provider.Settings;
import android.util.Log;

/** First-boot helpers for WraithLink Lineage Setup (platform-signed). */
public final class Provisioning {
    static final String TAG = "WraithLinkSetup";
    static final String DONE_FLAG = "wraithlink_setup_done";
    static final String VAULT_USER_ID = "wraithlink_vault_user_id";
    static final String EDITION_FLAG = "wraithlink_edition";

    private Provisioning() {}

    static void applyDefaults(Context ctx) {
        ContentResolver cr = ctx.getContentResolver();
        putSecureInt(cr, "lock_screen_allow_private_notifications", 0);
        try {
            Settings.Global.putString(cr, EDITION_FLAG, "lineage");
        } catch (Throwable ignored) { /* best-effort */ }
    }

    static boolean isDone(Context ctx) {
        return Settings.Secure.getInt(ctx.getContentResolver(), DONE_FLAG, 0) == 1;
    }

    static void markDone(Context ctx) {
        putSecureInt(ctx.getContentResolver(), DONE_FLAG, 1);
    }

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
        } catch (Throwable t) {
            Log.e(TAG, "createUser(WraithVault) failed", t);
        }
        return -1;
    }

    private static void putSecureInt(ContentResolver cr, String key, int value) {
        try {
            Settings.Secure.putInt(cr, key, value);
        } catch (Throwable t) {
            Log.w(TAG, "putSecureInt " + key + " failed", t);
        }
    }
}
