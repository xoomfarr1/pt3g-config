# PT3G Configuration Helper

PowerShell helper to configure a **PT3G (Porsche PIWIS 3 VCI)** for use with
**MBTools** and **Vediamo** (Mercedes-Benz coding/diagnostic software).

## ⚠️ Important caveats

- **PT3G brand matters.** Only **VXDIAG PT3G** and **genuine Porsche PT3G** support
  J2534 pass-through. **VNCI PT3G does NOT** — it only works with its own driver.
- **Vediamo 4.x only.** Vediamo 5 does not support J2534 pass-through devices.
- A VCI can only be claimed by **one application at a time** (MBTools, Vediamo, Xentry…).

## What the script does

`configure_pt3g.ps1` automates the scriptable parts:

1. Verifies it's running as Administrator.
2. Detects installed J2534 pass-through devices from the registry
   (`HKLM\SOFTWARE\WOW6432Node\PassThruSupport.04.04`).
3. Checks for EDIC (warns if EDIC 11.26 is installed — incompatible with MBTools;
   flags missing EDIC 1.20).
4. Locates the Vediamo installation and `slave.ini`.
5. Resolves the J2534 device name (auto-picks if only one; accepts `-DeviceName`).
6. Backs up and patches `slave.ini` → sets `PassThruVersion="04.04"` and
   `DeviceName` in the `[PartJ]` section.
7. Prints a manual checklist for the steps that can't be scripted.

## Fix: "running scripts is disabled on this system"

Windows blocks unsigned scripts by default. The quickest safe fix (one-time, current user only):

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

Or run just this script without changing policy:

```powershell
powershell -ExecutionPolicy Bypass -File .\configure_pt3g.ps1
```

## Usage

Run PowerShell **as Administrator**:

```powershell
# Preview changes without writing anything
.\configure_pt3g.ps1 -DryRun

# Auto-detect device and patch Vediamo slave.ini
.\configure_pt3g.ps1

# Force a specific J2534 device name
.\configure_pt3g.ps1 -DeviceName "PT3G..."

# Vediamo installed in a non-default location
.\configure_pt3g.ps1 -VediamoDir "D:\Vediamo"
```

## Manual steps (not scriptable)

1. Confirm your PT3G brand supports J2534 passthru (VXDIAG/genuine yes; VNCI no).
2. Install the PIWIS OEM driver (Actia PUD API) → select module type **PT3G-VCI**
   (not 6154a).
3. Verify the serial number in PT3G Device Manager matches the D-PDU API driver.
4. MBTools: run the Launcher → select **J2534** → click **"Set-up platform"**
   (installs EDIC 1.20).
5. Uninstall EDIC 11.26 if present (incompatible with MBTools).
6. Connect PT3G to **both** the PC (USB) and the car (OBD — it is OBD-powered).
7. Only one app may use the VCI at a time.
8. Vediamo: launch → **Update** → select **Part J only** → **Update**.

## License

Provided as-is for personal/educational use.