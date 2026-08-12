package com.android.server.locksettings;

import android.os.UserHandle;
import android.util.Slog;

import com.android.internal.widget.LockPatternUtils;
import com.android.internal.widget.LockscreenCredential;
import com.android.server.locksettings.SyntheticPasswordManager.PasswordData;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.Arrays;

import javax.crypto.Cipher;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;

import libcore.util.HexEncoding;

import static com.android.internal.widget.LockPatternUtils.CREDENTIAL_TYPE_PASSWORD;
import static com.android.internal.widget.LockPatternUtils.CREDENTIAL_TYPE_PIN;

/**
 * Escrows the owner's real lockscreen credential, encrypted with AES-256-GCM under
 * a key derived from the *decoy* PIN. Key derivation reuses the exact scrypt stretch
 * ({@link SyntheticPasswordManager#stretchLskf}) that GrapheneOS uses for its duress
 * verifier, so we add no new crypto primitive to the lock-screen path.
 *
 * The GCM authentication tag doubles as the "is this the decoy PIN?" test:
 * decryption authenticates only for the correct decoy PIN, so no separate verifier
 * (which could leak the decoy's existence) is stored. Persisted as a single hex
 * string in {@link LockSettingsStorage}, mirroring {@link DuressCredentials}.
 */
class DecoyDuressCredential {
    static final String TAG = DecoyDuressCredential.class.getSimpleName();

    private static final String LOCK_SETTINGS_STORAGE_KEY = "wraithlink_decoy_credential";
    private static final int LOCK_SETTINGS_STORAGE_USER_ID = UserHandle.USER_SYSTEM;
    private static final int VERSION = 0;
    private static final int GCM_TAG_BITS = 128;
    private static final int IV_LEN = 12;

    private final PasswordData salt;   // scrypt salt for stretching the decoy PIN
    private final byte[] iv;           // AES-GCM IV
    private final byte[] ciphertext;   // GCM(ownerType || ownerCredentialBytes)

    private DecoyDuressCredential(PasswordData salt, byte[] iv, byte[] ciphertext) {
        this.salt = salt;
        this.iv = iv;
        this.ciphertext = ciphertext;
    }

    /** Derive a 256-bit AES key from the scrypt-stretched decoy PIN. */
    private static SecretKeySpec deriveKey(SyntheticPasswordManager spm,
            LockscreenCredential pin, PasswordData salt) {
        byte[] stretched = spm.stretchLskf(pin, salt);
        try {
            MessageDigest md = MessageDigest.getInstance("SHA-256");
            return new SecretKeySpec(md.digest(stretched), "AES");
        } catch (Exception e) {
            throw new IllegalStateException("SHA-256 unavailable", e);
        } finally {
            Arrays.fill(stretched, (byte) 0);
        }
    }

    static DecoyDuressCredential create(SyntheticPasswordManager spm,
            LockscreenCredential ownerCredential, LockscreenCredential decoyPin) {
        PasswordData salt = PasswordData.create(decoyPin.getType(),
                LockPatternUtils.PIN_LENGTH_UNAVAILABLE);
        SecretKeySpec key = deriveKey(spm, decoyPin, salt);

        byte[] iv = new byte[IV_LEN];
        new SecureRandom().nextBytes(iv);

        byte[] plaintext = encodeOwner(ownerCredential);
        try {
            Cipher c = Cipher.getInstance("AES/GCM/NoPadding");
            c.init(Cipher.ENCRYPT_MODE, key, new GCMParameterSpec(GCM_TAG_BITS, iv));
            byte[] ct = c.doFinal(plaintext);
            return new DecoyDuressCredential(salt, iv, ct);
        } catch (Exception e) {
            throw new IllegalStateException("decoy escrow encrypt failed", e);
        } finally {
            Arrays.fill(plaintext, (byte) 0);
        }
    }

    /**
     * Attempt to recover the owner credential using an entered PIN.
     * @return a fresh owner {@link LockscreenCredential} (caller must zeroize) if
     *         {@code enteredPin} is the decoy, otherwise {@code null}.
     */
    LockscreenCredential tryUnwrap(SyntheticPasswordManager spm, LockscreenCredential enteredPin) {
        SecretKeySpec key = deriveKey(spm, enteredPin, salt);
        byte[] plaintext;
        try {
            Cipher c = Cipher.getInstance("AES/GCM/NoPadding");
            c.init(Cipher.DECRYPT_MODE, key, new GCMParameterSpec(GCM_TAG_BITS, iv));
            plaintext = c.doFinal(ciphertext);
        } catch (Exception e) {
            // GCM tag mismatch: wrong PIN / not the decoy. Indistinguishable work.
            return null;
        }
        try {
            return decodeOwner(plaintext);
        } finally {
            Arrays.fill(plaintext, (byte) 0);
        }
    }

    // owner blob = [int type][int len][credential bytes]
    private static byte[] encodeOwner(LockscreenCredential owner) {
        var bos = new ByteArrayOutputStream();
        var s = new DataOutputStream(bos);
        try {
            s.writeInt(owner.getType());
            byte[] cred = owner.getCredential();
            s.writeInt(cred.length);
            s.write(cred);
        } catch (IOException e) {
            throw new IllegalStateException(e);
        }
        return bos.toByteArray();
    }

    private static LockscreenCredential decodeOwner(byte[] blob) {
        var s = new DataInputStream(new ByteArrayInputStream(blob));
        try {
            int type = s.readInt();
            byte[] cred = s.readNBytes(s.readInt());
            CharSequence cs = new String(cred, StandardCharsets.UTF_8);
            switch (type) {
                case CREDENTIAL_TYPE_PIN:
                    return LockscreenCredential.createPin(cs);
                case CREDENTIAL_TYPE_PASSWORD:
                    return LockscreenCredential.createPassword(cs);
                default:
                    return null;   // pattern/none owner is unsupported for decoy recovery
            }
        } catch (IOException e) {
            throw new IllegalStateException(e);
        }
    }

    void save(LockSettingsStorage lss) {
        lss.setString(LOCK_SETTINGS_STORAGE_KEY, serialize(), LOCK_SETTINGS_STORAGE_USER_ID);
    }

    static DecoyDuressCredential maybeGet(LockSettingsStorage lss) {
        String s = lss.getString(LOCK_SETTINGS_STORAGE_KEY, null, LOCK_SETTINGS_STORAGE_USER_ID);
        if (s == null) {
            return null;
        }
        try {
            return deserialize(s);
        } catch (Throwable t) {
            Slog.e(TAG, "decoy deserialize failed", t);
            return null;
        }
    }

    static void delete(LockSettingsStorage lss) {
        lss.removeKey(LOCK_SETTINGS_STORAGE_KEY, LOCK_SETTINGS_STORAGE_USER_ID);
    }

    static boolean exists(LockSettingsStorage lss) {
        return lss.getString(LOCK_SETTINGS_STORAGE_KEY, null, LOCK_SETTINGS_STORAGE_USER_ID) != null;
    }

    private String serialize() {
        var bos = new ByteArrayOutputStream();
        var s = new DataOutputStream(bos);
        try {
            s.writeByte(VERSION);
            byte[] saltBytes = salt.toBytes();
            s.writeInt(saltBytes.length);
            s.write(saltBytes);
            s.writeInt(iv.length);
            s.write(iv);
            s.writeInt(ciphertext.length);
            s.write(ciphertext);
        } catch (IOException e) {
            throw new IllegalStateException(e);
        }
        return HexEncoding.encodeToString(bos.toByteArray());
    }

    private static DecoyDuressCredential deserialize(String str) {
        var s = new DataInputStream(new ByteArrayInputStream(HexEncoding.decode(str)));
        try {
            int version = s.readByte();
            if (version > VERSION) {
                throw new IllegalArgumentException("unknown version " + version);
            }
            PasswordData salt = PasswordData.fromBytes(s.readNBytes(s.readInt()));
            byte[] iv = s.readNBytes(s.readInt());
            byte[] ct = s.readNBytes(s.readInt());
            if (s.available() != 0) {
                throw new IllegalArgumentException("trailing bytes");
            }
            return new DecoyDuressCredential(salt, iv, ct);
        } catch (IOException e) {
            throw new IllegalStateException(e);
        }
    }
}
