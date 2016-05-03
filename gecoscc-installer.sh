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
export SERVER_IP="127.0.0.1"

export CHEF_SERVER_PACKAGE_URL="https://packages.chef.io/stable/el/6/chef-server-11.1.7-1.el6.x86_64.rpm"
export CHEF_USER_NAME='admin'
export CHEF_FIRST_NAME='Administrator'
export CHEF_LAST_NAME=''
export CHEF_EMAIL='gecos@guadalinex.org'
export CHEF_PASSWORD='gecos'
export CHEF_ADMIN_KEYFILE='/tmp/admin.pem'
export CHEF_ORGANIZATION_KEYFILE='/tmp/admin.pem'
export CHEF_URL="https://localhost/"

export GECOSCC_VERSION='2.1.10'

export NGINX_VERSION='1.4.3'

export MONGO_URL="mongodb://localhost:27017/gecoscc"

export RUBY_GEMS_REPOSITORY="http://rubygems.org"
export HELP_URL="http://forja.guadalinex.org/webs/gecos/doc/v2/doku.php"

TEMPLATES_URL="https://raw.githubusercontent.com/gecos-team/gecoscc-installer/master/templates/"

# FUNCTIONS

# Download a template, replace vars and copy it to a defined destination
# PARAMETERS: Destination full path, origin url 
function install_template {
    if [ ! -x /usr/bin/envsubst ]
        then
            yum install gettext
    fi
    filename=$(basename "$1")
    curl "$TEMPLATES_URL/$2" > /tmp/$filename
    if [ "$3" == "-subst" ] 
        then
            envsubst < /tmp/$filename > $1
        else
            cp /tmp/$filename $1
    fi
}


# START

OPTION=$(whiptail --title "GECOS CC Installation" --menu "Choose an option" 10 78 4 \
"CHEF" "Install Chef server" \
"MONGODB" "Install Mongo Database." \
"NGINX" "Install NGINX Web Server." \
"CC" "Install GECOS Control Center." \
"POLICIES" "Load New Policies." 3>&1 1>&2 2>&3 )


case $OPTION in


CHEF)
    echo "INSTALLING CHEF SERVER"

    echo "Downloading" $CHEF_SERVER_PACKAGE_URL
    curl -L "$CHEF_SERVER_PACKAGE_URL" > /tmp/chef-server.rpm
    echo "Installing"
    rpm -Uvh /tmp/chef-server.rpm
    echo "Configuring"
    chef-server-ctl reconfigure
#Change for Chef12:
#    chef-server-ctl user-create "$CHEF_USER_NAME" "$CHEF_FIRST_NAME" "$CHEF_LAST_NAME" "$CHEF_EMAIL" "$CHEF_PASSWORD" --filename "$CHEF_ADMIN_KEYFILE"
#    chef-server-ctl org-create short_name "$ORGANIZATION" --association_user "$CHEF_USER_NAME" --filename "$CHEF_ORGANIZATION_KEYFILE" 
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
yum install mongodb-org
echo "Starting mongodb on boot"
install_template "/etc/init.d/mongod" mongod -nosubst
chkconfig mongod on
;;


CC)
    echo "INSTALLING GECOS CONTROL CENTER"

echo "Creating Python virtual environment in /opt/gecosccui-$GECOSCC_VERSION"
pip install virtualenv
cd /opt/
virtualenv gecosccui-$GECOSCC_VERSION
echo "Activating virtualenv"
cd /opt/gecosccui-$GECOSCC_VERSION
export PS1="GECOS>" 
source bin/activate
echo "Installing gevent"
pip install "https://pypi.python.org/packages/source/g/gevent/gevent-1.0.tar.gz" 
echo "Installing supervisor"
pip install supervisor
echo "Installing GECOS Control Center UI"
pip install "https://github.com/gecos-team/gecoscc-ui/archive/$GECOSCC_VERSION.tar.gz"
echo "Configuring supervisord start script"
install_template "/etc/init.d/supervisord" supervisord -subst
install_template "/opt/gecoscc-$GECOSCC_VERSION/supervisor.conf" supervisor.conf -subst
install_template "/opt/gecoscc-$GECOSCC_VERSION/gecoscc.ini" gecoscc.ini -subst
;;


NGINX)
    echo "INSTALLING NGINX WEB SERVER"

yum install gcc pcre-devel openssl-devel
cd /tmp/ 
curl -L "http://nginx.org/download/nginx-$NGINX_VERSION.tar.gz" > /tmp/nginx-$NGINX_VERSION.tar.gz
tar xzf /tmp/nginx-$NGINX_VERSION.tar.gz
cd /tmp/nginx-$NGINX_VERSION
./configure --prefix=/opt/nginx --conf-path=/opt/nginx/etc/nginx.conf --sbin-path=/opt/nginx/bin/nginx
make && make install
echo "Configuring NGINX to serve GECOS Control Center"
mkdir /opt/nginx/etc/sites-available/
mkdir /opt/nginx/etc/sites-enabled/
install_template "/opt/nginx/etc/sites-available/gecoscc.conf" nginx.conf -subst
ln -s /opt/nginx/etc/sites-available/nginx.conf /opt/nginx/etc/sites-enabled/
echo "Starting NGINX on boot"
install_template "/etc/init.d/nginx" nginx -nosubst
chkconfig nginx on
;;


POLICIES)
    echo "Installing New Policies"

cat > /tmp/knife.rb << EOF
log_level                :info
log_location             STDOUT
node_name                'admin'
client_key               '/etc/chef-server/admin.pem'
validation_client_name   'chef-validator'
validation_key           '/etc/chef-server/chef-validator.pem'
chef_server_url          'https://localhost:443/'
syntax_check_cache_path  '/root/.chef/syntax_check_cache'
cookbook_path            '${LOCAL_CHEF_REPO}/cookbooks'
EOF
# upload all the cookbooks
knife cookbook upload -c /tmp/knife.rb -a

;;
esac

