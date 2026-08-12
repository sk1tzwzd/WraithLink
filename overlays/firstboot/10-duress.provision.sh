#!/system/bin/sh
# WraithLink first-boot onboarding fragment: duress credential prompt.
# We NEVER preset a duress secret (that would be a backdoor). Instead we set a
# flag so the onboarding wizard surfaces the "Set duress password" step.

settings put secure wraithlink_onboard_duress_prompt 1
log -t wraithlink "duress onboarding prompt scheduled"
