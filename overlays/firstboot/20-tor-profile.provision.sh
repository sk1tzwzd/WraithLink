#!/system/bin/sh
# WraithLink first-boot fragment: create the Tor-only "Ghost" profile.
# Best-effort; requires privileged/system context. Wired to run once at first boot.

GHOST_NAME="WraithLink Ghost"

# Create the secondary profile if it does not already exist.
if ! pm list users | grep -q "$GHOST_NAME"; then
    NEWID="$(pm create-user "$GHOST_NAME" | tr -dc '0-9')"
    log -t wraithlink "created Ghost profile uid=$NEWID"

    if [ -n "$NEWID" ]; then
        # Install Orbot + Tor Browser into the Ghost profile.
        pm install-existing --user "$NEWID" org.torproject.android || true
        pm install-existing --user "$NEWID" org.torproject.torbrowser || true

        # Force ALL traffic in the Ghost profile through Tor via Orbot always-on VPN
        # with lockdown (kill-switch: no traffic if Tor is down).
        settings put --user "$NEWID" secure always_on_vpn_app org.torproject.android
        settings put --user "$NEWID" secure always_on_vpn_lockdown 1

        # Strict encrypted DNS is redundant under Tor; Orbot handles DNS.
        log -t wraithlink "Ghost profile routed through Tor (Orbot VPN lockdown)"
    fi
else
    log -t wraithlink "Ghost profile already present; skipping"
fi
