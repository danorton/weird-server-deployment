#!/bin/bash
set -e

# Allow public key for root ssh login
if [ "$WEIRD_SSH_KEY_URL" ]; then
  mkdir -p /root/.ssh
  curl -sS "$WEIRD_SSH_KEY_URL" >> /root/.ssh/authorized_keys
  chmod -R o-rwx /root/.ssh
fi

# Fix hostname and make it stick after reboot
if [ "$WEIRD_NEW_HOSTNAME" ]; then
  echo $WEIRD_NEW_HOSTNAME > /etc/hostname
  hostname -F /etc/hostname
fi
cat /etc/hostname > /etc/mailname

# get rid of exim4 and fetch puppet
# we need "ed" for this selfsame script
apt-get -qyf install ed ssmtp bsd-mailx puppet

# Don't let puppet interfere during our init
service puppet stop

# Upgrade packages that had already been installed
apt-get -qy upgrade
apt-get -qy dist-upgrade

# get rid of cached packages
apt-get -qy --purge autoremove
dpkg --get-selections \
  | sed -ne 's/[\t]*deinstall//p' \
  | xargs dpkg --purge \
 || true

# Add Private IP address
if [ "$WEIRD_LAN_IPV4" ]; then
  WEIRD_LAN_IPV4_IP=${WEIRD_LAN_IPV4///*}
  WEIRD_LAN_IPV4_MASK=${WEIRD_LAN_IPV4##*/}
  cat << __EOF__ >> /etc/network/interfaces

# Private IP address
auto eth0:1
iface eth0:1 inet static
    address $WEIRD_LAN_IPV4_IP
    netmask $WEIRD_LAN_IPV4_MASK
__EOF__
fi

# Get basic but non-standard puppet functions
mkdir -p /var/lib/puppet/lib/facter
curl -sSo /var/lib/puppet/lib/facter/meminbytes.rb \
     https://weirdmasters.com/puppet/facter/meminbytes.rb

# Add puppet agent configuration
cat << '__EOF__' >> /etc/puppet/puppet.conf
[agent]
server = puppet.weirdmasters.com
listen = true
__EOF__

# puppet auth configuration to allow "kick" from master
curl -sSo /etc/puppet/auth.conf \
     https://weirdmasters.com/puppet/auth.conf

# start puppet at sysinit
echo -e "1,\$s/START=no/START=yes/\nwq" | ed /etc/default/puppet \
 || true

# Our initial set of aliases for new accounts
cat << '__EOF__' > /etc/skel/.bash_aliases
unalias -a
alias mv='mv -i'
alias cp='cp -i'
alias rm='rm -i'
alias ls='ls --color=auto'
alias ll='ls -alF'
__EOF__

# re-init root account with updated skeleton files
cp /etc/skel/.profile \
   /etc/skel/.bash_aliases \
   /etc/skel/.bashrc \
 /root/

# disable root password if we have a public key
if [ -s /root/.ssh/authorized_keys ]; then
  echo -e "1,\$s/^root:[^:]*:/root:\!:/\nwq" | ed /etc/shadow
fi

# clean up
set -x
rm -f "$0"
