#!/bin/bash

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
set +o nounset

ADMIN_USER=superadmin
ADMIN_EMAIL=test@test.com

export CHEF_SERVER_VERSION="12.16.9"


# START: MAIN MENU

OPTION=$(whiptail --title "GECOS Control Center Installation" --menu "Choose an option" 16 78 10 \
"CHEF" "Install Chef server" \
"CC" "Install GECOS Control Center." \
"USER" "Create Control Center First User." \
"SET_SUPERUSER" "Set Control Center Superuser as Chef Superuser." \
)


case $OPTION in

    
CHEF)

    echo "INSTALLING CHEF SERVER"
    echo "Please, check your FQDN, firewall, apparmor, ntp and mail configuration, before continuing"
    apt update
    apt install curl wget
    aa-complain /etc/apparmor.d/*


    echo "Downloading package $CHEF_SERVER_PACKAGE_URL"
    curl -L "$CHEF_SERVER_PACKAGE_URL" > /tmp/chef-server.rpm
    wget https://packages.chef.io/files/stable/chef-server/${CHEF_SERVER_VERSION}/ubuntu/18.04/chef-server-core_${CHEF_SERVER_VERSION}-1_amd64.deb
    echo "Installing package"  
    dpkg -i chef-server-core_${CHEF_SERVER_VERSION}-1_amd64.deb
    echo "Configuring"
    chef-server-ctl reconfigure

    echo "Creating an administrator account"
    chef-server-ctl user-create $ADMIN_USER GECOS ADMIN $ADMIN_EMAIL '$ADMIN_PASSWORD' --filename /tmp/chefadmin.pem

    mkdir -p /etc/opscode/
    install_template "/etc/opscode/chef-server.rb" chef-server.rb 644 -subst

    # Create the "default" organization
    chef-server-ctl org-create default default

    echo "CHEF SERVER INSTALLED"
    echo "Please, move /tmp/chefadmin.pem to a safe place."
;;



CC)
echo "INSTALLING GECOS CONTROL CENTER"


echo "Installing docker"
apt install docker.io docker-compose
systemctl start docker
docker-compose build
# WARNING: If DNS resolution fails, you need to configure your DNS server properly in /etc/docker/daemon.json and then restart your Docker daemon. Please read: https://stackoverflow.com/questions/24991136/docker-build-could-not-resolve-archive-ubuntu-com-apt-get-fails-to-install-a/40516974#40516974

echo "Installing GECOS Control Center UI"

echo "GECOS CONTROL CENTER INSTALLED"
;;

USER)
echo "CREATING CONTROL CENTER FIRST USER"
docker exec -ti web pmanage gecoscc.ini create_adminuser --username $ADMIN_USER --email $ADMIN_EMAIL
;;


esac



