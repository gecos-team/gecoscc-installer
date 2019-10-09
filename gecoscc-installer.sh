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
#  - RHEL 7
#  - 4 CPU
#  - 16 GB RAM
#  - 64 GB HDD

# Minimum host:
#  - RHEL 7
#  - 1 CPU
#  - 6 GB RAM
#  - 20 GB HDD

HOST_IP_ADDR=`ip addr | grep eth0 | grep inet | awk '{print $2}' | awk -F '/' '{ print $1}'`

HOSTNAME=$(hostname)
if [ "$HOSTNAME" == "localhost.localdomain" ]
then
	# Hostname is not properly configured --> use public IP
	HOSTNAME=$HOST_IP_ADDR

fi

# -------------------------------- setup constants START ---------------------
CHEF_SERVER_URL=https://$HOSTNAME
CHEF_SERVER_VERSION="12.18.14" 
RUNUSER=gecos
RUNGROUP=gecos
GCC_URL='https://codeload.github.com/gecos-team/gecoscc-installer/zip/development-docker'
COOKBOOKSDIR='/opt/gecosccui/.chef/cookbooks'


GECOS_WS_MGMT_VER=0.9.0
GECOS_OHAI_VER=1.12.0

export GECOSCC_POLICIES_URL="https://github.com/gecos-team/gecos-workstation-management-cookbook/archive/$GECOS_WS_MGMT_VER.zip"
export GECOSCC_OHAI_URL="https://github.com/gecos-team/gecos-workstation-ohai-cookbook/archive/$GECOS_OHAI_VER.zip"


# -------------------------------- setup constants END -----------------------

RUN="runuser -l $RUNUSER -c"

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
    $RUN "docker exec -ti web curl -L https://supermarket.chef.io/cookbooks/$1/versions/$2/download -o /tmp/$1-$2.tar.gz"
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

    if [ "$OS_VER" -ne 7 ]
	then
        echo "Operating System not supported: wrong version."
        echo "Please, check documentation for more information:"
        echo "https://github.com/gecos-team/gecoscc-installer/blob/master/README.md"
        echo "Aborting installation process."
        exit 2
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
		yum -y install docker
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
	DOCKERGROUP=`cat /etc/group | grep docker |  awk -F':' '{ print $1 }'`
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

	# Open port 80 (GECOS CC Nginx http port)
    firewall-cmd --zone=public --add-port=80/tcp --permanent > /dev/null 2>&1

    # Enable masquerade for port forward
	firewall-cmd --permanent --zone=public --add-masquerade > /dev/null 2>&1

	firewall-cmd --reload
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

# Stop the service
/bin/systemctl stop gecoscc.service

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
rm /etc/systemd/system/gecoscc.service
/bin/systemctl daemon-reload

# Remove the user
userdel $RUNUSER

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
    adduser $RUNUSER
fi

# Check if the user belongs to docker o dockerroot group
DOCKERGROUP=`cat /etc/group | grep docker |  awk -F':' '{ print $1 }'`
BELONGS=`groups $RUNUSER | grep $DOCKERGROUP | wc -l`
if [ $BELONGS -ne  1 ]
then
    usermod -aG $DOCKERGROUP $RUNUSER
fi


BASE="/home/$RUNUSER/"

# Download the installer
curl $GCC_URL -o "$BASE/gecoscc-installer.zip"
cd $BASE
DIRECTORY=`unzip gecoscc-installer.zip | grep creating | head -1 | awk -F ' ' '{print $2}' |  sed -r 's|/||g'`
rm gecoscc-installer.zip

if [ $DIRECTORY != 'gecoscc-installer' ]
then
	# Rename the unzipped directory
	mv $DIRECTORY gecoscc-installer
fi

BASE="/home/$RUNUSER/gecoscc-installer"


# Check if directories for docker volumes exists
mkdir -p /data/logs
mkdir -p /data/db
mkdir -p /data/gecoscc
mkdir -p /data/chef/psql
mkdir -p /data/chef/elasticsearch
mkdir -p /data/chef/erchef
mkdir -p /data/chef/nginx
mkdir -p /data/chef/config
mkdir -p /data/chef/opscode
if [ ! -L /data/chef/opscode/private-chef-secrets.json ]
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



cp $BASE/CTL_SECRET /data/chef/CTL_SECRET


chown -R $RUNUSER:$RUNGROUP $BASE



# Prepare the RUN script
cat >/etc/systemd/system/gecoscc.service <<EOL
[Unit]
Description=GECOS Control Center
Requires=docker.service
After=docker.service

[Service]
Environment=CHEF_SERVER_VERSION=$CHEF_SERVER_VERSION
Environment=CHEF_SERVER_URL=$CHEF_SERVER_URL
User=$RUNUSER
Group=$RUNGROUP
PermissionsStartOnly=true
WorkingDirectory=$BASE
# Forward 443 port to 8443 (Chef Server Nginx https port) before start
ExecStartPre=/usr/bin/firewall-cmd --zone=public --add-forward-port=port=443:proto=tcp:toport=8443
ExecStartPre=/usr/bin/firewall-cmd --direct --add-rule ipv4 nat OUTPUT 0 -p tcp -o lo --dport 443 -j REDIRECT --to-ports 8443

ExecStart=/usr/local/bin/docker-compose up
ExecStop=/usr/local/bin/docker-compose down

# Remove port forwarding after stop
ExecStopPost=/usr/bin/firewall-cmd --zone=public --remove-forward-port=port=443:proto=tcp:toport=8443
ExecStopPost=/usr/bin/firewall-cmd --direct --remove-rule ipv4 nat OUTPUT 0 -p tcp -o lo --dport 443 -j REDIRECT --to-ports 8443
TimeoutStartSec=0
Restart=on-failure
StartLimitIntervalSec=60
StartLimitBurst=3

[Install]
WantedBy=multi-user.target 
EOL

/bin/systemctl daemon-reload

# Pull the images
$RUN "cd $BASE; CHEF_SERVER_VERSION='$CHEF_SERVER_VERSION' CHEF_SERVER_URL='$CHEF_SERVER_URL' /usr/local/bin/docker-compose pull"

# Build the images
$RUN "cd $BASE; CHEF_SERVER_VERSION='$CHEF_SERVER_VERSION' CHEF_SERVER_URL='$CHEF_SERVER_URL' /usr/local/bin/docker-compose build"

rm -f /data/chef/config/pivotal.pem

# Start the service
/bin/systemctl start gecoscc.service


# Wait until the servers are online
ONLINE=0
while [ $ONLINE -eq 0 ]
do
	sleep 3
	echo "Waiting for gecoscc server to be online..."
	curl -s -k https://localhost  > /dev/null && ONLINE=1
done

# Wait until the pivotal certificate exists
while [ ! -f /data/chef/config/pivotal.pem ]
do
	sleep 3
	echo "Waiting for pivotal certificate to exists..."
done

sleep 5

# Check if the "default" organization exists
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

$RUN "docker exec -ti web pmanage gecoscc.ini create_chef_administrator -u $ADMIN_USER -e $ADMIN_EMAIL -a pivotal -s -k /etc/opscode/pivotal.pem  -n"


echo "Please, remember the GCC password. You will need it to login into Control Center"

echo "SET AS ADMIN USER"

# Patching chef-server-ctl configuration because the configurations and credentials aren't
# properly managed :(
$RUN "docker exec -ti chef-server-ctl cp /bin/chef-server-ctl /bin/chef-server-ctl-gecos"
$RUN "docker exec -ti chef-server-ctl sed -i 's/export CHEF_SECRETS_DATA/#export CHEF_SECRETS_DATA/g' /bin/chef-server-ctl-gecos"

BIFROST_SUID=`$RUN "docker exec -ti chef-server-ctl chef-server-ctl-gecos show-secret oc_bifrost superuser_id"`
BIFROST_SUID=`echo -n $BIFROST_SUID | sed "s/\r//"`
echo "Bifrost superuser_id='$BIFROST_SUID'"

cat >/data/chef/opscode/chef-server-running.json <<EOL
{
  "private_chef": {
    "opscode-erchef": {
      "enable": true,
      "sql_user": "hab"
    },
    "postgresql": {
      "version": "9.2",
      "vip": "127.0.0.1",
      "port": 5432
    },
    "oc_bifrost": {
      "vip": "127.0.0.1",
      "port": 9463,
      "superuser_id": "$BIFROST_SUID"
    }
  }
}
EOL

$RUN "docker exec -ti chef-server-ctl chef-server-ctl-gecos grant-server-admin-permissions $ADMIN_USER"


echo "CHEF USER CREATED!"

;;


PRINTERS)
    echo "LOADING PRINTERS CATALOG"
    $RUN "docker exec -ti web pmanage gecoscc.ini update_printers"
;;
PACKAGES)
    echo "LOADING PACKAGES CATALOG"
    $RUN "docker exec -ti web pmanage gecoscc.ini synchronize_repositories"
;;



POLICIES)
echo "INSTALLING NEW POLICIES"

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
$RUN "docker exec -ti web curl -L $GECOSCC_POLICIES_URL -o /tmp/policies.zip"
$RUN "docker exec -ti web curl -L $GECOSCC_OHAI_URL -o /tmp/ohai.zip"
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



