#!/system/bin/sh
# WraithLink first-boot runner. Executes every fragment in
# /system/etc/wraithlink/firstboot.d/*.sh exactly once, in lexical order,
# then sets a persistent marker so it never runs again.

MARKER="persist.wraithlink.provisioned"

if [ "$(getprop $MARKER)" = "1" ]; then
    exit 0
fi

log -t wraithlink "first-boot provisioning starting"
for frag in /system/etc/wraithlink/firstboot.d/*.sh; do
    [ -f "$frag" ] || continue
    log -t wraithlink "running fragment: $frag"
    sh "$frag" || log -t wraithlink "fragment failed: $frag"
done

setprop $MARKER 1
log -t wraithlink "first-boot provisioning complete"
