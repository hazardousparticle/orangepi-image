#! /bin/bash

# Script for building U-boot and upstream Linux kernel for orangepi-one
# Script also builds distro SD card image

set -e

download="true"
if [ "$1" == "--no-download" ]; then
    # don't re download everything
    download=""
    echo "Will not re-download files"
fi

# commands for printing in color
green()
{
    # green color printing text
    GREEN="\e[32m"
    BLACK="\e[0m"
    echo -e "$GREEN$*$BLACK"
}

red()
{
    # red color printing text
    RED="\e[31m"
    BLACK="\e[0m"
    echo -e "$RED$*$BLACK"
}

blue()
{
    # blue color printing text
    BLUE="\e[34m"
    BLACK="\e[0m"
    echo -e "$BLUE$*$BLACK"
}

# the good stuff starts here

# Options
# sd card size in MB
SD_SIZE=1900
SD_IMAGE="orangepi-linux-$(date --iso-8601).img"
#cross compiler prefix
gcc_prefix="arm-linux-gnu-"
#gcc_prefix="arm-linux-gnueabihf-"

# cores to use for make
CORES="$(lscpu | grep "^CPU(s):" | awk '{print $2}')"

blue "Cores: $CORES"

WORK_DIR="/tmp/orangepi"

# git tags to use
UBOOT_GIT_VER="v2017.01"
LINUX_GIT_VER="v4.9"


# start the process
if [ "$download" == "true" ]; then
    if [ -d $WORK_DIR ]; then
        # delete and start over
        rm -rf $WORK_DIR
    fi
fi

mkdir -p $WORK_DIR
cp -f orangepi-kernel-config.patch $WORK_DIR/

cd $WORK_DIR/

blue "Preparing disk image..."
# pre-allocate the image
dd if=/dev/zero of=$SD_IMAGE bs=10M count=$[$SD_SIZE / 10]

# partition the sd card image
printf "n\np\n1\n\n+50M\nt\nc\nn\np\n2\n\n\nw\n\n" | fdisk $SD_IMAGE

green "Made partitions"

# make u-boot
blue "Preparing u-boot build..."
if [ "$download" == "true" ]; then
    git clone git://git.denx.de/u-boot.git -b $UBOOT_GIT_VER
fi
cd u-boot
make -j$CORES CROSS_COMPILE=$gcc_prefix orangepi_one_defconfig
make -j$CORES CROSS_COMPILE=$gcc_prefix

cd $WORK_DIR/

green "Made U-boot"

# make linux
blue "Preparing linux build..."
if [ "$download" == "true" ]; then
    git clone git://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git -b $LINUX_GIT_VER
fi
cd linux

# Apply sunxi patches
blue "Applying sun8i ethernet pacthes..."
# [v4,01/10] ethernet: add sun8i-emac driver
wget https://patchwork.kernel.org/patch/9365783/raw/ \
-O sun8i-emac-patch-1.patch
 
# [v4,04/10] ARM: dts: sun8i-h3: Add dt node for the syscon
wget https://patchwork.kernel.org/patch/9365773/raw/ \
-O sun8i-emac-patch-4.patch
 
# [v4,05/10] ARM: dts: sun8i-h3: add sun8i-emac ethernet driver
wget https://patchwork.kernel.org/patch/9365757/raw/ \
-O sun8i-emac-patch-5.patch
 
# [v4,07/10] ARM: dts: sun8i: Enable sun8i-emac on the Orange PI One
wget https://patchwork.kernel.org/patch/9365767/raw/ \
-O sun8i-emac-patch-7.patch
 
# [v4,09/10] ARM: sunxi: Enable sun8i-emac driver on sunxi_defconfig
wget https://patchwork.kernel.org/patch/9365779/raw/ \
-O sun8i-emac-patch-9.patch

for patch_file in *.patch; do
    patch -p1 < $patch_file
done

make -j$CORES ARCH=arm CROSS_COMPILE=$gcc_prefix sunxi_defconfig
patch -p1 < $WORK_DIR/orangepi-kernel-config.patch
make -j$CORES ARCH=arm CROSS_COMPILE=$gcc_prefix zImage dtbs
green "Made Linux"

cd $WORK_DIR/

# wait for user to press enter when its time to do root stuff
# otherwise sudo will terminate with an error if it waits too long
red "The next phase requires sudo permissions. When ready press enter to continue..."
read


# format the sd card partitions

sudo kpartx -a $SD_IMAGE
loop_dev="$(losetup -l | grep $SD_IMAGE | awk '{print $1}' | cut -f3 -d'/')"

if [ -z "$loop_dev" ]; then
    red "Error: No loop device."
    exit 1
fi

red "Loop device used for mounting SD card image: $loop_dev"

sudo mkfs.vfat /dev/mapper/"$loop_dev"p1
sudo mkfs.ext4 /dev/mapper/"$loop_dev"p2

green "Formatted partitions"

# mount the image for adding files
mkdir -p orangepi-root
mkdir -p orangepi-boot

sudo mount /dev/mapper/"$loop_dev"p1 orangepi-boot
sudo mount /dev/mapper/"$loop_dev"p2 orangepi-root

# make the boot command
# bootz instead of bootm if using a zImage (gzipped kernel image)
cat << EOF > boot.cmd
setenv bootargs console=ttyS0,115200 root=/dev/mmcblk0p2 rootwait rw panic=10
load mmc 0:1 0x43000000 sun8i-h3-orangepi-one.dtb
load mmc 0:1 0x42000000 zImage
bootz 0x42000000 - 0x43000000
EOF

# install the kernel and boot files
mkimage -C none -A arm -T script -d boot.cmd boot.scr
sudo cp boot.cmd ./orangepi-boot/boot.cmd
sudo cp boot.scr ./orangepi-boot/boot.scr

sudo cp linux/arch/arm/boot/zImage ./orangepi-boot/
sudo cp linux/arch/arm/boot/dts/sun8i-h3-orangepi-one.dtb ./orangepi-boot/

green "Copied boot files"

# install the os
blue "Downloading Arch Linux..."
if [ "$download" == "true" ]; then
    wget "http://os.archlinuxarm.org/os/ArchLinuxARM-armv7-latest.tar.gz"
fi
red "Download complete, Press enter when ready to run root commands"
read
sudo tar -xzvf "ArchLinuxARM-armv7-latest.tar.gz" -C "./orangepi-root/"
# have to untar as root cause there are root owned files in there

# OS customizations
cd ./orangepi-root/
blue "Configuring distro..."
echo "orangepi" | sudo tee "etc/hostname"
# file mounts
echo "/dev/mmcblk0p1  /boot   vfat    ro,defaults        0       0" | sudo tee -a "etc/fstab"
#change the user to orangepi
sudo sed -i 's/alarm/orangepi/g' "etc/passwd"
sudo sed -i 's/alarm/orangepi/g' "etc/group"
sudo mv "home/alarm" "home/orangepi"

# change the password
sudo head -n -1 "etc/shadow" | sudo tee "etc/shadow1" >/dev/null
sudo mv "etc/shadow1" "etc/shadow"
sudo chmod 0000 "etc/shadow"

# generate and hash the password
salt="$(cat /dev/urandom | base64 | head -c16)"
cat << EOF > "$WORK_DIR/pw_gen.py"
import crypt
import sys

print(crypt.crypt("orangepi", "\$6\$" + str(sys.argv[1]) + "\$"))
exit()
EOF
password=$(python "$WORK_DIR/pw_gen.py" $salt)

echo "orangepi:$password::0:99999:7:::" | sudo tee -a "etc/shadow" 1>/dev/null

green "Installed OS"

# cleanup
cd $WORK_DIR/

blue "Unmounting image..."
sudo umount orangepi-boot
sudo umount orangepi-root

# install u-boot bootloader to the SD card
blue "Installing bootloader onto image..."
sudo dd if="u-boot/u-boot-sunxi-with-spl.bin" of=$"/dev/$loop_dev" bs=1024 seek=8

sudo kpartx -d $SD_IMAGE

green "ALL DONE!"
blue "Finished Image: $WORK_DIR/$SD_IMAGE"

