package net.wraithlink.setup;

import android.app.Activity;
import android.app.AlertDialog;
import android.app.admin.DevicePolicyManager;
import android.content.ComponentName;
import android.content.Intent;
import android.graphics.Typeface;
import android.os.Bundle;
import android.provider.Settings;
import android.text.InputType;
import android.util.TypedValue;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

/**
 * Guided-but-skippable hardening wizard. Sets safe defaults automatically (in
 * {@link BootReceiver}) and walks the user through the credential/profile steps
 * that require their input, deep-linking into the relevant Settings screens.
 */
public class WizardActivity extends Activity {

    private int mStepNo;

    /** Sequential "N. " prefix so step numbers stay correct as optional steps appear. */
    private String step(String title) {
        return (++mStepNo) + ". " + title;
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        ScrollView scroll = new ScrollView(this);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        int pad = dp(20);
        root.setPadding(pad, pad, pad, pad);
        scroll.addView(root);

        addHeader(root, "WraithLink Setup");
        addBody(root, "Harden this device against theft, coercion and forensic extraction. "
                + "Every step is optional and can be changed later in Settings.");

        addStep(root, step("Strong screen lock"),
                "Your lockscreen credential is the root of disk encryption. Prefer a long PIN or passphrase.",
                "Set screen lock",
                v -> startSafely(new Intent(DevicePolicyManager.ACTION_SET_NEW_PASSWORD),
                        Settings.ACTION_SECURITY_SETTINGS));

        addStep(root, step("Panic wipe password"),
                "GrapheneOS duress: a separate PIN/password that destroys disk-encryption keys and wipes "
                + "the entire device (including WraithVault). Keep this even if you later set a decoy PIN — "
                + "they are different credentials for different threats.",
                "Set panic password", v -> openDuress());

        addStep(root, step("Auto-reboot & auto-wipe"),
                "Auto-reboot returns the phone to a keys-evicted state after idle; auto-wipe erases after too "
                + "many wrong attempts. Configure both under Security.",
                "Open Security settings",
                v -> startSafely(new Intent(Settings.ACTION_SECURITY_SETTINGS), Settings.ACTION_SETTINGS));

        addStep(root, step("Block USB when locked"),
                "Keep USB data blocked while locked (defeats forensic bridges) but allowed when unlocked so "
                + "backups to a USB-C drive still work.",
                "Open Security settings",
                v -> startSafely(new Intent(Settings.ACTION_SECURITY_SETTINGS), Settings.ACTION_SETTINGS));

        addStep(root, step("Disable 2G"),
                "2G is insecure and enables IMSI-catcher downgrade attacks. Turn off 2G in mobile network "
                + "settings (per SIM).",
                "Open network settings",
                v -> startSafely(new Intent(Settings.ACTION_NETWORK_OPERATOR_SETTINGS),
                        Settings.ACTION_WIRELESS_SETTINGS));

        addStep(root, step("Encrypted DNS (Mullvad)"),
                "Route all DNS over TLS to Mullvad (dns.mullvad.net). Strongly recommended. Note: on some "
                + "captive-portal Wi-Fi you may need to switch Private DNS off briefly to sign in.",
                "Enable Mullvad DNS", v -> setMullvadDns());

        addBody(root, "Media privacy is on by default: GPS, device model, and timestamps are stripped from "
                + "photos and videos as soon as they are saved or received.");

        addStep(root, step("Create WraithVault"),
                "A secondary user profile for sensitive apps and data — not hidden from the profile switcher "
                + "or forensics. Give the vault its own strong lock after it is created.",
                "Create WraithVault", v -> createVault());

        addStep(root, step("Back up WraithVault"),
                "Back up WraithVault off this phone (X47 desktop or encrypted USB-C). On decoy builds you must "
                + "confirm backup here before Setup will arm a vault-wipe decoy PIN. Never keep the only "
                + "backup on this device.",
                "I've backed up",
                v -> acknowledgeVaultBackup());

        // Milestone-gated: only shown on builds that carry the decoy-duress framework
        // patch (ro.wraithlink.decoy=1). Inert/hidden on the base image.
        if (decoyDuressAvailable()) {
            addStep(root, step("Decoy PIN (vault wipe)"),
                    "Coercion unlock: opens your everyday phone normally while silently destroying WraithVault "
                    + "(and other secondary users). Not forensic deniability. Requires backup confirmation above. "
                    + "Does not replace the panic wipe password.",
                    "Set decoy PIN", v -> setupDecoyDuress());
        }

        addStep(root, step("WraithLink Messenger"),
                "Preinstalled E2EE messenger: peer-to-peer over Tor onion services, mandatory "
                + "verification before messaging, disappearing messages kept only in RAM. "
                + "Removable anytime in Settings if you do not want it.",
                "Open Messenger",
                v -> openMessenger());

        addStep(root, step("Apps"),
                "F-Droid is preinstalled. Add Mullvad VPN, Orbot and Tor Browser, and optionally sandboxed "
                + "Google Play, from the app repositories.",
                "Open apps",
                v -> startSafely(new Intent(Settings.ACTION_APPLICATION_SETTINGS), Settings.ACTION_SETTINGS));

        Button finish = new Button(this);
        finish.setText("Finish setup");
        finish.setOnClickListener(v -> {
            Provisioning.markDone(this);
            BootReceiver.clearNotification(this);
            Toast.makeText(this, "WraithLink hardening ready.", Toast.LENGTH_LONG).show();
            finish();
        });
        LinearLayout.LayoutParams flp = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        flp.topMargin = dp(24);
        root.addView(finish, flp);

        setContentView(scroll);
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
        Toast.makeText(this, "WraithLink Messenger is preinstalled — find it in the app drawer.",
                Toast.LENGTH_LONG).show();
        startSafely(new Intent(Settings.ACTION_APPLICATION_SETTINGS), Settings.ACTION_SETTINGS);
    }

    private void openDuress() {
        Intent i = new Intent().setComponent(new ComponentName(
                "com.android.settings", "com.android.settings.security.DuressPasswordActivity"));
        try {
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(i);
        } catch (Throwable t) {
            Toast.makeText(this, "Open Settings > Security > Duress password", Toast.LENGTH_LONG).show();
            startSafely(new Intent(Settings.ACTION_SECURITY_SETTINGS), Settings.ACTION_SETTINGS);
        }
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

    /** Settings.Secure: user confirmed an off-phone WraithVault backup (decoy arming gate). */
    static final String VAULT_BACKUP_ACK = "wraithlink_vault_backup_acked";

    private void createVault() {
        int id = Provisioning.ensureVault(this);
        if (id >= 0) {
            Toast.makeText(this, "WraithVault created. Switch to it to set its lock and apps.",
                    Toast.LENGTH_LONG).show();
        } else {
            Toast.makeText(this, "Could not create WraithVault (see logs).", Toast.LENGTH_LONG).show();
        }
    }

    private void acknowledgeVaultBackup() {
        try {
            Settings.Secure.putInt(getContentResolver(), VAULT_BACKUP_ACK, 1);
            Toast.makeText(this, "Backup confirmed. You can arm a decoy PIN on decoy builds.",
                    Toast.LENGTH_LONG).show();
        } catch (Throwable t) {
            Toast.makeText(this, "Could not save backup confirmation.", Toast.LENGTH_LONG).show();
        }
        startSafely(new Intent(Settings.ACTION_SETTINGS), Settings.ACTION_SETTINGS);
    }

    private boolean vaultBackupAcked() {
        try {
            return Settings.Secure.getInt(getContentResolver(), VAULT_BACKUP_ACK, 0) == 1;
        } catch (Throwable t) {
            return false;
        }
    }

    private boolean vaultExists() {
        try {
            return Settings.Global.getInt(getContentResolver(), "wraithlink_vault_user_id", -1) > 0;
        } catch (Throwable t) {
            return false;
        }
    }

    /**
     * True only on builds carrying the decoy-duress framework patch, advertised via
     * {@code ro.wraithlink.decoy=1}. Read reflectively so this app still compiles and
     * runs unchanged on the base image (where the property and patch are absent).
     */
    private boolean decoyDuressAvailable() {
        try {
            Class<?> sp = Class.forName("android.os.SystemProperties");
            java.lang.reflect.Method getInt = sp.getMethod("getInt", String.class, int.class);
            return ((Integer) getInt.invoke(null, "ro.wraithlink.decoy", 0)) == 1;
        } catch (Throwable t) {
            return false;
        }
    }

    private void setupDecoyDuress() {
        if (!vaultExists()) {
            Toast.makeText(this, "Create WraithVault first.", Toast.LENGTH_LONG).show();
            return;
        }
        if (!vaultBackupAcked()) {
            Toast.makeText(this, "Confirm backup first (tap \"I've backed up\" above).",
                    Toast.LENGTH_LONG).show();
            return;
        }

        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        int p = dp(16);
        box.setPadding(p, p, p, p);

        final EditText owner = new EditText(this);
        owner.setHint("Your current PIN or password");
        owner.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD);
        box.addView(owner);

        final EditText decoy = new EditText(this);
        decoy.setHint("New decoy PIN (digits only)");
        decoy.setInputType(InputType.TYPE_CLASS_NUMBER | InputType.TYPE_NUMBER_VARIATION_PASSWORD);
        box.addView(decoy);

        new AlertDialog.Builder(this)
                .setTitle("Set decoy PIN")
                .setMessage("This PIN unlocks your everyday phone and silently destroys WraithVault "
                        + "(and other secondary users). It is not hidden storage. Keep your separate "
                        + "panic wipe password for full-device destroy.")
                .setView(box)
                .setPositiveButton("Set", (d, w) ->
                        applyDecoyDuress(owner.getText().toString(), decoy.getText().toString()))
                .setNegativeButton("Cancel", null)
                .show();
    }

    /**
     * Sets the decoy-duress credential via {@code LockPatternUtils.setDecoyDuressCredential}.
     * Everything is invoked reflectively so the base image (which lacks that method) still
     * builds; a milestone image resolves and calls it. Credentials are zeroized after use.
     */
    private void applyDecoyDuress(String ownerCred, String decoyPin) {
        if (ownerCred.isEmpty() || decoyPin.length() < 4 || !decoyPin.matches("\\d+")) {
            Toast.makeText(this, "Enter your current credential and a decoy PIN of at least 4 digits.",
                    Toast.LENGTH_LONG).show();
            return;
        }
        Object ownerObj = null, decoyObj = null;
        java.lang.reflect.Method zeroize = null;
        try {
            Class<?> lc = Class.forName("com.android.internal.widget.LockscreenCredential");
            Class<?> lpu = Class.forName("com.android.internal.widget.LockPatternUtils");
            java.lang.reflect.Method createPin = lc.getMethod("createPin", CharSequence.class);
            java.lang.reflect.Method createPassword = lc.getMethod("createPassword", CharSequence.class);
            zeroize = lc.getMethod("zeroize");

            ownerObj = ownerCred.matches("\\d+")
                    ? createPin.invoke(null, ownerCred)
                    : createPassword.invoke(null, ownerCred);
            decoyObj = createPin.invoke(null, decoyPin);

            Object lpuObj = lpu.getConstructor(android.content.Context.class).newInstance(this);
            java.lang.reflect.Method setter = lpu.getMethod("setDecoyDuressCredential", lc, lc);
            setter.invoke(lpuObj, ownerObj, decoyObj);
            Toast.makeText(this, "Decoy-duress PIN set. Test it from the lockscreen after your backup.",
                    Toast.LENGTH_LONG).show();
        } catch (NoSuchMethodException e) {
            Toast.makeText(this, "This build does not include decoy-duress.", Toast.LENGTH_LONG).show();
        } catch (java.lang.reflect.InvocationTargetException e) {
            Throwable c = e.getCause();
            Toast.makeText(this, "Failed: " + (c != null ? c.getMessage() : e.getMessage()),
                    Toast.LENGTH_LONG).show();
        } catch (Throwable t) {
            android.util.Log.e(Provisioning.TAG, "decoy set failed", t);
            Toast.makeText(this, "Failed to set decoy PIN (see logs).", Toast.LENGTH_LONG).show();
        } finally {
            if (zeroize != null) {
                try { if (ownerObj != null) zeroize.invoke(ownerObj); } catch (Throwable ignore) {}
                try { if (decoyObj != null) zeroize.invoke(decoyObj); } catch (Throwable ignore) {}
            }
        }
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
