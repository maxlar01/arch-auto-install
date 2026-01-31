#!/usr/bin/env bash
# Arch Linux Automated Base Install Script (UEFI)
# OPTIONAL: LUKS Full Disk Encryption
# WARNING: THIS WILL WIPE THE TARGET DISK

set -euo pipefail

### ===== USER CONFIG =====
DISK="/dev/sda"
HOSTNAME="arch"
USERNAME="maxlar"
TIMEZONE="Africa/Cairo"
LOCALE="en_US.UTF-8"
KEYMAP="us"
EFI_SIZE="512M"
### =======================

echo "== Arch Linux Automated Installer By Maxlar =="
read -rp "This will ERASE ${DISK}. Type YES to continue: " CONFIRM
[[ "$CONFIRM" == "YES" ]] || exit 1

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

echo "[1/11] Enabling NTP"
timedatectl set-ntp true

# --- Partition Disk ---
echo "[2/11] Partitioning disk"
sgdisk --zap-all "$DISK"
sgdisk -n 1:0:+$EFI_SIZE -t 1:ef00 "$DISK"
sgdisk -n 2:0:0 -t 2:8300 "$DISK"
partprobe "$DISK"

EFI_PART="${DISK}1"
ROOT_PART="${DISK}2"

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
echo "[4/11] Formatting partitions"
mkfs.fat -F32 "$EFI_PART"
mkfs.ext4 -F "$ROOT_DEV"

# --- Mount ---
echo "[5/11] Mounting partitions"
mount "$ROOT_DEV" /mnt
mkdir -p /mnt/boot
mount "$EFI_PART" /mnt/boot

# --- Install Base ---
echo "[6/11] Installing base system"
# --- Hardware auto-detection (pre-install) ---
CPU_VENDOR=$(lscpu | awk -F: '/Vendor ID/ {gsub(/ /, "", $2); print $2}')
GPU_VENDOR=$(lspci | grep -E "VGA|3D" || true)
IS_LAPTOP=$(cat /sys/class/dmi/id/chassis_type 2>/dev/null | grep -Eq "8|9|10|14" && echo yes || echo no)

echo "[INFO] CPU vendor: $CPU_VENDOR"
echo "[INFO] GPU info: $GPU_VENDOR"
echo "[INFO] Laptop detected: $IS_LAPTOP"

# --- Install Base ---
echo "[6/12] Installing base system"
EXTRA_PKGS=""

# CPU microcode
if [[ "$CPU_VENDOR" == "GenuineIntel" ]]; then
  EXTRA_PKGS+=" intel-ucode"
elif [[ "$CPU_VENDOR" == "AuthenticAMD" ]]; then
  EXTRA_PKGS+=" amd-ucode"
fi

pacstrap /mnt base linux linux-firmware vim sudo networkmanager grub efibootmgr cryptsetup systemd $EXTRA_PKGS

# --- fstab ---
echo "[7/11] Generating fstab"
genfstab -U /mnt >> /mnt/etc/fstab

# --- Chroot Config ---
echo "[8/11] Configuring system"
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
if [[ "$USE_LUKS" == "yes" ]] && systemd-detect-virt --quiet || [[ -c /dev/tpmrm0 ]]; then
  echo "[INFO] TPM2 detected, enrolling auto-unlock"
  systemd-cryptenroll --tpm2-device=auto /dev/disk/by-uuid/$(blkid -s UUID -o value $ROOT_PART)
else
  echo "[INFO] TPM2 not available, using passphrase only"
filesystems fsck)/' /etc/mkinitcpio.conf
  mkinitcpio -P
  echo "cryptroot UUID=$(blkid -s UUID -o value $ROOT_PART) none luks" >> /etc/crypttab
fi

if [[ "$IS_VM" == "yes" ]]; then
  grub-install --target=x86_64-efi --efi-directory=/boot --removable
else
  grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
fi

if [[ "$USE_LUKS" == "yes" ]]; then
  sed -i "s|GRUB_CMDLINE_LINUX=\"\"|GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=$(blkid -s UUID -o value $ROOT_PART):cryptroot root=/dev/mapper/cryptroot\"|" /etc/default/grub
fi

grub-mkconfig -o /boot/grub/grub.cfg

useradd -m -G wheel -s /bin/bash $USERNAME
sed -i 's/^# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers

EOF

# --- Passwords ---
echo "[9/11] Set passwords"
echo "Set ROOT password"
arch-chroot /mnt passwd

echo "Set password for $USERNAME"
arch-chroot /mnt passwd "$USERNAME"

# --- Finish ---
echo "[10/11] Cleaning up"
umount -R /mnt

# --- Done ---
echo "[11/11] Installation complete! Reboot and remove install media."
