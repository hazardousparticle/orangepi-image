#! /bin/bash

# setup script for bare metal Arch Linux os. Run as root

TIMEZONE='Australia/Melbourne'

# update list of packages
pacman -Syy

# enable alternative dhcp client (for ipv6)
systemctl disable systemd-networkd
systemctl enable dhcpcd
echo 'send fqdn.fqdn = pick-first-value(gethostname(), "ISC-dhclient");' > /etc/dhclient.conf
systemctl stop systemd-networkd
systemctl start dhcpcd

# random customizations
cat >> /etc/bash.bashrc << EOF
export TZ="$TIMEZONE"
complete -cf sudo
alias grep='grep --color=always'
alias ls='ls --color=auto'
alias ll='ls -l'
export PS1='\[\033[01;32m\][\u@\h\[\033[00m\]:\[\033[01;34m\]\W\[\033[01;32m\]]\[\033[01;34m\]\$\[\033[00m\] '
EOF

chmod +s $(which ping)

echo "Defaults insults" >> /etc/sudoers

cat > /root/.bashrc << EOF
# .bashrc

# User specific aliases and functions

alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

# Source global definitions
if [ -f /etc/bashrc ]; then
	. /etc/bashrc
fi

[[ $- != *i* ]] && return

echo -e "\e[32mThis is a root terminal. Be very careful!\e[00m"

export PS1='\[\033[01;31m\][\u@\h\[\033[0m\]:\[\033[01;34m\]\W\[\033[01;31m\]]\$\[\033[00m\] '


echo -e "\e[31m"
echo " ██▀███   ▒█████   ▒█████  ▄▄▄█████▓               ";
echo "▓██ ▒ ██▒▒██▒  ██▒▒██▒  ██▒▓  ██▒ ▓▒               ";
echo "▓██ ░▄█ ▒▒██░  ██▒▒██░  ██▒▒ ▓██░ ▒░               ";
echo "▒██▀▀█▄  ▒██   ██░▒██   ██░░ ▓██▓ ░                ";
echo "░██▓ ▒██▒░ ████▓▒░░ ████▓▒░  ▒██▒ ░  ██▓  ██▓  ██▓ ";
echo "░ ▒▓ ░▒▓░░ ▒░▒░▒░ ░ ▒░▒░▒░   ▒ ░░    ▒▓▒  ▒▓▒  ▒▓▒ ";
echo "  ░▒ ░ ▒░  ░ ▒ ▒░   ░ ▒ ▒░     ░     ░▒   ░▒   ░▒  ";
echo "  ░░   ░ ░ ░ ░ ▒  ░ ░ ░ ▒    ░       ░    ░    ░   ";
echo "   ░         ░ ░      ░ ░             ░    ░    ░  ";
echo "                                      ░    ░    ░  ";
echo -e "\e[0m"
echo ""

date

echo ""
EOF

# timezone
timedatectl set-timezone $TIMEZONE

# install arch linux arm gpg keys
pacman -S archlinux-keyring --noconfirm
pacman -S archlinuxarm-keyring --noconfirm
pacman-key --init
pacman-key --populate archlinux
pacman-key --populate archlinuxarm

# configure pacman
## prevent installing new kernel
perl -pi -e 's/^(?:#)(IgnorePkg\s*=)/\1 linux-armv7/g' /etc/pacman.conf
## enable colored output
perl -pi -e 's/^(?:#)(Color)/\1/g' /etc/pacman.conf
## force pacman to verfiy package signatures
perl -pi -e 's/^(SigLevel = Never)/#\1/g' /etc/pacman.conf 
perl -pi -e 's/^(?:#)(SigLevel\s*= Required DatabaseOptional)/\1/g' /etc/pacman.conf

# package installation
pacman -S ntp vim sudo --noconfirm

# ntp setup
systemctl enable ntpd
systemctl disable systemd-timesyncd
systemctl start ntpd
systemctl stop systemd-timesyncd

