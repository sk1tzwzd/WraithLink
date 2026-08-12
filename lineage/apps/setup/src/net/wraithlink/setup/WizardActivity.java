package net.wraithlink.setup;

import android.app.Activity;
import android.app.AlertDialog;
import android.app.admin.DevicePolicyManager;
import android.content.ComponentName;
import android.content.Intent;
import android.graphics.Typeface;
import android.os.Bundle;
import android.provider.Settings;
import android.util.TypedValue;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

/**
 * WraithLink Lineage Setup — no GrapheneOS duress / decoy. Soft panic via device admin wipe.
 */
public class WizardActivity extends Activity {

    private int mStepNo;
    private DevicePolicyManager mDpm;
    private ComponentName mAdmin;

    private String step(String title) {
        return (++mStepNo) + ". " + title;
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        mDpm = getSystemService(DevicePolicyManager.class);
        mAdmin = new ComponentName(this, PanicAdminReceiver.class);

        ScrollView scroll = new ScrollView(this);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        int pad = dp(20);
        root.setPadding(pad, pad, pad, pad);
        scroll.addView(root);

        addHeader(root, "WraithLink Lineage Setup");
        addBody(root, "Wide-device edition. Soft panic wipe is interruptible software reset — not "
                + "secure-element key destroy. Prefer Pixel WraithLink when that matters. "
                + "Every step is optional.");

        addStep(root, step("Strong screen lock"),
                "Lockscreen credential protects disk encryption on this device.",
                "Set screen lock",
                v -> startSafely(new Intent(DevicePolicyManager.ACTION_SET_NEW_PASSWORD),
                        Settings.ACTION_SECURITY_SETTINGS));

        addStep(root, step("Enable soft panic admin"),
                "Grant device-admin so Setup can factory-reset this phone. This is a normal Android "
                + "wipeData call — a local attacker can often interrupt it.",
                "Enable admin", v -> enablePanicAdmin());

        addStep(root, step("Soft panic wipe"),
                "Immediately factory-reset this device (software wipe). Confirm carefully.",
                "Wipe device now", v -> confirmSoftPanic());

        addStep(root, step("Encrypted DNS (Mullvad)"),
                "Private DNS over TLS to dns.mullvad.net. Disable briefly on captive portals if needed.",
                "Enable Mullvad DNS", v -> setMullvadDns());

        addStep(root, step("Create WraithVault"),
                "Secondary user profile for sensitive apps — visible in the profile switcher, not hidden.",
                "Create WraithVault", v -> createVault());

        addStep(root, step("WraithLink Messenger"),
                "Tor P2P messenger (same app as Pixel WraithLink). Preinstalled on ROM builds; "
                + "also available as an APK for stock Lineage.",
                "Open Messenger", v -> openMessenger());

        Button finish = new Button(this);
        finish.setText("Finish setup");
        finish.setOnClickListener(v -> {
            Provisioning.markDone(this);
            BootReceiver.clearNotification(this);
            Toast.makeText(this, "WraithLink Lineage setup marked done.", Toast.LENGTH_LONG).show();
            finish();
        });
        LinearLayout.LayoutParams flp = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        flp.topMargin = dp(24);
        root.addView(finish, flp);

        setContentView(scroll);
    }

    private void enablePanicAdmin() {
        if (mDpm != null && mDpm.isAdminActive(mAdmin)) {
            Toast.makeText(this, "Soft-panic admin already enabled.", Toast.LENGTH_SHORT).show();
            return;
        }
        Intent i = new Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN);
        i.putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, mAdmin);
        i.putExtra(DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                "Allows a software factory reset (soft panic). Interruptible — not SE key destroy.");
        try {
            startActivity(i);
        } catch (Throwable t) {
            Toast.makeText(this, "Could not open device-admin prompt.", Toast.LENGTH_LONG).show();
        }
    }

    private void confirmSoftPanic() {
        if (mDpm == null || !mDpm.isAdminActive(mAdmin)) {
            Toast.makeText(this, "Enable soft-panic admin first.", Toast.LENGTH_LONG).show();
            return;
        }
        new AlertDialog.Builder(this)
                .setTitle("Software factory reset?")
                .setMessage("This calls wipeData(). It is NOT GrapheneOS key-destroying duress. "
                        + "Everything on this device will be erased if the wipe completes.")
                .setPositiveButton("Wipe now", (d, w) -> {
                    try {
                        mDpm.wipeData(0);
                    } catch (Throwable t) {
                        Toast.makeText(this, "Wipe failed: " + t.getMessage(), Toast.LENGTH_LONG).show();
                    }
                })
                .setNegativeButton("Cancel", null)
                .show();
    }

    private void setMullvadDns() {
        try {
            Settings.Global.putString(getContentResolver(), "private_dns_mode", "hostname");
            Settings.Global.putString(getContentResolver(), "private_dns_specifier", "dns.mullvad.net");
            Toast.makeText(this, "Encrypted DNS set to Mullvad (dns.mullvad.net).", Toast.LENGTH_LONG).show();
        } catch (Throwable t) {
            Toast.makeText(this, "Set Private DNS to dns.mullvad.net in Settings.", Toast.LENGTH_LONG).show();
            startSafely(new Intent(Settings.ACTION_SETTINGS), Settings.ACTION_SETTINGS);
        }
    }

    private void createVault() {
        int id = Provisioning.ensureVault(this);
        if (id >= 0) {
            Toast.makeText(this, "WraithVault created. Switch profiles to set its lock.",
                    Toast.LENGTH_LONG).show();
        } else {
            Toast.makeText(this, "Could not create WraithVault (see logs).", Toast.LENGTH_LONG).show();
        }
    }

    private void openMessenger() {
        Intent i = getPackageManager().getLaunchIntentForPackage("net.wraithlink.chat");
        if (i != null) {
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            try {
                startActivity(i);
                return;
            } catch (Throwable ignored) { /* fall through */ }
        }
        Toast.makeText(this, "Install WraithLink Messenger (preinstalled on ROM builds, or APK).",
                Toast.LENGTH_LONG).show();
    }

    private void startSafely(Intent primary, String fallbackAction) {
        try {
            primary.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(primary);
        } catch (Throwable t) {
            try {
                startActivity(new Intent(fallbackAction).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            } catch (Throwable t2) {
                Toast.makeText(this, "Open Settings manually.", Toast.LENGTH_LONG).show();
            }
        }
    }

    private void addHeader(LinearLayout root, String text) {
        TextView t = new TextView(this);
        t.setText(text);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, 26);
        t.setTypeface(t.getTypeface(), Typeface.BOLD);
        t.setPadding(0, 0, 0, dp(8));
        root.addView(t);
    }

    private void addBody(LinearLayout root, String text) {
        TextView t = new TextView(this);
        t.setText(text);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, 15);
        t.setPadding(0, 0, 0, dp(12));
        root.addView(t);
    }

    private void addStep(LinearLayout root, String title, String desc, String btn,
            View.OnClickListener onClick) {
        TextView tt = new TextView(this);
        tt.setText(title);
        tt.setTextSize(TypedValue.COMPLEX_UNIT_SP, 18);
        tt.setTypeface(tt.getTypeface(), Typeface.BOLD);
        tt.setPadding(0, dp(16), 0, dp(4));
        root.addView(tt);

        TextView td = new TextView(this);
        td.setText(desc);
        td.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14);
        root.addView(td);

        Button b = new Button(this);
        b.setText(btn);
        b.setOnClickListener(onClick);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        lp.topMargin = dp(6);
        root.addView(b, lp);
    }

    private int dp(int v) {
        return (int) TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v,
                getResources().getDisplayMetrics());
    }
}
