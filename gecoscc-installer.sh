#!/bin/bash

# GECOS Control Center Installer
# Download it from http://bit.ly/gecoscc-installer

# Authors: 
#   Alfonso de Cala <alfonso.cala@juntadeandalucia.es>
#
# Copyright 2016, Junta de Andalucia
# http://www.juntadeandalucia.es/
#
# Released under EUPL License V 1.1
# http://www.osor.eu/eupl

set -u
set -e

export ORGANIZATION="Your Organization"
export ADMIN_USER_NAME='superuser'
export ADMIN_EMAIL="gecos@guadalinex.org"

export GECOS_CC_SERVER_IP="127.0.0.1"
export CHEF_SERVER_IP="127.0.0.1"
# Test values
export GECOS_CC_SERVER_IP="192.168.0.15"
export CHEF_SERVER_IP="192.168.0.15"



export MONGO_URL="mongodb://localhost:27017/gecoscc"

export CHEF_SERVER_VERSION="12.6.0"
export CHEF_SERVER_PACKAGE_URL="https://packages.chef.io/stable/el/6/chef-server-core-$CHEF_SERVER_VERSION-1.el6.x86_64.rpm"
export CHEF_CLIENT_PACKAGE_URL="https://packages.chef.io/stable/el/6/chef-$CHEF_SERVER_VERSION-1.el6.x86_64.rpm"
export CHEF_SERVER_URL="https://localhost/"
export CHEF_SUPERADMIN_USER=pivotal
export CHEF_SUPERADMIN_CERTIFICATE=/etc/opscode/pivotal.pem



export SUPERVISOR_USER_NAME=internal
export SUPERVISOR_PASSWORD=changeme

# WARNING: I set my own repositories for testing purposses!
export GECOSCC_VERSION='chef12_test'
export GECOSCC_POLICIES_URL="https://github.com/System25/gecos-workstation-management-cookbook/archive/gecosv3.zip"
export GECOSCC_OHAI_URL="https://github.com/System25/gecos-workstation-ohai-cookbook/archive/development.zip"
export GECOSCC_URL="https://github.com/System25/gecoscc-ui/archive/$GECOSCC_VERSION.tar.gz"

#TEMPLATES_URL="https://raw.githubusercontent.com/gecos-team/gecoscc-installer/master/templates/"
TEMPLATES_URL="https://raw.githubusercontent.com/System25/gecoscc-installer/chef_12/templates/"


export NGINX_VERSION='1.4.3'

export RUBY_GEMS_REPOSITORY_URL="https://rubygems.org"
export HELP_URL="http://forja.guadalinex.org/webs/gecos/doc/v2/doku.php"

# FUNCTIONS

# Download a template, replace vars and copy it to a defined destination
# PARAMETERS: Destination full path, origin url, permissions, -subst/-nosubst for environment vars substitution
function install_template {
    filename=$(basename "$1")
    curl "$TEMPLATES_URL/$2" > /tmp/$filename.tmp
    if [ "$4" == "-subst" ] 
        then
            lines="$(cat /tmp/$filename.tmp)"
            end_offset=${#lines}
            while [[ "${lines:0:$end_offset}" =~ (.*)(\$\{([a-zA-Z_][a-zA-Z_0-9]*)\})(.*) ]] ; do
                PRE="${BASH_REMATCH[1]}"
                POST="${BASH_REMATCH[4]}${lines:$end_offset:${#lines}}"
                VARNAME="${BASH_REMATCH[3]}"
                eval 'VARVAL="$'$VARNAME'"'
                lines="$PRE$VARVAL$POST"
                end_offset=${#PRE}
            done
            echo -n "${lines}" > $1
        else
            cp /tmp/$filename.tmp $1
    fi
    chmod $3 $1
}


function install_package {
    if ! rpm -q $1;then
        yum install -y $1
    fi
}

function fix_host_name {
    IP=$(hostname -I)
    echo $IP
    if  ! grep $IP /etc/hosts; then
        echo "#Added by GECOS Control Center Installer" >> /etc/hosts
        echo "$IP       $HOSTNAME" >> /etc/hosts
    fi
}

function download_cookbook {
    echo "Downloading $1-$2"
    curl -L https://supermarket.chef.io/cookbooks/$1/versions/$2/download > /tmp/$1.tgz
    cd /tmp/cookbooks/  
    tar xzf /tmp/$1.tgz
}



# START: MAIN MENU

OPTION=$(whiptail --title "GECOS Control Center Installation" --menu "Choose an option" 14 78 8 \
"CHEF" "Install Chef server" \
"MONGODB" "Install Mongo Database." \
"NGINX" "Install NGINX Web Server." \
"CC" "Install GECOS Control Center." \
"USER" "Create Control Center Superuser." \
"SET_SUPERUSER" "Set Control Center Superuser as Chef Superuser." \
"POLICIES" "Update Control Center Policies." \
"PRINTERS" "Update Printers Models Catalog" \
"PACKAGES" "Update Software Packages Catalog" 3>&1 1>&2 2>&3 )


case $OPTION in

    
CHEF)
    echo "INSTALLING CHEF SERVER"
    echo "Downloading package $CHEF_SERVER_PACKAGE_URL"
    curl -L "$CHEF_SERVER_PACKAGE_URL" > /tmp/chef-server.rpm
    echo "Installing package"
    rpm -Uvh /tmp/chef-server.rpm
    echo "Checking host name resolution"
    fix_host_name
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


MONGODB)
    echo "INSTALLING MONGODB SERVER"

# Add mongodb repository
cat > /etc/yum.repos.d/mongodb.repo <<EOF
[mongodb]
name=mongodb RPM Repository
baseurl=http://downloads-distro.mongodb.org/repo/redhat/os/x86_64
enabled=1
gpgcheck=0
sslverify=1
EOF

echo "Installing mongodb package"
install_package mongodb-org
echo "Configuring mongod start script"
install_template "/etc/init.d/mongod" mongod 755 -nosubst
chkconfig mongod on
# Current mongodb package has got an error in start script. Disabling next lines until it is solved
#echo "Starting mongod"
#service mongod start
echo "MONGODB INSTALLED"
;;


CC)
    echo "INSTALLING GECOS CONTROL CENTER"

if pgrep supervisord > /dev/null 2>&1
  then

OPTION=$(whiptail --title "GECOS Control Center Installation" --menu "A Control Center is already running. Should I stop it?" 14 78 6 \
"YES" "Stop current GECOS Control Center before reinstalling" \
"NO" "Return to main menu" 3>&1 1>&2 2>&3 )

  case $OPTION in
    
YES)
    echo "Stopping GECOS Control Center"
    /etc/init.d/supervisord stop
;;
NO)
# Rerun this installer
    exec "$0"
;;
  esac
fi


echo "Adding EPEL repository"
if ! rpm -q epel-release-6-8.noarch; then
    rpm -ivh http://dl.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-8.noarch.rpm
fi
echo "Installing python-devel and pip"
install_package python-devel 
install_package python-pip
echo "Creating a Python Virtual Environment in /opt/gecosccui-$GECOSCC_VERSION"
pip install virtualenv
cd /opt/
virtualenv gecosccui-$GECOSCC_VERSION
echo "Activating Python Virtual Environment"
cd /opt/gecosccui-$GECOSCC_VERSION
export PS1="GECOS>" 
source bin/activate
echo "Installing gevent"
pip install "https://pypi.python.org/packages/source/g/gevent/gevent-1.0.tar.gz" 
echo "Installing supervisor"
pip install supervisor
echo "Installing GECOS Control Center UI"
# Add --no-deps to speed up gecos-cc reinstallations and dependencies are already satisfied
pip install --upgrade --force-reinstall $GECOSCC_URL
echo "Configuring GECOS Control Center"
install_template "/opt/gecosccui-$GECOSCC_VERSION/gecoscc.ini" gecoscc.ini 644 -subst
echo "Configuring supervisord"
install_template "/etc/init.d/supervisord" supervisord 755 -subst
install_template "/opt/gecosccui-$GECOSCC_VERSION/supervisord.conf" supervisord.conf 644 -subst
mkdir -p /opt/gecosccui-$GECOSCC_VERSION/supervisor/run
mkdir -p /opt/gecosccui-$GECOSCC_VERSION/supervisor/log
chkconfig supervisord on
install_package redis
echo "GECOS CONTROL CENTER INSTALLED"
;;


NGINX)
    echo "INSTALLING NGINX WEB SERVER"

if [ ! -e /opt/nginx/bin/nginx ]
then
    echo "Installing some development packages"
    install_package gcc
    install_package pcre-devel
    install_package openssl-devel
    cd /tmp/ 
    curl -L "http://nginx.org/download/nginx-$NGINX_VERSION.tar.gz" > /tmp/nginx-$NGINX_VERSION.tar.gz
    tar xzf /tmp/nginx-$NGINX_VERSION.tar.gz
    cd /tmp/nginx-$NGINX_VERSION
    ./configure --prefix=/opt/nginx --conf-path=/opt/nginx/etc/nginx.conf --sbin-path=/opt/nginx/bin/nginx
    make && make install
fi
echo "Creating user nginx"
adduser nginx
echo "Configuring NGINX to serve GECOS Control Center"
install_template "/opt/nginx/etc/nginx.conf" nginx.conf 644 -nosubst
if [ ! -e /opt/nginx/etc/sites-available ]; then 
    mkdir /opt/nginx/etc/sites-available/
fi
if [ ! -e /opt/nginx/etc/sites-enabled ]; then 
    mkdir /opt/nginx/etc/sites-enabled/
fi
install_template "/opt/nginx/etc/sites-available/gecoscc.conf" nginx-gecoscc.conf 644 -subst
if [ ! -e /opt/nginx/etc/sites-enabled/gecoscc.conf ]; then 
    ln -s /opt/nginx/etc/sites-available/gecoscc.conf /opt/nginx/etc/sites-enabled/
fi
echo "Starting NGINX on boot"
install_template "/etc/init.d/nginx" nginx 755 -nosubst
chkconfig nginx on
echo "Opening port in Firewall"
lokkit -s http
echo "Starting nginx"
service nginx start
echo "NGINX SERVER INSTALLED"
;;


POLICIES)
    echo "INSTALLING NEW POLICIES"

echo "Installing required unzip package"
install_package unzip
echo "Installing chef client package"
yum localinstall $CHEF_CLIENT_PACKAGE_URL -y
echo "Uploading policies to CHEF"
echo "Downloading GECOS policies"
curl -L $GECOSCC_POLICIES_URL > /tmp/policies.zip
curl -L $GECOSCC_OHAI_URL > /tmp/ohai.zip
rm -rf /tmp/cookbooks
mkdir -p /tmp/cookbooks
cd /tmp/cookbooks
unzip -o /tmp/policies.zip
mv /tmp/cookbooks/gecos-workstation-management-cookbook-* /tmp/cookbooks/gecos_ws_mgmt
unzip -o /tmp/ohai.zip
mv /tmp/cookbooks/gecos-workstation-ohai-cookbook-* /tmp/cookbooks/ohai-gecos

echo "Downloading dependent cookbooks"
download_cookbook chef-client 4.3.1
download_cookbook apt 2.8.2
download_cookbook windows 1.38.2
download_cookbook chef_handler 1.2.0
download_cookbook logrotate 1.9.2
download_cookbook cron 1.7.0

cat > /tmp/knife.rb << EOF
log_level                :info
log_location             STDOUT
node_name                '$CHEF_SUPERADMIN_USER'
client_key               '$CHEF_SUPERADMIN_CERTIFICATE'
chef_server_url          '$CHEF_SERVER_URL'
syntax_check_cache_path  '/root/.chef/syntax_check_cache'
cookbook_path            '/tmp/cookbooks/'
EOF
# Using chef client knife instead of chef server embedded one. This one shows an json deep nesting error with our cookbook.
/usr/bin/knife ssl fetch -c /tmp/knife.rb
/usr/bin/knife cookbook upload -c /tmp/knife.rb -a


if [ -e /opt/gecosccui-$GECOSCC_VERSION/bin/pmanage ]; then
    echo "Uploading policies to Control Center"
    /opt/gecosccui-$GECOSCC_VERSION/bin/pmanage /opt/gecosccui-$GECOSCC_VERSION/gecoscc.ini import_policies -a $CHEF_SUPERADMIN_USER -k $CHEF_SUPERADMIN_CERTIFICATE
fi

;;


USER)
    echo "CREATING CONTROL CENTER SUPERUSER"
    if [ -e /opt/gecosccui-$GECOSCC_VERSION/bin/pmanage ]; then
        /opt/gecosccui-$GECOSCC_VERSION/bin/pmanage /opt/gecosccui-$GECOSCC_VERSION/gecoscc.ini create_chef_administrator -u $ADMIN_USER_NAME -e $ADMIN_EMAIL -a $CHEF_SUPERADMIN_USER -s -k $CHEF_SUPERADMIN_CERTIFICATE -n
        echo "Please, remember the GCC password. You will need it to login into Control Center"

    else
        echo "Control Center is not installed in this machine"
    fi
;;

SET_SUPERUSER)
    echo "SETTING THE CONTROL CENTER SUPERUSER AS A CHEF SUPERUSER"
    if [ -e /opt/opscode/bin/chef-server-ctl ]; then
        /opt/opscode/bin/chef-server-ctl grant-server-admin-permissions $ADMIN_USER_NAME
        echo "Now $ADMIN_USER_NAME can manage Chef users"

    else
        echo "Chef 12 server is not installed in this machine"
    fi
;;


PRINTERS)
    echo "LOADING PRINTERS CATALOG"
    /opt/gecosccui-$GECOSCC_VERSION/bin/pmanage /opt/gecosccui-$GECOSCC_VERSION/gecoscc.ini update_printers
;;
PACKAGES)
    echo "LOADING PACKAGES CATALOG"
    /opt/gecosccui-$GECOSCC_VERSION/bin/pmanage /opt/gecosccui-$GECOSCC_VERSION/gecoscc.ini synchronize_repositories
;;
esac



