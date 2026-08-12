#!/usr/bin/env python3
"""Apply the WraithLink decoy-duress framework patch to a synced source tree.

Idempotent and anchor-based (not line-based) so it tolerates minor upstream
drift. Copies three new classes into the locksettings package and makes four
small, well-anchored edits:

  1. LockSettingsService.java  - field, init, verify-path hook, IPC overrides
  2. ILockSettings.aidl        - two new methods
  3. LockPatternUtils.java     - two client wrappers

Every edit checks for its marker first, so re-running is safe. If an anchor is
missing (upstream changed), it fails loudly rather than half-applying.

Usage: apply-decoy-duress.py <SRC_DIR>
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def die(msg):
    sys.stderr.write("ERROR: " + msg + "\n")
    sys.exit(1)


def read(path):
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def write(path, text):
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def insert_after(text, anchor, addition, marker):
    """Insert `addition` right after the first `anchor`. No-op if `marker` present."""
    if marker in text:
        return text, False
    idx = text.find(anchor)
    if idx == -1:
        die("anchor not found: " + repr(anchor[:60]))
    end = idx + len(anchor)
    return text[:end] + addition + text[end:], True


def replace_once(text, needle, replacement, marker):
    if marker in text:
        return text, False
    idx = text.find(needle)
    if idx == -1:
        die("replace anchor not found: " + repr(needle[:60]))
    return text[:idx] + replacement + text[idx + len(needle):], True


def main():
    if len(sys.argv) != 2:
        die("usage: apply-decoy-duress.py <SRC_DIR>")
    src = sys.argv[1]
    ls_dir = os.path.join(src, "frameworks/base/services/core/java/com/android/server/locksettings")
    lss = os.path.join(ls_dir, "LockSettingsService.java")
    aidl = os.path.join(src, "frameworks/base/core/java/com/android/internal/widget/ILockSettings.aidl")
    lpu = os.path.join(src, "frameworks/base/core/java/com/android/internal/widget/LockPatternUtils.java")
    for p in (lss, aidl, lpu):
        if not os.path.isfile(p):
            die("missing expected file: " + p)

    # ---- 1. copy new classes ----
    for name in ("WraithVaultDestroy.java", "DecoyDuressCredential.java", "DecoyDuressHelper.java"):
        write(os.path.join(ls_dir, name), read(os.path.join(HERE, "locksettings", name)))
        print("  + " + name)

    # ---- 2. LockSettingsService.java edits ----
    t = read(lss)

    t, c1 = insert_after(
        t,
        "private final DuressPasswordHelper duressPasswordHelper;",
        "\n    private final DecoyDuressHelper decoyDuressHelper;",
        "private final DecoyDuressHelper decoyDuressHelper;",
    )

    t, c2 = insert_after(
        t,
        "duressPasswordHelper = injector.getDuressPasswordHelper(this, mStorage, mSpManager);",
        "\n        decoyDuressHelper = new DecoyDuressHelper(this, mStorage, mSpManager);",
        "decoyDuressHelper = new DecoyDuressHelper(",
    )

    verify_needle = (
        "            res = doVerifyCredentialInner(credential, lockDomain, userId, progressCallback, flags);\n"
        "            return res;"
    )
    verify_replacement = (
        "            // WraithLink decoy-duress: intercept BEFORE normal verification so the\n"
        "            // decoy PIN never counts as a failed owner unlock attempt (no GateKeeper\n"
        "            // throttle, no failed-attempt auto-wipe). If the entered credential is the\n"
        "            // decoy, unlock the real owner profile exactly as usual while silently\n"
        "            // destroying the hidden WraithVault in the background.\n"
        "            if (lockDomain == Primary && userId == UserHandle.USER_SYSTEM) {\n"
        "                LockscreenCredential wlOwnerCred =\n"
        "                        decoyDuressHelper.maybeUnwrapOwnerForDecoy(credential);\n"
        "                if (wlOwnerCred != null) {\n"
        "                    try {\n"
        "                        decoyDuressHelper.triggerWraithVaultDestroy();\n"
        "                        res = doVerifyCredentialInner(wlOwnerCred, lockDomain, userId,\n"
        "                                progressCallback, flags);\n"
        "                        return res;\n"
        "                    } finally {\n"
        "                        wlOwnerCred.zeroize();\n"
        "                    }\n"
        "                }\n"
        "            }\n"
        "            res = doVerifyCredentialInner(credential, lockDomain, userId, progressCallback, flags);\n"
        "            return res;"
    )
    t, c3 = replace_once(t, verify_needle, verify_replacement, "maybeUnwrapOwnerForDecoy(credential)")

    duress_override = (
        "    @Override\n"
        "    public boolean hasDuressCredentials(LockscreenCredential ownerCredential) {\n"
        "        checkHavePermission();\n"
        "        return duressPasswordHelper.hasDuressCredentials(ownerCredential);\n"
        "    }"
    )
    decoy_override = (
        "\n\n"
        "    @Override\n"
        "    public void setDecoyDuressCredential(LockscreenCredential ownerCredential,\n"
        "            LockscreenCredential decoyPin) {\n"
        "        checkWritePermission();\n"
        "        try {\n"
        "            decoyDuressHelper.setDecoyDuressCredential(ownerCredential, decoyPin);\n"
        "        } catch (Throwable e) {\n"
        "            throw new ParcelableException(e);\n"
        "        } finally {\n"
        "            ownerCredential.zeroize();\n"
        "            decoyPin.zeroize();\n"
        "        }\n"
        "    }\n\n"
        "    @Override\n"
        "    public boolean hasDecoyDuressCredential(LockscreenCredential ownerCredential) {\n"
        "        checkHavePermission();\n"
        "        return decoyDuressHelper.hasDecoyDuressCredential(ownerCredential);\n"
        "    }"
    )
    t, c4 = insert_after(t, duress_override, decoy_override, "hasDecoyDuressCredential(LockscreenCredential ownerCredential)")

    if any((c1, c2, c3, c4)):
        write(lss, t)
    print("  ~ LockSettingsService.java (field=%s init=%s hook=%s ipc=%s)" % (c1, c2, c3, c4))

    # ---- 3. ILockSettings.aidl ----
    a = read(aidl)
    a, ca = insert_after(
        a,
        "boolean hasDuressCredentials(in LockscreenCredential ownerCredential);",
        "\n    void setDecoyDuressCredential(in LockscreenCredential ownerCredential, in LockscreenCredential decoyPin);"
        "\n    boolean hasDecoyDuressCredential(in LockscreenCredential ownerCredential);",
        "hasDecoyDuressCredential(in LockscreenCredential ownerCredential)",
    )
    if ca:
        write(aidl, a)
    print("  ~ ILockSettings.aidl (%s)" % ca)

    # ---- 4. LockPatternUtils.java ----
    l = read(lpu)
    lpu_anchor = (
        "    public boolean hasDuressCredentials(@NonNull LockscreenCredential ownerCredential) {\n"
        "        try {\n"
        "            return getLockSettings().hasDuressCredentials(ownerCredential);\n"
        "        } catch (RemoteException e) {\n"
        "            throw e.rethrowFromSystemServer();\n"
        "        }\n"
        "    }"
    )
    lpu_add = (
        "\n\n"
        "    public void setDecoyDuressCredential(@NonNull LockscreenCredential ownerCredential,\n"
        "                                         @NonNull LockscreenCredential decoyPin) {\n"
        "        try {\n"
        "            getLockSettings().setDecoyDuressCredential(ownerCredential, decoyPin);\n"
        "        } catch (RemoteException e) {\n"
        "            throw e.rethrowFromSystemServer();\n"
        "        }\n"
        "    }\n\n"
        "    public boolean hasDecoyDuressCredential(@NonNull LockscreenCredential ownerCredential) {\n"
        "        try {\n"
        "            return getLockSettings().hasDecoyDuressCredential(ownerCredential);\n"
        "        } catch (RemoteException e) {\n"
        "            throw e.rethrowFromSystemServer();\n"
        "        }\n"
        "    }"
    )
    l, cl = insert_after(l, lpu_anchor, lpu_add, "hasDecoyDuressCredential(@NonNull LockscreenCredential ownerCredential)")
    if cl:
        write(lpu, l)
    print("  ~ LockPatternUtils.java (%s)" % cl)

    print("Decoy-duress framework patch applied.")


if __name__ == "__main__":
    main()
