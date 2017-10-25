#!/bin/bash

PATH="/bin:/usr/bin:/sbin:/usr/sbin"
LANG="C"
DATE=`date +%Y%m%d%H%M`
GCCDIR="/opt/gecosccui-2.2.0"
GCCINI="$GCCDIR/gecoscc.ini"
GCCVER="2.2.0"
CHEFPK="https://packages.chef.io/files/stable/chef/13.5.3/el/6/chef-13.5.3-1.el6.x86_64.rpm"
CHEFCL="chef-13.5.3-1.el6.x86_64"
NGINXC="/opt/nginx/etc/sites-enabled/gecoscc.conf"

function processGecosccini() {
    echo -n "backing up $GCCINI on $GCCINI-$DATE.backup... "
    cp -f $GCCINI $GCCINI-$DATE.backup
    echo 'done.'

    if [ `grep -c "http://forja.guadalinex.org/webs/gecos/doc/v2/doku.php" $GCCINI` -eq '1' ] ; then
        echo -n "found wrong help URL --> changing... " && \
        sed -i 's|^help_manual_url = http://forja.guadalinex.org/webs/gecos/doc/v2/doku.php|help_manual_url = https://github.com/gecos-team/gecos-doc/wiki/Politicas:|' $GCCINI && \
        echo 'done.'
    fi

    if [ `grep -c "^worker_class = gevent" $GCCINI` -eq '1' ] ; then
        echo -n "found wrong gevent definition --> changing... " && \
        sed -i 's/^worker_class = gevent/worker_class = gecoscc.socks.GecosGeventSocketIOWorker/' $GCCINI && \
        echo 'done.'
    fi

    if [ `grep -c "v2.gecos.guadalinex.org/gems" $GCCINI` -eq '1' ] ; then
        echo -n "found wrong gems repository --> changing... " && \
        sed -i 's|^firstboot_api.gem_repo = http://v2.gecos.guadalinex.org/gems|firstboot_api.gem_repo = http://v3.gecos.guadalinex.org/gems|' $GCCINI && \
        echo 'done.'
    fi

    if [ `grep -c "^timeout = 600" $GCCINI` -eq '1' ] ; then
        echo -n "found wrong timeout --> changing... " && \
        sed -i 's/^timeout = 600/timeout = 1800/' $GCCINI && \
        echo 'done.'
    fi

    if [ `grep -c "http://v3.gecos.guadalinex.org/gecos/" $GCCINI` -eq '0' ] ; then
        echo -n "found no Guadalinex v3 repos --> changing... " && \
        sed -i 's|"http://v2.gecos.guadalinex.org/gecos/",|"http://v2.gecos.guadalinex.org/gecos/", "http://v3.gecos.guadalinex.org/gecos/",|' $GCCINI && \
        sed -i 's|"http://v2.gecos.guadalinex.org/ubuntu/",|"http://v2.gecos.guadalinex.org/ubuntu/", "http://v3.gecos.guadalinex.org/ubuntu/",|' $GCCINI && \
        sed -i 's|"http://v2.gecos.guadalinex.org/mint/"|"http://v2.gecos.guadalinex.org/mint/", "http://v3.gecos.guadalinex.org/mint/"|' $GCCINI && \
        echo 'done.'
    fi

    if [ `grep -c "GECOS_VERSION" $GCCINI` -gt '0' ] ; then
        echo -n "found \$GECOS_VERSION variable --> changing... " && \
        sed -i "s/\${GECOS_VERSION}/$GCCVER/g" $GCCINI && \
        echo 'done.'
    fi
}

function processNginxConf() {
    if [ `grep -c proxy_http_version $NGINXC` -eq '0' ] ; then
        echo -n "nginx has no proxy_http_version definition --> changing... " && \
        sed -i '/proxy_pass http:\/\/@app;/a\\n      proxy_http_version 1.1;' $NGINXC
        echo 'done.'
    fi

    if [ `grep -c 'listen 80;' $NGINXC` -eq '0' ] ; then
        echo -n "nginx has no port 80 redirection --> changing... " && \
        echo -e "server {\n      listen 80;\n      return 301 https://\$host:443\$request_uri;\n}" >> $NGINXC
        echo 'done.'
    fi
    /etc/init.d/nginx restart
}

function updatePackagesLists() {
    if [ -x $GCCDIR/bin/pmanage ] ; then
        echo 'upgrading lists of packages...'
        [ -f /opt/rh/python27/enable ] && source /opt/rh/python27/enable
        [ -f $GCCDIR/bin/activate ]    && source $GCCDIR/bin/activate
        $GCCDIR/bin/pmanage $GCCINI synchronize_repositories
        echo 'done.'
    else
        echo "WARNING: packages list upgrade hasn't been done because there is no pmanage executable"
    fi
}

if [ ! $(id -u) = 0 ]; then
    echo 'ERROR: you must be root to run this script'
    exit 1
fi

if [ ! -f $GCCINI ] ; then
    echo "ERROR: $GCCINI not found"
    echo 'Is this a real GECOSCC server?'
    exit 2
else
    processGecosccini
fi

if [ ! -f $NGINXC ] ; then
    echo "ERROR: $NGINXC not found"
    exit 3
else
    processNginxConf
fi

if [ x`rpm -qa chef` != x$CHEFCL ] ; then
    echo "chef package not found, installing version 13.5.3 --> installing... " && \
    rpm -Uvh $CHEFPK && \
    echo 'done.'
fi

exit 0
