// WraithLink web installer.
//
// Uses the locally vendored MIT-licensed fastboot.js WebUSB library
// (./vendor/fastboot.mjs) so the site has no third-party runtime dependency.
// The command-line `fastboot` path shown on the install page is the guaranteed
// fallback when WebUSB is unavailable or a release has not been published yet.

const logEl = document.getElementById("log");
const barEl = document.getElementById("bar");
const relEl = document.getElementById("release");
const btnConnect = document.getElementById("connect");
const btnFlash = document.getElementById("flash");
const btnRelock = document.getElementById("relock");

function log(msg) {
  logEl.textContent += "\n" + msg;
  logEl.scrollTop = logEl.scrollHeight;
}
function setBar(frac) {
  barEl.style.width = Math.max(0, Math.min(1, frac)) * 100 + "%";
}

let fastbootLib = null;
let device = null;
let release = null;   // parsed release.json
let target = null;    // { codename, factory_zip, sha256 } chosen after connect

async function loadRelease() {
  try {
    const res = await fetch("./release.json", { cache: "no-store" });
    release = await res.json();
    const devs = release && release.devices ? Object.keys(release.devices) : [];
    if (release && release.published && devs.length) {
      relEl.innerHTML =
        `Release <strong>${release.version || "?"}</strong> - supported: ${devs.join(", ")}.`;
    } else {
      relEl.innerHTML =
        (release && release.version ? `<strong>${release.version}</strong>. ` : "") +
        "No published factory image yet - the first build is still being signed. You can still " +
        "connect your device to check compatibility, and use the command-line method below.";
    }
  } catch (e) {
    relEl.textContent = "Could not load release information (release.json missing).";
  }
}

async function loadFastboot() {
  if (fastbootLib) return fastbootLib;
  try {
    fastbootLib = await import("./vendor/fastboot.mjs");
    if (fastbootLib.setDebugLevel) fastbootLib.setDebugLevel(1);
    return fastbootLib;
  } catch (e) {
    log("WebUSB flashing library is not available on this deployment.");
    log("Use the command-line `fastboot` method shown below - it is fully supported.");
    return null;
  }
}

async function verifyChecksum(buf, expectedHex) {
  if (!expectedHex) {
    log("WARNING: no checksum in release manifest; skipping verification.");
    return true;
  }
  const digest = await crypto.subtle.digest("SHA-256", buf);
  const hex = [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
  if (hex.toLowerCase() !== expectedHex.toLowerCase()) {
    log(`CHECKSUM MISMATCH!\n  got:  ${hex}\n  want: ${expectedHex}`);
    return false;
  }
  log("Checksum verified: " + hex);
  return true;
}

function pickTarget(product) {
  if (!release || !release.devices || !product) return null;
  const entry = release.devices[product];
  if (!entry || !entry.factory_zip) return null;
  return { codename: product, factory_zip: entry.factory_zip, sha256: entry.sha256 };
}

btnConnect.addEventListener("click", async () => {
  if (!("usb" in navigator)) {
    log("WebUSB is not supported in this browser. Use Chrome/Edge/Brave, or the CLI method.");
    return;
  }
  const lib = await loadFastboot();
  try {
    if (lib) {
      device = new lib.FastbootDevice();
      await device.connect();
      const product = await device.getVariable("product").catch(() => null);
      const unlocked = await device.getVariable("unlocked").catch(() => null);
      log("Connected in bootloader" + (product ? `: ${product}` : "") +
          (unlocked ? ` (unlocked=${unlocked})` : ""));
      target = pickTarget(product);
      if (release && release.published && target) {
        log(`A signed WraithLink image is available for ${product}.`);
        btnFlash.disabled = false;
      } else if (product) {
        log(`No published image for ${product} yet - use the CLI method below for now.`);
      }
    } else {
      const dev = await navigator.usb.requestDevice({ filters: [{ vendorId: 0x18d1 }] });
      log("Connected: " + (dev.productName || "Pixel device") + " (library unavailable; use CLI to flash)");
    }
    btnRelock.disabled = !device;
  } catch (e) {
    log("Connection failed: " + (e && e.message ? e.message : e));
  }
});

btnFlash.addEventListener("click", async () => {
  if (!device || !target) return;
  btnFlash.disabled = true;
  btnConnect.disabled = true;
  try {
    log("Unlocking bootloader (confirm on the phone with Volume + Power)...");
    try { await device.runCommand("flashing unlock"); } catch (_) { /* may already be unlocked */ }

    log("Downloading factory image: " + target.factory_zip);
    const resp = await fetch(target.factory_zip, { cache: "no-store" });
    if (!resp.ok) throw new Error("download failed: HTTP " + resp.status);
    const buf = await resp.arrayBuffer();
    setBar(0.15);

    if (!(await verifyChecksum(buf, target.sha256))) {
      throw new Error("aborting: checksum verification failed");
    }
    setBar(0.2);

    const blob = new Blob([buf]);
    log("Flashing WraithLink. Do not disconnect the phone.");
    await device.flashFactoryZip(
      blob,
      true, // wipe userdata
      (reconnectResume) => { log("Device rebooted; reconnecting..."); reconnectResume(); },
      (action, item, progress) => {
        log(`${action} ${item} ${(progress * 100).toFixed(0)}%`);
        setBar(0.2 + 0.7 * progress);
      }
    );
    setBar(0.95);
    log("Flash complete. Relock the bootloader to restore verified boot.");
    btnRelock.disabled = false;
  } catch (e) {
    log("Flash failed: " + (e && e.message ? e.message : e));
    log("You can retry, or use the CLI method below.");
    btnFlash.disabled = false;
  } finally {
    btnConnect.disabled = false;
  }
});

btnRelock.addEventListener("click", async () => {
  if (!device) return;
  try {
    log("Relocking bootloader (confirm on the phone)... this re-enables verified boot.");
    await device.runCommand("flashing lock");
    setBar(1);
    log("Done. The phone will verify WraithLink against its own key on every boot.");
  } catch (e) {
    log("Relock command failed: " + (e && e.message ? e.message : e) +
        " - you can run `fastboot flashing lock` manually.");
  }
});

await loadRelease();
