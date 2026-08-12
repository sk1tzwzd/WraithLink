#!/usr/bin/env bash
# First-boot provisioning is handled by the platform-signed WraithLink Setup app
# (packages/apps/WraithLinkSetup, see apps/setup/), NOT by an init shell service.
#
# Why: an init 'oneshot' running 'settings'/'pm' needs a bespoke SELinux domain
# and still cannot cleanly reach binder system services; under enforcing SELinux
# on a user build it simply never runs. The app runs in the system_app domain
# with the framework permissions it needs granted by platform-signature match.
#
# This script now only writes a neutralized fragment and removes any previously
# generated (broken) init service so re-running 04-apply-rebrand.sh cleans up.
. "$(cd "$(dirname "$0")/../scripts" && pwd)/lib.sh"
load_config

SRC="${1:-$WL_SRC_DIR}"
[ -d "$SRC" ] || die "Source dir not found: $SRC"

VDIR="${SRC}/vendor/wraithlink"
mkdir -p "$VDIR"

mk="${VDIR}/wraithlink-firstboot.mk"
{
  echo "# WraithLink first-boot fragment (neutralized)."
  echo "# Provisioning moved to packages/apps/WraithLinkSetup (BOOT_COMPLETED + wizard)."
  echo "# The former init 'wraithlink_firstboot' service had no SELinux domain and"
  echo "# could not use binder services. See apps/setup/ and docs/integration.md."
} > "$mk"

# Remove any previously generated init service / runner / shell fragments.
rm -f  "${VDIR}/etc/init/wraithlink-firstboot.rc" "${VDIR}/bin/wraithlink-firstboot" 2>/dev/null || true
rm -rf "${VDIR}/firstboot.d" 2>/dev/null || true

ok "First-boot provisioning delegated to the WraithLink Setup app (init service removed)."
