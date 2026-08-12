package com.android.server.locksettings;

import android.os.HandlerThread;
import android.os.UserHandle;
import android.util.Slog;

import com.android.internal.widget.LockPatternUtils;
import com.android.internal.widget.LockscreenCredential;
import com.android.internal.widget.VerifyCredentialResponse;

import java.util.Objects;
import java.util.UUID;

import static com.android.internal.widget.LockDomain.Primary;
import static com.android.internal.widget.LockPatternUtils.CREDENTIAL_TYPE_NONE;
import static com.android.internal.widget.LockPatternUtils.CREDENTIAL_TYPE_PASSWORD;
import static com.android.internal.widget.LockPatternUtils.CREDENTIAL_TYPE_PIN;

/**
 * WraithLink decoy-duress. A *decoy* PIN unlocks the real owner profile exactly as
 * the normal PIN would, while the hidden WraithVault (and any other secondary
 * users) are silently destroyed in the background. Structure mirrors
 * {@link DuressPasswordHelper}; the owner credential is escrowed under the decoy
 * PIN via {@link DecoyDuressCredential}.
 *
 * Honest ceiling (see docs/security.html): this defeats theft, coercion and casual
 * inspection - NOT a forensic adversary who images storage before you unlock.
 */
public class DecoyDuressHelper {
    static final String TAG = DecoyDuressHelper.class.getSimpleName();

    private final LockSettingsService lockSettingsService;
    private final LockSettingsStorage lockSettingsStorage;
    private final SyntheticPasswordManager spManager;
    private final HandlerThread backgroundThread;

    DecoyDuressHelper(LockSettingsService lockSettingsService,
            LockSettingsStorage lockSettingsStorage, SyntheticPasswordManager spManager) {
        var bgThread = new HandlerThread("wl-decoy-" + UUID.randomUUID());
        bgThread.start();
        this.backgroundThread = bgThread;
        this.lockSettingsService = lockSettingsService;
        this.lockSettingsStorage = lockSettingsStorage;
        this.spManager = spManager;
    }

    /** Verify the caller actually knows the owner credential before any change/read. */
    private void checkOwnerCredential(LockscreenCredential ownerCredential) {
        int userId = UserHandle.USER_SYSTEM;
        if (lockSettingsService.getCredentialType(userId) == CREDENTIAL_TYPE_NONE) {
            throw new IllegalArgumentException("decoy-duress requires an owner PIN/password");
        }
        VerifyCredentialResponse response = lockSettingsService.checkCredential(ownerCredential,
                Primary, userId, null);
        if (!response.isMatched()) {
            throw new SecurityException("owner credential verification failed; " + response);
        }
    }

    /**
     * Escrow the owner credential under {@code decoyPin}. A none/empty decoy PIN
     * deletes any existing escrow. Exception handling is delegated to the caller.
     */
    protected void setDecoyDuressCredential(LockscreenCredential ownerCredential,
            LockscreenCredential decoyPin) {
        Objects.requireNonNull(ownerCredential, "ownerCredential");
        Objects.requireNonNull(decoyPin, "decoyPin");

        checkOwnerCredential(ownerCredential);

        if (decoyPin.isNone()) {
            DecoyDuressCredential.delete(lockSettingsStorage);
            Slog.d(TAG, "deleted decoy-duress credential");
            return;
        }

        if (decoyPin.getType() != CREDENTIAL_TYPE_PIN) {
            throw new IllegalArgumentException("decoy must be a PIN");
        }
        DuressCredential.validate(decoyPin, CREDENTIAL_TYPE_PIN);

        int ownerType = ownerCredential.getType();
        if (ownerType != CREDENTIAL_TYPE_PIN && ownerType != CREDENTIAL_TYPE_PASSWORD) {
            throw new IllegalArgumentException("owner must use a PIN or password for decoy-duress");
        }
        if (Objects.equals(new String(ownerCredential.getCredential()),
                new String(decoyPin.getCredential()))) {
            throw new IllegalArgumentException("decoy PIN must differ from the owner credential");
        }

        DecoyDuressCredential.create(spManager, ownerCredential, decoyPin).save(lockSettingsStorage);
        Slog.i(TAG, "decoy-duress credential set");
    }

    protected boolean hasDecoyDuressCredential(LockscreenCredential ownerCredential) {
        checkOwnerCredential(ownerCredential);
        return DecoyDuressCredential.exists(lockSettingsStorage);
    }

    /**
     * If {@code enteredCredential} is the configured decoy PIN, returns a fresh
     * owner {@link LockscreenCredential} (caller must zeroize); otherwise null.
     * Returns null immediately when no decoy is configured or the entry isn't a PIN.
     */
    LockscreenCredential maybeUnwrapOwnerForDecoy(LockscreenCredential enteredCredential) {
        if (enteredCredential == null || enteredCredential.getType() != CREDENTIAL_TYPE_PIN) {
            return null;
        }
        DecoyDuressCredential dc = DecoyDuressCredential.maybeGet(lockSettingsStorage);
        if (dc == null) {
            return null;
        }
        return dc.tryUnwrap(spManager, enteredCredential);
    }

    /** Destroy WraithVault + other secondaries off the (usually binder) unlock thread. */
    void triggerWraithVaultDestroy() {
        backgroundThread.getThreadHandler().post(() -> {
            try {
                WraithVaultDestroy.run(lockSettingsService.getContext());
            } catch (Throwable t) {
                Slog.e(TAG, "WraithVault destroy failed", t);
            }
        });
    }
}
