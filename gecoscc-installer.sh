#!/bin/bash
#
# GECOS Control Center Installer
#
# Authors: 
#   Alfonso de Cala <alfonso.cala@juntadeandalucia.es>
#
# Copyright 2019, Junta de Andalucia
# http://www.juntadeandalucia.es/
#
# Released under EUPL License V 1.1
# http://www.osor.eu/eupl 

set -u
set -e

CHEF_SERVER_VERSION="12.18.14"  # For Ubuntu 18.04


# START: MAIN MENU

OPTION=$(whiptail --title "GECOS Control Center Installation" --menu "Choose an option" 16 68 8 \
"CC" "Install GECOS Control Center." \
"CCUSER" "Create a GECOS Control Center User." \
"CHEF" "Install Chef server" \
"CHEFUSER" "Create a CHEF User." \
"SET_SUPERUSER" "Set Control Center Superuser as Chef Superuser." \
 3>&1 1>&2 2>&3)


case $OPTION in


CC)
echo "INSTALLING GECOS CONTROL CENTER"

echo "Installing docker"
apt install docker.io docker-compose
systemctl start docker

echo "Installing Control Center UI"
docker-compose build
# WARNING: If DNS resolution fails, you need to configure your DNS server properly in /etc/docker/daemon.json and then restart your Docker daemon. Please read: https://stackoverflow.com/questions/24991136/docker-build-could-not-resolve-archive-ubuntu-com-apt-get-fails-to-install-a/40516974#40516974

echo "GECOS CONTROL CENTER INSTALLED"
;;



CCUSER)
echo "CREATING CONTROL CENTER USER"

ADMIN_USER=$(whiptail --inputbox "Username" 8 78 superadmin --title "Creating Control Center User" 3>&1 1>&2 2>&3)
[ -z "$ADMIN_USER" ] && exit 1
ADMIN_EMAIL=$(whiptail --inputbox "E-Mail Address" 8 78 superadmin@test.com --title "Creating Control Center User" 3>&1 1>&2 2>&3)
[ -z "$ADMIN_EMAIL" ] && exit 1

docker exec -ti web pmanage gecoscc.ini create_adminuser --username $ADMIN_USER --email $ADMIN_EMAIL --is-superuser

whiptail --msgbox "User $ADMIN_USER created." 8 78 --title "Creating Chef User" 3>&1 1>&2 2>&3


;;


    
CHEF)

    echo "INSTALLING CHEF SERVER"
    echo "Please, check your FQDN, firewall, apparmor, ntp and mail configuration, before continuing"
#   example for apparmor deactivation: aa-complain /etc/apparmor.d/*

    read -p "Continue? (y/n)" -n 1 -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]
    then
          [[ "$0" = "$BASH_SOURCE" ]] && exit 1 
    fi

    apt update
    apt install curl wget

    echo "Downloading Chef package $CHEF_SERVER_VERSION"
    wget https://packages.chef.io/files/stable/chef-server/${CHEF_SERVER_VERSION}/ubuntu/18.04/chef-server-core_${CHEF_SERVER_VERSION}-1_amd64.deb
    echo "Installing package"  
    dpkg -i chef-server-core_${CHEF_SERVER_VERSION}-1_amd64.deb

    # Non serving on port 80 (just in case you install Control Center and Chef in the same machine)
    echo "nginx['non_ssl_port'] = false" > /etc/opscode/chef-server.rb

    echo "Configuring"
    chef-server-ctl reconfigure

    # Create the "default" organization
    chef-server-ctl org-create default default

    echo "CHEF SERVER INSTALLED"
    echo "Please, copy /etc/opscode/pivotal.pem to a safe place."
;;

CHEFUSER)
echo "CREATING CHEF USER"

ADMIN_USER=$(whiptail --inputbox "Username" 8 78 superadmin --title "Creating Chef User" 3>&1 1>&2 2>&3)
[ -z "$ADMIN_USER" ] && exit 1
ADMIN_EMAIL=$(whiptail --inputbox "E-Mail Address" 8 78 superadmin@test.com --title "Creating Chef User" 3>&1 1>&2 2>&3)
[ -z "$ADMIN_EMAIL" ] && exit 1
ADMIN_PASSWORD=$(whiptail --passwordbox "Password" 8 78 --title "Creating Chef User" 3>&1 1>&2 2>&3)
[ -z "$ADMIN_PASSWORD" ] && exit 1
ADMIN_PASSWORD2=$(whiptail --passwordbox "Repeat Password" 8 78 --title "Creating Chef User" 3>&1 1>&2 2>&3)
[ -z "$ADMIN_PASSWORD2" ] && exit 1

if [[ "$ADMIN_PASSWORD" != "$ADMIN_PASSWORD2" ]]
then
    whiptail --msgbox "Password are diferent!" 8 78 --title "Creating Chef User" 3>&1 1>&2 2>&3
    exit 1
fi

chef-server-ctl user-create $ADMIN_USER GECOS ADMIN $ADMIN_EMAIL "$ADMIN_PASSWORD" --filename /tmp/chefadmin.pem

whiptail --msgbox "User $ADMIN_USER created. Please, move your keyfile /tmp/chefadmin.pem to a safe place" 8 78 --title "Creating Chef User" 3>&1 1>&2 2>&3

;;


esac



