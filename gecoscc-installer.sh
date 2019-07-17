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

export CHEF_SERVER_VERSION="12.16.9"
export CHEF_SERVER_PACKAGE_URL="https://packages.chef.io/files/stable/chef-server/$CHEF_SERVER_VERSION/el/6/chef-server-core-$CHEF_SERVER_VERSION-1.el6.x86_64.rpm"

# START: MAIN MENU

OPTION=$(whiptail --title "GECOS Control Center Installation" --menu "Choose an option" 16 78 10 \
"CHEF" "Install Chef server" \
"CC" "Install GECOS Control Center." \
"USER" "Create Control Center Superuser." \
"SET_SUPERUSER" "Set Control Center Superuser as Chef Superuser." \
)


case $OPTION in

    
CHEF)
    echo "INSTALLING CHEF SERVER"
    echo "Downloading package $CHEF_SERVER_PACKAGE_URL"
    curl -L "$CHEF_SERVER_PACKAGE_URL" > /tmp/chef-server.rpm
    echo "Installing package"
    rpm -Uvh --nosignature /tmp/chef-server.rpm
    echo "Configuring"
    mkdir -p /etc/opscode/
    install_template "/etc/opscode/chef-server.rb" chef-server.rb 644 -subst
    /opt/opscode/bin/chef-server-ctl reconfigure
    # Create the "default" organization
    /opt/opscode/bin/chef-server-ctl org-create default default
    echo "Opening port in Firewall"
    lokkit -s https
    echo "CHEF SERVER INSTALLED"
;;



CC)
echo "INSTALLING GECOS CONTROL CENTER"


echo "Installing docker"
apt install docker.io

echo "Installing GECOS Control Center UI"

echo "GECOS CONTROL CENTER INSTALLED"
;;

USER)
echo "CREATING CONTROL CENTER FIRST USER"
echo "(Pending)"
;;


esac



