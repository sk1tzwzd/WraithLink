# On-device Linux (WraithLink Terminal)

Pixel 8 and newer support the Android Virtualization Framework (AVF). GrapheneOS ships a
Terminal app that boots a Debian guest in a protected VM (pVM) entirely on-device.

WraithLink reuses this for an **offline** local Linux shell (distinct from the remote X47
link). No porting of the X47 toolchain to ARM is required - this is a generic Debian VM.

## What we do
- The rebrand pass renames the Terminal app to "WraithLink Terminal".
- Ensure the AVF + Terminal product packages are enabled for the target in the device
  product config.

## What it is not
- It is not full X47. X47 stays x86_64 and is reached remotely (see `x47-link/`).
- Heavy x86-only pentest tools are used on X47 over the remote link, not in this VM.

## Usage
Open WraithLink Terminal -> the Debian guest boots -> you get a shell with apt. Install
lightweight ARM64 tooling here for offline work; use the X47 remote link for the full
desktop and x86 tools.
