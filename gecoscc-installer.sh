#!/bin/bash
#
# GECOS Control Center Installer
#
# Authors: 
#   Alfonso de Cala <alfonso.cala@juntadeandalucia.es>
#   Abraham Macias <amacias@gruposolutia.com>
#
# Copyright 2019, Junta de Andalucia
# http://www.juntadeandalucia.es/
#
# Released under EUPL License V 1.1
# http://www.osor.eu/eupl 

set -u
set -e


# Recommended host:
#  - RHEL 7 or 8
#  - 4 CPU
#  - 16 GB RAM
#  - 64 GB HDD

# Minimum host:
#  - RHEL 7 or 8
#  - 1 CPU
#  - 6 GB RAM
#  - 20 GB HDD

HOST_IP_ADDR=`ip addr | grep eth0 | grep inet | awk '{print $2}' | awk -F '/' '{ print $1}'`
if [ "$HOST_IP_ADDR" == "" ]
then
    HOST_IP_ADDR=`ip addr | grep ens | grep inet | awk '{print $2}' | awk -F '/' '{ print $1}'`
fi

HOSTNAME=$(hostname)
if [ "$HOSTNAME" == "localhost.localdomain" ]
then
    # Hostname is not properly configured --> use public IP
    HOSTNAME=$HOST_IP_ADDR

fi

# -------------------------------- setup constants START ---------------------
DOCKERIMGNAME=guadalinexgecos/gecoscc
RUNUSER=gecos
RUNGROUP=gecos
GCC_URL='https://codeload.github.com/gecos-team/gecoscc-installer/zip/dev-environment'
COOKBOOKSDIR='/opt/gecosccui/.chef/cookbooks'


GECOS_WS_MGMT_VER=0.11.4
GECOS_OHAI_VER=1.15.1

export GECOSCC_POLICIES_URL="https://github.com/gecos-team/gecos-workstation-management-cookbook/archive/$GECOS_WS_MGMT_VER.zip"
export GECOSCC_OHAI_URL="https://github.com/gecos-team/gecos-workstation-ohai-cookbook/archive/$GECOS_OHAI_VER.zip"


# -------------------------------- setup constants END -----------------------

# -------------------------------- Preconfigured variables BEGIN -------------
# MongoDB database address
MONGODB_URL=mongodb://mongo:27017/gecoscc

# Chef server URLs
# - The internal URL will be the address that the GECOS CC will use to
#   communicate with the Chef server.
# - The external URL will be the address that the Guadalinex GECOS based PCs
#   will use to communicate with the Chef server.
# (both addresses must point to the same server).
CHEF_SERVER_INTERNAL_URL=https://chef-server-nginx:8443/
CHEF_SERVER_URL=https://$HOSTNAME
CHEF_SERVER_VERSION="12.18.14" 

# Redis databases
SOCKJS_REDIS_SERVER_URL=redis://redis:6379/0
SOCKJS_REDIS_OPTIONS='{}'
CELERY_REDIS_SERVER_URL=redis://redis:6379/1
CELERY_REDIS_TRANSPORT_OPTIONS=""

# Supervisor credentials
SUPERVISOR_USER_NAME=internal
SUPERVISOR_PASSWORD=changeme
# -------------------------------- Preconfigured variables END -------------



RUN="runuser -l $RUNUSER -c"

DOCKER_BASE=docker
PYTHON=python

if [ "$USER" != "root" ]
then
    echo "This script must be executed as root!"
    echo "Please, check documentation for more information:"
    echo "https://github.com/gecos-team/gecoscc-installer/blob/master/README.md"
    echo "Aborting installation process."
    exit 1
fi 


function download_cookbook {
    echo "Downloading $1-$2"
    $RUN "docker exec -ti web wget https://supermarket.chef.io/cookbooks/$1/versions/$2/download -O /tmp/$1-$2.tar.gz -o /dev/null"
    $RUN "docker exec -ti web tar xzf /tmp/$1-$2.tar.gz -C $COOKBOOKSDIR"
    $RUN "docker exec -ti web rm /tmp/$1-$2.tar.gz"
}


function OS_checking {
    if [ -f /etc/redhat-release ]
    then
        [ `grep -c -i 'CentOS'  /etc/redhat-release` -ge "1" ] && \
            OS_SYS='centos'
        [ `grep -c -i 'Red Hat' /etc/redhat-release` -ge "1" ] && \
            OS_SYS='redhat'
        OS_VER=`cat /etc/redhat-release|egrep -o '[0-9].[0-9]'|cut -d'.' -f1 | head -n 1`
    else
        echo "Operating System not supported: wrong operating system."
        echo "Please, check documentation for more information:"
        echo "https://github.com/gecos-team/gecoscc-installer/blob/master/README.md"
        echo "Aborting installation process."
        exit 1
    fi

    if [ "$OS_VER" -ne 7 ] && [ "$OS_VER" -ne 8 ] 
    then
        echo "Operating System not supported: wrong version."
        echo "Please, check documentation for more information:"
        echo "https://github.com/gecos-team/gecoscc-installer/blob/master/README.md"
        echo "Aborting installation process."
        exit 2
    fi

    if [ "$OS_VER" -ne 7 ] 
    then
        # Note: sometimes it is necessary to remove podman and buildah before installing docker
        DOCKER_BASE=docker-ce
        PYTHON=python3
        # Check docker repo
        CONFIGURED=`dnf repolist -v | grep Repo-id | grep "docker" | wc -l`
        if [ $CONFIGURED -ne  1 ]
        then
            # Add docker repo
            dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
        fi
    fi

    # Check Elasticsearch configuration values
    if [ $(sysctl -n vm.max_map_count) -ne  262144 ]
    then
        echo "vm.max_map_count=262144" > /etc/sysctl.d/gecos.conf
        sysctl -w vm.max_map_count=262144
    fi

    # Check SELinux enforcing
    if [ $(getenforce) == "Enforcing" ]
    then
        setenforce 0
        sed -i 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/selinux/config
    fi

}

function RAM_checking {
    MEMINFO='/proc/meminfo'
    if [ -f $MEMINFO ] ; then
        TotalRAM=`cat $MEMINFO | grep MemTotal: | awk -F ' ' '{ print $2 }'`

        if [ ! $TotalRAM ] ; then
            echo "WARNING: Can't check the amount of RAM. Please ensure that this server has at least 6GB or RAM"
        else
            if [ $TotalRAM -lt "5900000" ] ; then
                echo "The host machine needs at least 6 GB of RAM."
                echo "Please, check documentation for more information:"
                echo "https://github.com/gecos-team/gecoscc-installer/blob/master/README.md"
                echo "Aborting installation process."
                exit 2
            fi

        fi
    else
        echo "WARNING: Can't check the amount of RAM. Please ensure that this server has at least 6GB or RAM"
    fi

}


function HDD_checking {
    TotalHDD=`df | grep /dev/mapper | awk -F ' ' '{ print $2 }'`

    if [ $TotalHDD -lt "17000000" ] ; then
        echo "The host machine needs at least 20 GB of HDD."
        echo "Please, check documentation for more information:"
        echo "https://github.com/gecos-team/gecoscc-installer/blob/master/README.md"
        echo "Aborting installation process."
        exit 2
    fi
}


function docker_checking {
    # Checking if docker is installed
    if [ ! -x /usr/bin/docker ]
    then
        echo "Installing docker"
        yum -y install $DOCKER_BASE
        chkconfig docker on
    fi

    # Checking if docker service is started
    RUNNING=0
    /bin/systemctl is-active --quiet docker.service && RUNNING=1
    if [ $RUNNING -eq  0 ]
    then
        # Start the docker service
        /bin/systemctl start docker.service
    fi

    # Checking if the docker group
    DOCKERGROUP=`cat /etc/group | grep docker |  awk -F':' '{ print $1 }' |  tail -n 1`
    SOCKETOWNER=`ls -l /var/run/docker.sock | awk -F ' ' '{print $4}'`
    if [ "$SOCKETOWNER" != "$DOCKERGROUP" ]
    then
        # Set the docker group as the owner of the socket
        echo "{ \"live-restore\": true, \"group\": \"$DOCKERGROUP\" }" > /etc/docker/daemon.json

        # Restart the docker server
        /bin/systemctl restart docker.service
    fi


    # Checking if docker-composer is installed
    if [ ! -x /usr/local/bin/docker-compose ]
    then
        # Install docker compose
        curl -L "https://github.com/docker/compose/releases/download/1.24.1/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
        ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
    fi

}


function tools_checking {

    # Checking if unzip is installed
    if [ ! -x /usr/bin/unzip ]
    then
        echo "Installing unzip"
        yum -y install unzip
    fi

    # Checking if openssl is installed
    if [ ! -x /usr/bin/openssl ]
    then
        echo "Installing openssl"
        yum -y install openssl
    fi

    # Checking if netcat is installed
    if [ ! -x /usr/bin/nc ]
    then
        echo "Installing netcat"
        yum -y install netcat
    fi

    # Checking if python3 is installed
    if [ ! -x /usr/bin/python3 ]
    then
        echo "Installing python3"
        yum -y install python3
    fi

}


function firewall_checking {
    # Checking if firewalld is installed
    if [ ! -x /usr/sbin/firewalld ]
    then
        echo "Installing firewalld"
        yum -y install firewalld
        systemctl enable firewalld
    fi

    # Checking if firewalld service is started
    RUNNING=0
    /bin/systemctl is-active --quiet firewalld && RUNNING=1
    if [ $RUNNING -eq  0 ]
    then
        # Start the firewalld service
        /bin/systemctl start firewalld
    fi

    # Check if the ports are open
    PORTS=`firewall-cmd --zone=public --list-ports`
    PORTS="P $PORTS"
    RELOAD=0
    if [[ $PORTS != *" 80/tcp"* ]]
    then
        # Open NginX port
        firewall-cmd --zone=public --add-port=80/tcp --permanent > /dev/null 2>&1
        RELOAD=1
    fi

    if [[ $PORTS != *" 443/tcp"* ]]
    then
        # Open Chef port
        firewall-cmd --zone=public --add-port=443/tcp --permanent > /dev/null 2>&1
        RELOAD=1
    fi

    if [ $RELOAD -eq  1 ]
    then
        # Reload the firewall service
        firewall-cmd --reload > /dev/null 2>&1
    fi
}


function opscode_chef_running_check {
    # Check that there is an running Opscode chef installation

    # Wait until the servers are online
    ONLINE=0
    while [ $ONLINE -eq 0 ]
    do
        sleep 3
        echo "Waiting for Opscode Chef server to be online..."
        curl -s -k https://localhost  > /dev/null && ONLINE=1
    done

    # Wait until status is "pong"
    export PYTHONIOENCODING=utf8
    cat >/tmp/check_chef.py <<EOL
import sys, json;

try:
    print(json.load(sys.stdin)['status'])
except:
    print("error")

EOL

    STATUS=`curl -s -k https://localhost/_status | python3 /tmp/check_chef.py`
    while [ $STATUS != 'pong' ]
    do
        sleep 3
        echo "Waiting for Opscode Chef server status to be 'pong'... (status=$STATUS)"
        STATUS=`curl -s -k https://localhost/_status | python3 /tmp/check_chef.py`
    done

    # Wait until the pivotal certificate exists
    while [ ! -f /data/chef/config/pivotal.pem ]
    do
        echo "Waiting for pivotal certificate file to exists..."
        sleep 3
    done

    echo "Private key exists!"

    # Check that the certificate is correct
    while ! openssl rsa -check -noout -in /data/chef/config/pivotal.pem > /dev/null 2>&1
    do
        echo "Waiting for a VALID pivotal certificate to exists..."
        sleep 3
    done

    echo "Private key is valid!"


}


# Checking if OS and version are right
OS_checking

# Checking if there is enough RAM
RAM_checking

# Checking if there is enough disk space
HDD_checking

# Checking docker installation
docker_checking

# Checking that other tools are installed
tools_checking

# Checking if the firewall is loaded and configured
firewall_checking

# START: MAIN MENU

OPTION=$(whiptail --title "GECOS Control Center Installation" --menu "Choose an option" 16 68 8 \
"REMOVE" "Uninstall a previous version of the GECOS CC." \
"CC" "Install GECOS Control Center." \
"CCUSER" "Create a GECOS Control Center User." \
"POLICIES" "Update Control Center Policies." \
"PRINTERS" "Update Printers Models Catalog." \
"PACKAGES" "Update Software Packages Catalog." \
 3>&1 1>&2 2>&3)


case $OPTION in

REMOVE)
echo "UNINSTALLING GECOS CONTROL CENTER"

if [ -f /etc/systemd/system/gecoscc.service ]
then
    # Stop the service
    /bin/systemctl stop gecoscc.service
fi

# Remove all containers
CONTAINERS=$($RUN "docker ps -a -q | tr \"\\n\" ' '")
if [ "$CONTAINERS" != "" ]
then
	$RUN "docker rm $CONTAINERS"
fi

# Remove all images
IMAGES=$($RUN "docker image list -q | tr \"\\n\" ' '")
if [ "$IMAGES" != "" ]
then
    $RUN "docker rmi --force $IMAGES"
fi

# Remove all volumes
VOLUMES=$($RUN "docker volume list -q | tr \"\\n\" ' '")
if [ "$VOLUMES" != "" ]
then
    $RUN "docker volume rm $VOLUMES"
fi

# Remove the software directory
rm -rf "/home/$RUNUSER/gecoscc-installer"

# remove the RUN script
rm -f /etc/systemd/system/gecoscc.service
/bin/systemctl daemon-reload

# Remove the user
userdel -r $RUNUSER

# Remove the user home directory
rm -rf "/home/$RUNUSER"

echo "GECOS CONTROL CENTER UNINSTALLED"
;;

CC)
echo "INSTALLING GECOS CONTROL CENTER"

# Check that the run user exists
RUNUSER_EXISTS=`grep "^$RUNUSER:" /etc/passwd | wc -l`
if [ $RUNUSER_EXISTS -eq 0 ]
then
    # create run user
    adduser -u 42 $RUNUSER
fi

# Check if the user belongs to docker o dockerroot group
DOCKERGROUP=`cat /etc/group | grep docker |  awk -F':' '{ print $1 }' | tail -n 1`
BELONGS=`groups $RUNUSER | grep $DOCKERGROUP | wc -l`
if [ $BELONGS -ne  1 ]
then
    usermod -aG $DOCKERGROUP $RUNUSER
fi


BASE="/home/$RUNUSER/"

# Download the installer
echo "Download from $GCC_URL to $BASE/gecoscc-installer.zip"
curl $GCC_URL -o "$BASE/gecoscc-installer.zip"
cd $BASE
if [ -d gecoscc-installer ]
then
    rm -rf gecoscc-installer
fi

unzip gecoscc-installer.zip > unzip.log
DIRECTORY=`cat unzip.log | grep creating | head -1 | awk -F ' ' '{print $2}' |  sed -r 's|/||g'`
rm gecoscc-installer.zip
rm unzip.log

if [ $DIRECTORY != 'gecoscc-installer' ]
then
    # Rename the unzipped directory
    mv $DIRECTORY gecoscc-installer
fi

BASE="/home/$RUNUSER/gecoscc-installer"


# Check if directories for docker volumes exists
mkdir -p /data/logs
mkdir -p /data/conf
mkdir -p /data/conf/.chef
mkdir -p /data/db
mkdir -p /data/gecoscc
mkdir -p /data/gecoscc/media
mkdir -p /data/chef/psql
mkdir -p /data/chef/elasticsearch
mkdir -p /data/chef/erchef
mkdir -p /data/chef/nginx
mkdir -p /data/chef/config
mkdir -p /data/chef/opscode
if [ ! -e /data/chef/opscode/private-chef-secrets.json ]
then
	ln -s /hab/svc/chef-server-ctl/config/hab-secrets-config.json /data/chef/opscode/private-chef-secrets.json
fi

mkdir -p /data/gecoscc/scripts/
if [ ! -f /data/gecoscc/scripts/chef_backup.sh ]
then 
    curl https://raw.githubusercontent.com/gecos-team/gecoscc-ui/master/gecoscc/scripts/chef_backup.sh -o /data/gecoscc/scripts/chef_backup.sh
fi

if [ ! -f /data/gecoscc/scripts/chef_restore.sh ]
then 
    curl https://raw.githubusercontent.com/gecos-team/gecoscc-ui/master/gecoscc/scripts/chef_restore.sh -o /data/gecoscc/scripts/chef_restore.sh
fi


if [ ! -x /data/gecoscc/scripts/chef_backup.sh ]
then 
    chmod 755 /data/gecoscc/scripts/chef_backup.sh
fi

if [ ! -x /data/gecoscc/scripts/chef_restore.sh ]
then 
    chmod 755 /data/gecoscc/scripts/chef_restore.sh
fi

if [ ! -f /data/conf/.chef/knife.rb ]
then 
    cp $BASE/templates/knife.rb /data/conf/.chef/knife.rb
    sed -i "s|CHEF_SERVER|$CHEF_SERVER_INTERNAL_URL|" /data/conf/.chef/knife.rb
    chmod 644 /data/conf/.chef/knife.rb
fi

if [ ! -f /data/conf/supervisord.conf ]
then 
    cp $BASE/templates/supervisord.conf /data/conf/supervisord.conf
    sed -i "s/SUPERVISOR_USER_NAME/$SUPERVISOR_USER_NAME/" /data/conf/supervisord.conf
    sed -i "s/SUPERVISOR_PASSWORD/$SUPERVISOR_PASSWORD/" /data/conf/supervisord.conf
fi

if [ ! -f /data/conf/gecoscc.ini ]
then 
    cp $BASE/templates/gecoscc.ini /data/conf/gecoscc.ini
    sed -i "s/SUPERVISOR_USER_NAME/$SUPERVISOR_USER_NAME/" /data/conf/gecoscc.ini
    sed -i "s/SUPERVISOR_PASSWORD/$SUPERVISOR_PASSWORD/" /data/conf/gecoscc.ini
    sed -i "s|MONGODB_URL|$MONGODB_URL|" /data/conf/gecoscc.ini
    sed -i "s|CHEF_SERVER_INTERNAL_URL|$CHEF_SERVER_INTERNAL_URL|" /data/conf/gecoscc.ini
    sed -i "s|CHEF_SERVER_URL|$CHEF_SERVER_URL|" /data/conf/gecoscc.ini
    sed -i "s|CHEF_SERVER_VERSION|$CHEF_SERVER_VERSION|" /data/conf/gecoscc.ini
    sed -i "s|SOCKJS_REDIS_SERVER_URL|$SOCKJS_REDIS_SERVER_URL|" /data/conf/gecoscc.ini
    sed -i "s|SOCKJS_REDIS_OPTIONS|$SOCKJS_REDIS_OPTIONS|" /data/conf/gecoscc.ini
    sed -i "s|CELERY_REDIS_SERVER_URL|$CELERY_REDIS_SERVER_URL|" /data/conf/gecoscc.ini
    sed -i "s|CELERY_REDIS_TRANSPORT_OPTIONS|$CELERY_REDIS_TRANSPORT_OPTIONS|" /data/conf/gecoscc.ini

fi

cp $BASE/CTL_SECRET /data/chef/CTL_SECRET


chown -R $RUNUSER:$RUNGROUP $BASE
chown -R $RUNUSER:$RUNGROUP /data/conf/.chef
chown -R $RUNUSER:$RUNGROUP /data/gecoscc

# Prepare the RUN script
cat >/etc/systemd/system/gecoscc.service <<EOL
[Unit]
Description=GECOS Control Center
Requires=docker.service
After=docker.service

[Service]
User=$RUNUSER
Group=$RUNGROUP
PermissionsStartOnly=true
WorkingDirectory=$BASE

ExecStart=/usr/local/bin/docker-compose up
ExecStop=/usr/local/bin/docker-compose down

TimeoutStartSec=0
Restart=on-failure
StartLimitIntervalSec=60
StartLimitBurst=3

[Install]
WantedBy=multi-user.target 
EOL

/bin/systemctl daemon-reload

# Pull the images
$RUN "cd $BASE; /usr/local/bin/docker-compose pull"

# Build the images
$RUN "cd $BASE; /usr/local/bin/docker-compose build"

rm -f /data/chef/config/pivotal.pem

# Start the services one by one for the first initialization
echo Start postgresql
$RUN "cd $BASE; nohup /usr/local/bin/docker-compose up postgresql > /tmp/postgresql.log 2>&1 &"
sleep 5
echo Start chef-server-ctl
$RUN "cd $BASE; nohup /usr/local/bin/docker-compose up chef-server-ctl > /tmp/chef-server-ctl.log 2>&1 &"
sleep 5
echo Start elasticsearch
$RUN "cd $BASE; nohup /usr/local/bin/docker-compose up elasticsearch > /tmp/elasticsearch.log 2>&1 &"
sleep 5
echo Start oc_id
$RUN "cd $BASE; nohup /usr/local/bin/docker-compose up oc_id > /tmp/oc_id.log 2>&1 &"
sleep 5
echo Start bookshelf
$RUN "cd $BASE; nohup /usr/local/bin/docker-compose up bookshelf > /tmp/bookshelf.log 2>&1 &"
sleep 5
echo Start oc_bifrost
$RUN "cd $BASE; nohup /usr/local/bin/docker-compose up oc_bifrost > /tmp/oc_bifrost.log 2>&1 &"
sleep 5
echo Start oc_erchef
$RUN "cd $BASE; nohup /usr/local/bin/docker-compose up oc_erchef > /tmp/oc_erchef.log 2>&1 &"
sleep 5
echo Start chef-server-nginx
$RUN "cd $BASE; nohup /usr/local/bin/docker-compose up chef-server-nginx > /tmp/oc_erchef.log 2>&1 &"
sleep 5

# Start GECOS services
/bin/systemctl start gecoscc.service


opscode_chef_running_check

sleep 1

# Check if the "default" organization exists
echo "Check if the \"default\" organization exists"
EXIST=$($RUN "docker exec -ti chef-server-ctl chef-server-ctl org-list | grep default | wc -l")
if [ $EXIST -eq 0 ]
then
	# Create the "default" organization
	echo "Creating the default organization"
	$RUN "docker exec -ti chef-server-ctl chef-server-ctl org-create default default"
fi

echo "GECOS CONTROL CENTER INSTALLED"
;;


CCUSER)
echo "CREATING CONTROL CENTER USER"

ADMIN_USER=$(whiptail --inputbox "Username" 8 78 superadmin --title "Creating Control Center User" 3>&1 1>&2 2>&3)
[ -z "$ADMIN_USER" ] && exit 1

VALID=0
[[ "$ADMIN_USER" =~ ^([a-zA-Z0-9]+)$ ]] && VALID=1
if [ $VALID -eq 0 ]
then
    echo "ERROR: The username must be composed only by letters and numbers"
    exit 1
fi

ADMIN_EMAIL=$(whiptail --inputbox "E-Mail Address" 8 78 superadmin@test.com --title "Creating Control Center User" 3>&1 1>&2 2>&3)
[ -z "$ADMIN_EMAIL" ] && exit 1

VALID=0
[[ "$ADMIN_EMAIL" =~ ^[a-zA-Z0-9._~-]+@[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]] && VALID=1
if [ $VALID -eq 0 ]
then
    echo "ERROR: The email must be valid"
    exit 1
fi


#docker exec -ti web pmanage gecoscc.ini create_adminuser --username $ADMIN_USER --email $ADMIN_EMAIL --is-superuser

opscode_chef_running_check

$RUN "docker exec -ti web pmanage gecoscc.ini create_chef_administrator -u $ADMIN_USER -e $ADMIN_EMAIL -a pivotal -s -k /etc/opscode/pivotal.pem  -n"


echo "Please, remember the GCC password. You will need it to login into Control Center"

echo "SET AS ADMIN USER"

# Patching chef-server-ctl configuration because the configurations and credentials aren't
# properly managed :(
$RUN "docker exec -ti chef-server-ctl cp /bin/chef-server-ctl /bin/chef-server-ctl-gecos"
$RUN "docker exec -ti chef-server-ctl sed -i 's/export CHEF_SECRETS_DATA/#export CHEF_SECRETS_DATA/g' /bin/chef-server-ctl-gecos"
rm /data/chef/opscode/private-chef-secrets.json
$RUN "docker exec -ti chef-server-ctl cp /hab/svc/chef-server-ctl/config/hab-secrets-config.json /etc/opscode/private-chef-secrets.json"

BIFROST_SUID=`$RUN "docker exec -ti chef-server-ctl chef-server-ctl-gecos show-secret oc_bifrost superuser_id"`
BIFROST_SUID=`echo -n $BIFROST_SUID | sed "s/\r//"`

ERCHEF_DB_PWD=`$RUN "docker exec -it oc_erchef cat /hab/svc/oc_erchef/config/sys.config" | grep db_pass`
ERCHEF_DB_PWD=`echo -n $ERCHEF_DB_PWD | awk '{print $2}' | sed 's/"//g' | sed 's/}//g'  | sed 's/,//g'`
ERCHEF_DB_USER=`$RUN "docker exec -it oc_erchef cat /hab/svc/oc_erchef/config/sys.config" | grep db_user`
ERCHEF_DB_USER=`echo -n $ERCHEF_DB_USER | awk '{print $2}' | sed 's/"//g' | sed 's/}//g'  | sed 's/,//g'`
ERCHEF_DB_USER=`echo -n $ERCHEF_DB_USER | sed "s/\r//"`


cat >/data/chef/opscode/chef-server-running.json <<EOL
{
  "private_chef": {
    "opscode-erchef": {
      "enable": true,
      "sql_user": "$ERCHEF_DB_USER"
    },
    "postgresql": {
      "version": "9.2",
      "vip": "postgresql",
      "port": 5432
    },
    "oc_bifrost": {
      "vip": "oc_bifrost",
      "port": 9463,
      "superuser_id": "$BIFROST_SUID"
    }
  }
}
EOL

ERCHEF_PASSWORD=`$RUN "docker exec -ti chef-server-ctl chef-server-ctl-gecos show-secret opscode_erchef sql_password"`
ERCHEF_PASSWORD=`echo -n $ERCHEF_PASSWORD | sed "s/\r//"`

if [ $ERCHEF_PASSWORD != $ERCHEF_DB_PWD ]
then
    echo "Fix Opscode Chef service password"
    sed -i "s/$ERCHEF_PASSWORD/$ERCHEF_DB_PWD/g" /data/chef/opscode/private-chef-secrets.json
fi

$RUN "docker exec -ti chef-server-ctl chef-server-ctl-gecos grant-server-admin-permissions $ADMIN_USER"


echo "CHEF USER CREATED!"

;;


PRINTERS)
	opscode_chef_running_check
    echo "LOADING PRINTERS CATALOG"
    $RUN "docker exec -ti web pmanage gecoscc.ini update_printers"
;;
PACKAGES)
	opscode_chef_running_check
    echo "LOADING PACKAGES CATALOG"
    $RUN "docker exec -ti web pmanage gecoscc.ini synchronize_repositories"
;;



POLICIES)
echo "INSTALLING NEW POLICIES"

opscode_chef_running_check

echo "Download dependent cookbooks"

$RUN "docker exec -ti web rm -rf $COOKBOOKSDIR"
$RUN "docker exec -ti web mkdir -p $COOKBOOKSDIR"

download_cookbook chef-client 4.3.1
download_cookbook apt 2.8.2
download_cookbook windows 1.38.2
download_cookbook chef_handler 1.2.0
download_cookbook logrotate 1.9.2
download_cookbook cron 1.7.0
download_cookbook compat_resource 12.19.1


echo "Downloading GECOS policies"
$RUN "docker exec -ti web wget $GECOSCC_POLICIES_URL -O /tmp/policies.zip  -o /dev/null"
$RUN "docker exec -ti web wget $GECOSCC_OHAI_URL -O /tmp/ohai.zip  -o /dev/null"
$RUN "docker exec -ti web unzip -o /tmp/policies.zip -d $COOKBOOKSDIR"
$RUN "docker exec -ti web mv $COOKBOOKSDIR/gecos-workstation-management-cookbook-$GECOS_WS_MGMT_VER $COOKBOOKSDIR/gecos_ws_mgmt"
$RUN "docker exec -ti web unzip -o /tmp/ohai.zip -d $COOKBOOKSDIR"
$RUN "docker exec -ti web mv $COOKBOOKSDIR/gecos-workstation-ohai-cookbook-$GECOS_OHAI_VER $COOKBOOKSDIR/ohai-gecos"


echo "Uploading policies to CHEF"
$RUN "docker exec -ti web knife ssl fetch"
$RUN "docker exec -ti web knife cookbook upload -a"


echo "Uploading policies to Control Center"
$RUN "docker exec -ti web pmanage gecoscc.ini import_policies -a pivotal -k /etc/opscode/pivotal.pem"
echo "Uploading Broadband Service Providers"
$RUN "docker exec -ti web pmanage gecoscc.ini mobile_broadband_providers -a pivotal -k /etc/opscode/pivotal.pem"

;;



esac



