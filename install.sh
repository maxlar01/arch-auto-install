#!/usr/bin/env bash
# WARNING: THIS SCRIPT IS EXPERIMENTAL AND PROVIDED "AS IS"
# WARNING: THIS WILL WIPE THE TARGET DISK

set -euo pipefail

### ===== USER CONFIG =====
# DISK will be selected interactively
DISK=""
# HOSTNAME and USERNAME will be selected interactively
HOSTNAME=""
USERNAME=""
TIMEZONE="Africa/Cairo"
LOCALE="en_US.UTF-8"
KEYMAP="us"
EFI_SIZE="512M"
SCRIPT_REPO="https://raw.githubusercontent.com/maxlar01/arch-auto-install/main/install.sh"
### =======================


# --- Self-update mechanism ---
echo "[INFO] Checking for script updates..."
TMP_SCRIPT="/tmp/arch_installer_latest.sh"
if curl -fsSL "$SCRIPT_REPO" -o "$TMP_SCRIPT"; then
    if ! cmp -s "$TMP_SCRIPT" "$0"; then
        echo "[INFO] New version found. Updating and re-executing script..."
        chmod +x "$TMP_SCRIPT"
        exec "$TMP_SCRIPT" "$@"
    else
        echo "[INFO] Script is up-to-date. Continuing..."
    fi
else
    echo "[WARN] Could not check for updates. Continuing with current script."
fi

echo "== Arch Linux Automated Installer By Maxlar =="

echo
while true; do
  read -rp "Enter hostname for this system: " HOSTNAME

  # RFC 952 / 1123 hostname validation
  if [[ ! "$HOSTNAME" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]]; then
    echo "[ERROR] Invalid hostname. Use lowercase letters, digits, and '-', max 63 chars, no leading/trailing '-'."
    continue
  fi

  break
done

echo
while true; do
  read -rp "Enter username to create: " USERNAME

  # must start with lowercase letter, contain only lowercase letters, numbers, underscore or hyphen
  if [[ ! "$USERNAME" =~ ^[a-z][a-z0-9_-]*$ ]]; then
    echo "[ERROR] Invalid username. Use lowercase letters, numbers, '-' or '_', and start with a letter."
    continue
  fi

  # avoid reserved/system usernames
  if getent passwd "$USERNAME" >/dev/null; then
    echo "[ERROR] Username '$USERNAME' already exists. Choose another one."
    continue
  fi

  break
done

echo "[INFO] Hostname set to: $HOSTNAME"
echo "[INFO] Username set to: $USERNAME"

echo "Available disks:"
lsblk -dpno NAME,SIZE,MODEL | grep -E "HARDDISK|Disk|disk"

echo
while true; do
  read -rp "Enter the disk to install Arch Linux on (e.g. /dev/nvme0n1): " DISK

  if [[ ! -b "$DISK" ]]; then
    echo "[ERROR] $DISK is not a valid block device. Please try again."
    continue
  fi

  echo
  read -rp "This will ERASE ALL DATA on $DISK. Type YES to continue (or NO to reselect): " CONFIRM

  if [[ "$CONFIRM" == "YES" ]]; then
    break
  else
    echo "[INFO] Disk selection cancelled. Please choose again."
  fi
done

read -rp "Enable FULL DISK ENCRYPTION (LUKS)? (yes/no): " USE_LUKS
# --- VM Detection ---
if systemd-detect-virt --quiet; then
  IS_VM="yes"
  echo "[INFO] Virtual machine detected"
else
  IS_VM="no"
  echo "[INFO] Bare metal detected"
fi

loadkeys "$KEYMAP"

echo "[1/12] Enabling NTP"
timedatectl set-ntp true

# --- Partition Disk ---
echo "[2/12] Partitioning disk"
sgdisk --zap-all "$DISK"
sgdisk -n 1:0:+$EFI_SIZE -t 1:ef00 "$DISK"
sgdisk -n 2:0:0 -t 2:8300 "$DISK"
partprobe "$DISK"

# Handle partition naming for NVMe vs SATA/SCSI
if [[ "$DISK" =~ "nvme" ]] || [[ "$DISK" =~ "mmcblk" ]]; then
  EFI_PART="${DISK}p1"
  ROOT_PART="${DISK}p2"
else
  EFI_PART="${DISK}1"
  ROOT_PART="${DISK}2"
fi

# --- Encryption (Optional) ---
if [[ "$USE_LUKS" == "yes" ]]; then
  echo "[3/12] Setting up LUKS encryption"
  cryptsetup luksFormat "$ROOT_PART"
  cryptsetup open "$ROOT_PART" cryptroot
  ROOT_DEV="/dev/mapper/cryptroot"
else
  ROOT_DEV="$ROOT_PART"
fi

# --- Format ---
echo "[4/12] Formatting partitions"
mkfs.fat -F32 "$EFI_PART"
mkfs.ext4 -F "$ROOT_DEV"

# --- Mount ---
echo "[5/12] Mounting partitions"
mount "$ROOT_DEV" /mnt
mkdir -p /mnt/boot
mount "$EFI_PART" /mnt/boot

# --- Add Reflector ---
echo "[6/12] Installing reflector for mirror optimization"
pacman -Sy --noconfirm python python-requests reflector
reflector --latest 12 --protocol https --sort rate --save /etc/pacman.d/mirrorlist

# --- Install Base ---
echo "[7/12] Installing base system"
# --- Hardware auto-detection (pre-install) ---
CPU_VENDOR=$(lscpu | awk -F: '/Vendor ID/ {gsub(/ /, "", $2); print $2}')
GPU_VENDOR=$(lspci | grep -E "VGA|3D" || true)
IS_LAPTOP=$(cat /sys/class/dmi/id/chassis_type 2>/dev/null | grep -Eq "8|9|10|14" && echo yes || echo no)

echo "[INFO] CPU vendor: $CPU_VENDOR"
echo "[INFO] GPU info: $GPU_VENDOR"
echo "[INFO] Laptop detected: $IS_LAPTOP"

EXTRA_PKGS=""

# CPU microcode
if [[ "$CPU_VENDOR" == "GenuineIntel" ]]; then
  EXTRA_PKGS+="intel-ucode"
elif [[ "$CPU_VENDOR" == "AuthenticAMD" ]]; then
  EXTRA_PKGS+="amd-ucode"
fi

pacstrap /mnt base linux linux-firmware vim sudo networkmanager grub efibootmgr cryptsetup systemd "$EXTRA_PKGS"

# --- fstab ---
echo "[8/12] Generating fstab"
genfstab -U /mnt >> /mnt/etc/fstab

# --- Chroot Config ---
echo "[9/12] Configuring system"

# Get UUID for use in chroot
ROOT_UUID=$(blkid -s UUID -o value "$ROOT_PART")

arch-chroot /mnt /bin/bash <<EOF
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

echo "$LOCALE UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf

echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts <<HOSTS
127.0.0.1 localhost
::1       localhost
127.0.1.1 $HOSTNAME.localdomain $HOSTNAME
HOSTS

systemctl enable NetworkManager

# --- Beautify Pacman ---
sed -i '/^#Color/c\Color' /etc/pacman.conf
sed -i '/^Color/a\ILoveCandy' /etc/pacman.conf
sed -i '/^#UseSyslog/c\UseSyslog' /etc/pacman.conf
sed -i '/^#CheckSpace/c\CheckSpace' /etc/pacman.conf
sed -i '/^#VerbosePkgLists/c\VerbosePkgLists' /etc/pacman.conf
sed -i '/^#ParallelDownloads/c\ParallelDownloads' /etc/pacman.conf

# --- Enable Multilib ---
sed -i '/\[multilib\]/,/Include/ s/^#//' /etc/pacman.conf
pacman -Syyu --noconfirm

# --- Install Reflector (post-install) ---
pacman -S --noconfirm reflector
cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak
reflector --latest 50 --protocol https --sort rate --save /etc/pacman.d/mirrorlist

# --- GPU drivers ---
if echo "$GPU_VENDOR" | grep -qi intel; then
  pacman -S --noconfirm mesa
elif echo "$GPU_VENDOR" | grep -qi amd; then
  pacman -S --noconfirm mesa xf86-video-amdgpu
elif echo "$GPU_VENDOR" | grep -qi nvidia; then
  pacman -S --noconfirm nvidia nvidia-utils
fi

# --- Laptop power management ---
if [[ "$IS_LAPTOP" == "yes" ]]; then
  pacman -S --noconfirm tlp
  systemctl enable tlp
fi

# --- Initramfs for LUKS ---
if [[ "$USE_LUKS" == "yes" ]]; then
  sed -i 's/^HOOKS=.*/HOOKS=(base systemd autodetect keyboard sd-vconsole modconf block sd-encrypt filesystems fsck)/' /etc/mkinitcpio.conf
  mkinitcpio -P
fi

# --- TPM2 Auto-Unlock (Optional) ---
if [[ "$USE_LUKS" == "yes" ]]; then
  if systemd-detect-virt --quiet; then
    echo "[INFO] VM detected, skipping TPM2 auto-unlock"
  elif [[ -c /dev/tpmrm0 ]]; then
    echo "[INFO] TPM2 detected, enrolling auto-unlock"
    systemd-cryptenroll --tpm2-device=auto \
      /dev/disk/by-uuid/$ROOT_UUID
  else
    echo "[INFO] TPM2 not available, using passphrase only"
  fi
  echo "cryptroot UUID=$ROOT_UUID none luks" >> /etc/crypttab
fi

if [[ "$IS_VM" == "yes" ]]; then
  grub-install --target=x86_64-efi --efi-directory=/boot --removable
else
  grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
fi

if [[ "$USE_LUKS" == "yes" ]]; then
  sed -i "s|GRUB_CMDLINE_LINUX=\"\"|GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=$ROOT_UUID:cryptroot root=/dev/mapper/cryptroot\"|" /etc/default/grub
fi

grub-mkconfig -o /boot/grub/grub.cfg

useradd -m -G wheel -s /bin/bash $USERNAME
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

EOF

# --- Passwords ---
echo "[10/12] Set passwords"
echo "Set ROOT password"
arch-chroot /mnt passwd

echo "Set password for $USERNAME"
arch-chroot /mnt passwd "$USERNAME"

# --- Finish ---
echo "[11/12] Cleaning up"
umount -R /mnt

# --- Done ---
echo "[12/12] Installation complete! Reboot and remove install media."