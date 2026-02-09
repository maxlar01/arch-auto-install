# Arch Linux Automated Installer

A fully automated **Arch Linux base installation script** designed for both **bare metal** and **virtual machines**.

This installer focuses on **clarity, safety, and modern best practices**, while still keeping the Arch philosophy of control and transparency.

> ⚠️ **WARNING**: This script will **DESTROY ALL DATA** on the selected disk. Use at your own risk.

---

## ✨ Features

* 🔐 Optional **LUKS full-disk encryption**
* 🔓 **TPM2 auto-unlock** support (with safe fallback)
* 🖥️ **Automatic VM detection** (VirtualBox, QEMU, VMware, etc.)
* 🧠 **VM-safe EFI mode** (skips NVRAM writes when needed)
* ⚙️ **Hardware auto-detection & tuning**

  * CPU vendor detection (Intel / AMD)
  * Microcode installation
  * Laptop detection + power management
* 🧩 Automatic **GPU driver selection** (Intel / AMD / NVIDIA)
* 🔑 Secure password setup (root + user)
* 🌍 Locale, timezone, and keymap configuration
* 📦 Fast installs via optimized pacman configuration
* 🧱 GRUB bootloader (UEFI)

---

## ⚡ Quick Start (TL;DR)

Already on the Arch ISO with working internet? Run this:

```bash
pacman -Sy --noconfirm git

git clone https://github.com/maxlar01/arch-auto-install.git
cd arch-auto-install
chmod +x install.sh
./install.sh
```

Follow the prompts, wait for completion, **remove the ISO**, reboot — done. 🚀

---

## 🧰 Requirements

* Booted from the **official Arch Linux ISO** (UEFI mode)
* Working internet connection
* Target system supports UEFI
* TPM2 hardware (optional, for auto-unlock)

---

## 🚀 How to Use

### 1️⃣ Boot into the Arch ISO

* Use **UEFI mode**
* Ensure networking works:

```bash
ping -c 3 archlinux.org
```

---

### 2️⃣ Install git (ISO environment)

```bash
pacman -Sy --noconfirm git
```

---

### 3️⃣ Download the installer

```bash
git clone https://github.com/maxlar01/arch-auto-install.git
cd arch-auto-install
chmod +x install.sh
```

---

### 4️⃣ Run the installer

```bash
./install.sh
```

You will be prompted for:

* Disk selection
* Encryption (LUKS) choice
* Username
* Hostname
* Passwords

---

## 🔐 Encryption & TPM2

If you enable **LUKS encryption**:

* The root partition is encrypted using **LUKS2**
* If TPM2 is detected:

  * A TPM-backed unlock key is enrolled automatically
* If TPM2 is unavailable:

  * System falls back to **passphrase-only** unlock

This ensures the system always remains bootable.

---

## 🖥️ VM Support

The installer automatically detects virtualized environments and:

* Uses **EFI removable install mode** when required
* Avoids unsafe NVRAM writes
* Works out-of-the-box on:

  * VirtualBox
  * QEMU / KVM
  * VMware

---

## ⚙️ Hardware Auto-Tuning

The script detects and configures:

* CPU vendor → installs correct microcode
* GPU vendor → installs correct drivers
* Laptop chassis → enables `tlp`

This provides sane defaults without sacrificing control.

---

## 📦 Pacman Improvements

The installed system is configured with:

* `Color`
* `ILoveCandy`
* `ParallelDownloads`
* `VerbosePkgLists`
* `CheckSpace`
* `UseSyslog`
* **Multilib repository enabled**

This improves speed, usability, and aesthetics.

---

## 🧹 After Installation

When installation completes:

1. Power off or reboot
2. **Remove the ISO** from your VM or USB
3. Boot into your new Arch system 🎉

---

## 🛠️ Customization

You can edit `install.sh` before running it to adjust:

* Timezone
* Locale
* Keymap
* Default packages
* Filesystem choices

The script is intentionally readable and hackable.

---

## 🧠 Philosophy

This installer aims to:

* Automate the boring parts
* Keep decisions explicit
* Avoid hidden magic
* Stay close to official Arch practices

It’s a **learning-friendly automation**, not a black box.

---

## ❗ Disclaimer

This project is **not officially supported by Arch Linux**.

Always review the script before running it on real hardware.

---

## 📜 License

MIT License

---

Happy hacking 🐧🔥
