package net.wraithlink.setup;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.util.Log;

/**
 * Applies safe defaults on first boot and prompts the user to finish hardening.
 * We also expose a launcher icon, so if the notification/auto-open is suppressed
 * the user can still open "WraithLink Setup" manually.
 */
public class BootReceiver extends BroadcastReceiver {
    private static final String CHANNEL = "wraithlink_setup";
    private static final int NOTIF_ID = 4701;

    @Override
    public void onReceive(Context context, Intent intent) {
        if (!Intent.ACTION_BOOT_COMPLETED.equals(intent.getAction())) {
            return;
        }
        if (Provisioning.isDone(context)) {
            return;
        }
        Provisioning.applyDefaults(context);
        postSetupNotification(context);
        // Best-effort direct open (may be blocked by background-activity-launch
        // limits; the launcher icon and notification are the reliable fallbacks).
        try {
            context.startActivity(new Intent(context, WizardActivity.class)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        } catch (Throwable t) {
            Log.i(Provisioning.TAG, "deferred wizard launch to notification/launcher");
        }
    }

    private void postSetupNotification(Context context) {
        NotificationManager nm = context.getSystemService(NotificationManager.class);
        if (nm == null) {
            return;
        }
        nm.createNotificationChannel(new NotificationChannel(
                CHANNEL, "WraithLink Setup", NotificationManager.IMPORTANCE_HIGH));

        PendingIntent pi = PendingIntent.getActivity(context, 0,
                new Intent(context, WizardActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);

        Notification n = new Notification.Builder(context, CHANNEL)
                .setSmallIcon(android.R.drawable.ic_lock_idle_lock)
                .setContentTitle("Finish securing WraithLink")
                .setContentText("Set your duress PIN, WraithVault and hardening options.")
                .setContentIntent(pi)
                .setOngoing(true)
                .setAutoCancel(false)
                .build();
        nm.notify(NOTIF_ID, n);
    }

    static void clearNotification(Context context) {
        NotificationManager nm = context.getSystemService(NotificationManager.class);
        if (nm != null) {
            nm.cancel(NOTIF_ID);
        }
    }
}
