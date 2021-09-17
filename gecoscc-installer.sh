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

# Minimum host:
#  - RHEL 7 or 8
#  - 1 CPU
#  - 1 GB RAM
#  - 20 GB HDD

# ---------------------------------------------------------------------------
# Please edit the following variables

# MongoDB database address
MONGODB_URL=mongodb://<your mongodb server>:27017/gecoscc

# Chef server URLs
# - The internal URL will be the address that the GECOS CC will use to
#   communicate with the Chef server.
# - The external URL will be the address that the Guadalinex GECOS based PCs
#   will use to communicate with the Chef server.
# (both addresses must point to the same server).
CHEF_SERVER_INTERNAL_URL=https://<your chef server>/
CHEF_SERVER_URL=https://<your chef server>/
CHEF_SERVER_VERSION="12.18.14" 

CHEF_SERVER_PIVOTAL_CERT_PATH=/path/to/your/pivotal.pem
CHEF_SERVER_WEBUI_CERT_PATH=/path/to/your/webui_priv.pem

# Redis databases
SOCKJS_REDIS_SERVER_URL=redis://<your redis server>:6379/0
SOCKJS_REDIS_OPTIONS='{}'
CELERY_REDIS_SERVER_URL=redis://<your redis server>:6379/1
CELERY_REDIS_TRANSPORT_OPTIONS=""

# Redis with sentinel example
#SOCKJS_REDIS_SERVER_URL="sentinel://:<password>@<your redis sentinel 1>:26379/0;sentinel://:<password>@<your redis sentinel 2>:26379/0"
#SOCKJS_REDIS_OPTIONS='{ "transport_options": { "master_name": "mymaster" } }'
#CELERY_REDIS_SERVER_URL="sentinel://:<password>@<your redis sentinel 1>:26379/1;sentinel://:<password>@<your redis sentinel 2>:26379/1"
#CELERY_REDIS_TRANSPORT_OPTIONS="master_name = mymaster"


# Supervisor credentials
SUPERVISOR_USER_NAME=internal
SUPERVISOR_PASSWORD=changeme

# Custom Nginx configuration path
# (you can leave this blank to use a generic Nginx configuration)
CUSTOM_NGINX_CONFIG=/data/minxingxconf

# ---------------------------------------------------------------------------


HOST_IP_ADDR=`ip addr | grep eth0 | grep inet | awk '{print $2}' | awk -F '/' '{ print $1}'`

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
COOKBOOKSDIR='/opt/gecosccui/.chef/cookbooks'
GCC_URL="https://codeload.github.com/gecos-team/gecoscc-installer/zip/development-docker"


GECOS_WS_MGMT_VER=0.11.4
GECOS_OHAI_VER=1.15.1

export GECOSCC_POLICIES_URL="https://github.com/gecos-team/gecos-workstation-management-cookbook/archive/$GECOS_WS_MGMT_VER.zip"
export GECOSCC_OHAI_URL="https://github.com/gecos-team/gecos-workstation-ohai-cookbook/archive/$GECOS_OHAI_VER.zip"


# -------------------------------- setup constants END -----------------------

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
            if [ $TotalRAM -lt "840936" ] ; then
                echo "The host machine needs at least 1 GB of RAM."
                echo "Please, check documentation for more information:"
                echo "https://github.com/gecos-team/gecoscc-installer/blob/master/README.md"
                echo "Aborting installation process."
                exit 2
            fi

        fi
    else
        echo "WARNING: Can't check the amount of RAM. Please ensure that this server has at least 1GB or RAM"
    
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

    # Open NginX port
    firewall-cmd --zone=public --add-port=80/tcp --permanent > /dev/null 2>&1

    # Open default GECOS CC ports (8010, 8011 and 9001)
    firewall-cmd --zone=public --add-port=8010/tcp --permanent > /dev/null 2>&1
    firewall-cmd --zone=public --add-port=8011/tcp --permanent > /dev/null 2>&1
    firewall-cmd --zone=public --add-port=9001/tcp --permanent > /dev/null 2>&1

    firewall-cmd --reload > /dev/null 2>&1
}

function mongodb_checking {
    # Check mongodb URL
    if [[ "$MONGODB_URL" == mongodb://* ]]
    then
        # Remove mongodb://
        ADDR="$MONGODB_URL"
        LEN=${#ADDR}
        ADDR=$(expr substr "$ADDR" 11 $LEN )

        # Remove the database name part (usualy "/gecoscc")
        if ! POS=$(expr index "$ADDR" "/" )
        then
            echo "The mongodb url must contain the database name."
            echo "Aborting installation process."
            exit 2
        fi

        POS=$(expr $POS - 1)
        ADDR=$(expr substr "$ADDR" 1 $POS )

        # Check if the address contains :PORT
        PORT=0
        if POS=$(expr index "$ADDR" ":" )
        then
            # Extract port from address
            LEN=${#ADDR}
            POS=$(expr $POS + 1)
            PORT=$(expr substr "$ADDR" $POS $LEN)
            POS=$(expr $POS - 2)
            ADDR=$(expr substr "$ADDR" 1 $POS )
        else
            # Use default port
            PORT=27017
        fi
        
        if ! nc -z $ADDR $PORT > /dev/null 2>&1
        then
            echo "Can't connect to mongodb on host $ADDR and port $PORT"
            echo "Aborting installation process."
            exit 2
        fi

    else
        echo "The mongodb url must start with mongodb://"
        echo "Aborting installation process."
        exit 2
    fi
}


function redis_checking {
    ADDR=$1

    # Check redis sentinel URL
    if [[ "$ADDR" == sentinel://* ]]
    then
        ADDRESSES=$(echo $ADDR | tr ";" "\n")
        for ADDR in $ADDRESSES
        do
            # Remove sentinel://
            LEN=${#ADDR}
            ADDR=$(expr substr "$ADDR" 12 $LEN )

            # Remove the database number part (usualy "/1")
            if ! POS=$(expr index "$ADDR" "/" )
            then
                echo "The redis url must contain the database number."
                echo "Aborting installation process."
                exit 2
            fi

            POS=$(expr $POS - 1)
            ADDR=$(expr substr "$ADDR" 1 $POS )

            # Check if the address contains @
            if POS=$(expr index "$ADDR" "@" )
            then
                # Remove the <user:password> from the address
                LEN=${#ADDR}
                POS=$(expr $POS + 1)
                ADDR=$(expr substr "$ADDR" $POS $LEN)
            fi

            # Check if the address contains :PORT
            if POS=$(expr index "$ADDR" ":" )
            then
                # Extract port from address
                LEN=${#ADDR}
                POS=$(expr $POS + 1)
                PORT=$(expr substr "$ADDR" $POS $LEN)
                POS=$(expr $POS - 2)
                ADDR=$(expr substr "$ADDR" 1 $POS )
            else
                # Use default port
                PORT=26379
            fi
        
            if ! nc -z $ADDR $PORT > /dev/null 2>&1
            then
                echo "Can't connect to redis sentinel on host $ADDR and port $PORT"
                echo "Aborting installation process."
                exit 2
            fi
        done

        # Return OK
        return 0
    fi

    # Check redis URL
    if [[ "$ADDR" == redis://* ]]
    then
        # Remove redis://
        LEN=${#ADDR}
        ADDR=$(expr substr "$ADDR" 9 $LEN )

        # Remove the database number part (usualy "/1")
        if ! POS=$(expr index "$ADDR" "/" )
        then
            echo "The redis url must contain the database number."
            echo "Aborting installation process."
            exit 2
        fi

        POS=$(expr $POS - 1)
        ADDR=$(expr substr "$ADDR" 1 $POS )

        # Check if the address contains :PORT
        if POS=$(expr index "$ADDR" ":" )
        then
            # Extract port from address
            LEN=${#ADDR}
            POS=$(expr $POS + 1)
            PORT=$(expr substr "$ADDR" $POS $LEN)
            POS=$(expr $POS - 2)
            ADDR=$(expr substr "$ADDR" 1 $POS )
        else
            # Use default port
            PORT=6379
        fi
        
        if ! nc -z $ADDR $PORT > /dev/null 2>&1
        then
            echo "Can't connect to redis on host $ADDR and port $PORT"
            echo "Aborting installation process."
            exit 2
        fi


    else
        echo "The redis url must start with redis://"
        echo "Aborting installation process."
        exit 2
    fi
}


function opscode_chef_running_check {
    # Check that there is an running Opscode chef installation
    CHEFADDR=$1

    # Chef if the server is online
    ONLINE=0
    curl -s -k $CHEFADDR  > /dev/null && ONLINE=1

    if [ $ONLINE -eq 0 ]
    then
        echo "Can't connect to the Chef server: $CHEFADDR"
        echo "Aborting installation process."
        exit 2
    fi

    # Wait until status is "pong"
    export PYTHONIOENCODING=utf8
    cat >/tmp/check_chef.py <<EOL
import sys, json;

try:
    print(json.load(sys.stdin)['status'])
except:
    print("error")

EOL

    STATUS=`curl -s -k $CHEFADDR/_status | $PYTHON /tmp/check_chef.py`
    if [ $STATUS != 'pong' ]
    then
        echo "Bad Chef server status: $CHEFADDR - $STATUS"
        echo "Aborting installation process."
        exit 2
    fi

    # Check that the pivotal certificate exists
    if [ ! -f $CHEF_SERVER_PIVOTAL_CERT_PATH ]
    then
        echo "Can't find the pivotal.pem file: $CHEF_SERVER_PIVOTAL_CERT_PATH"
        echo "Aborting installation process."
        exit 2
    fi

    if ! openssl rsa -check -noout -in $CHEF_SERVER_PIVOTAL_CERT_PATH > /dev/null 2>&1
    then
        echo "Invalid certificate file: $CHEF_SERVER_PIVOTAL_CERT_PATH"
        echo "Aborting installation process."
        exit 2
    fi


    # Check that the webui certificate exists
    if [ ! -f $CHEF_SERVER_WEBUI_CERT_PATH ]
    then
        echo "Can't find the pivotal.pem file: $CHEF_SERVER_WEBUI_CERT_PATH"
        echo "Aborting installation process."
        exit 2
    fi

    if ! openssl rsa -check -noout -in $CHEF_SERVER_WEBUI_CERT_PATH > /dev/null 2>&1
    then
        echo "Invalid certificate file: $CHEF_SERVER_WEBUI_CERT_PATH"
        echo "Aborting installation process."
        exit 2
    fi

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

# Opscode chef server checking
opscode_chef_running_check $CHEF_SERVER_INTERNAL_URL
opscode_chef_running_check $CHEF_SERVER_URL

# Checking if can connect to MongoDB server
mongodb_checking

# Check redis databases
redis_checking $SOCKJS_REDIS_SERVER_URL
redis_checking $CELERY_REDIS_SERVER_URL


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

# Get the docker image ID
IMAGEID=$($RUN "docker image list -q $DOCKERIMGNAME | tr \"\\n\" ' '")
if POS=$(expr index "$IMAGEID" ":" )
then
    # Remove ":whatever"
    POS=$(expr $POS - 1)
    IMAGEID=$(expr substr "$IMAGEID" 1 $POS )
fi

if [ "$IMAGEID" != "" ]
then
    # Remove all containers
    CONTAINERS=$($RUN "docker ps -a -q -f ancestor=$IMAGEID | tr \"\\n\" ' '")
    if [ "$CONTAINERS" != "" ]
    then
        $RUN "docker rm $CONTAINERS"
    fi

    # Remove the image
    $RUN "docker rmi --force $IMAGEID"
fi

# Get the docker image ID
IMAGEID=$($RUN "docker image list -q gecos_nginx | tr \"\\n\" ' '")
if POS=$(expr index "$IMAGEID" ":" )
then
    # Remove ":whatever"
    POS=$(expr $POS - 1)
    IMAGEID=$(expr substr "$IMAGEID" 1 $POS )
fi

if [ "$IMAGEID" != "" ]
then
    # Remove all containers
    CONTAINERS=$($RUN "docker ps -a -q -f ancestor=$IMAGEID | tr \"\\n\" ' '")
    if [ "$CONTAINERS" != "" ]
    then
        $RUN "docker rm $CONTAINERS"
    fi

    # Remove the image
    $RUN "docker rmi --force $IMAGEID"
fi


# Remove all volumes
GCC_VOLUMES="gecos-cc_chef-config-data gecos-cc_data_volume gecos-cc_conf_volume gecos-cc_log_volume"
GCC_VOLUMES=$(echo $GCC_VOLUMES | tr ' ' "\n")
for VOLUME in $GCC_VOLUMES
do
    VOLUMES=$($RUN "docker volume list -q -f name=$VOLUME | tr \"\\n\" ' '")
    if [ "$VOLUMES" != "" ]
    then
        $RUN "docker volume rm $VOLUMES"
    fi
done

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
mkdir -p /data/gecoscc
mkdir -p /data/chef/config
mkdir -p /data/nginx

if [ ! -f /data/chef/config/pivotal.pem ]
then 
    cp $CHEF_SERVER_PIVOTAL_CERT_PATH /data/chef/config/pivotal.pem
fi

if [ ! -f /data/chef/config/webui_priv.pem ]
then 
    cp $CHEF_SERVER_WEBUI_CERT_PATH /data/chef/config/webui_priv.pem
fi

chmod 644 /data/chef/config/pivotal.pem
chmod 644 /data/chef/config/webui_priv.pem

if [ ! -f /data/conf/.chef/knife.rb ]
then 
    cp $BASE/templates/knife.rb /data/conf/.chef/knife.rb
    sed -i "s|CHEF_SERVER|$CHEF_SERVER_URL|" /data/conf/.chef/knife.rb
    chmod 644 /data/conf/.chef/knife.rb
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

if [ "$CUSTOM_NGINX_CONFIG" == "" ]
then
    # Use a basic Nginx configuration

    if [ ! -f /data/nginx/gecoscc.conf ]
    then 
        cp $BASE/nginx/gecoscc.conf /data/nginx/gecoscc.conf
    fi

else
    # Apply a custom Nginx configuration directory
    sed -i "s|'/data/nginx/'|'$CUSTOM_NGINX_CONFIG'|" $BASE/docker-compose.yml
fi


chown -R $RUNUSER:$RUNGROUP $BASE
chown -R $RUNUSER:$RUNGROUP /data/conf/.chef



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

# Start the service
/bin/systemctl start gecoscc.service


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


$RUN "docker exec -ti web pmanage gecoscc.ini create_chef_administrator -u $ADMIN_USER -e $ADMIN_EMAIL -a pivotal -s -k /etc/opscode/pivotal.pem  -n"


echo "Please, remember the GCC password. You will need it to login into Control Center"

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



