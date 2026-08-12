package com.android.server.locksettings;

import android.content.Context;
import android.content.pm.UserInfo;
import android.os.UserHandle;
import android.os.UserManager;
import android.provider.Settings;
import android.util.Slog;

import java.util.List;

/**
 * WraithLink decoy-duress action: silently destroy the hidden WraithVault profile
 * (and any other non-system secondary users) so a coerced unlock reveals only the
 * believable everyday phone.
 *
 * removeUserWhenPossible() stops the user and removes it as soon as possible; the
 * user's credential-encrypted (CE) storage key is destroyed early in removal, so
 * the data is cryptographically unrecoverable even if removal is interrupted or
 * the device loses power. This runs on a background thread off the unlock path.
 *
 * Honest ceiling (see docs/security.html): this defeats theft, coercion and casual
 * inspection - NOT a forensic adversary who images storage before you ever unlock.
 */
public class WraithVaultDestroy {
    static final String TAG = "WraithVaultDestroy";
    /** Settings.Global int written by the WraithLink Setup app when the vault is created. */
    static final String VAULT_USER_ID = "wraithlink_vault_user_id";

    static void run(Context context) {
        try {
            int vaultId = Settings.Global.getInt(context.getContentResolver(), VAULT_USER_ID, -1);
            UserManager um = context.getSystemService(UserManager.class);
            if (um == null) {
                Slog.e(TAG, "no UserManager; cannot destroy WraithVault");
                return;
            }

            // Destroy the crown-jewels vault first.
            if (vaultId > UserHandle.USER_SYSTEM) {
                removeUser(um, vaultId);
            }

            // Then destroy any other non-system, non-profile secondary users so a
            // coerced unlock cannot surface a second identity either.
            List<UserInfo> users = um.getUsers();
            for (UserInfo ui : users) {
                if (ui.id == UserHandle.USER_SYSTEM || ui.id == vaultId) {
                    continue;
                }
                if (ui.isProfile()) {
                    continue;
                }
                removeUser(um, ui.id);
            }
        } catch (Throwable t) {
            Slog.e(TAG, "WraithVault destroy failed", t);
        }
    }

    private static void removeUser(UserManager um, int userId) {
        try {
            int res = um.removeUserWhenPossible(UserHandle.of(userId), /* overrideDevicePolicy */ false);
            Slog.i(TAG, "removeUserWhenPossible(" + userId + ")=" + res);
        } catch (Throwable t) {
            Slog.e(TAG, "removeUser(" + userId + ") failed", t);
        }
    }
}
