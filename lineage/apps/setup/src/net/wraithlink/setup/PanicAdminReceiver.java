package net.wraithlink.setup;

import android.app.admin.DeviceAdminReceiver;
import android.content.Context;
import android.content.Intent;
import android.util.Log;

/** Device admin used only for software wipeData (soft panic). */
public class PanicAdminReceiver extends DeviceAdminReceiver {
    @Override
    public void onEnabled(Context context, Intent intent) {
        Log.i(Provisioning.TAG, "soft-panic device admin enabled");
    }

    @Override
    public void onDisabled(Context context, Intent intent) {
        Log.i(Provisioning.TAG, "soft-panic device admin disabled");
    }
}
