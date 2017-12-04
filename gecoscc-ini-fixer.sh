#!/bin/bash

PATH="/bin:/usr/bin:/sbin:/usr/sbin"
LANG="C"
DATE=`date +%Y%m%d%H%M%S`
PWD=`pwd`
SUPERV="/etc/init.d/supervisord"
GCC221="https://github.com/gecos-team/gecoscc-ui/archive/2.2.1.tar.gz"
NGINXC="/opt/nginx/etc/sites-enabled/gecoscc.conf"
CHEFPK="https://packages.chef.io/files/stable/chef/13.5.3/el/6/chef-13.5.3-1.el6.x86_64.rpm"
CHEFCL="chef-13.5.3-1.el6.x86_64"

function updateGECOSCC() {
    echo "found outdated version of GECOSCC --> updating... "

    $SUPERV stop

    local OLDVER="2.2.0"
    local NEWVER="2.2.1"

    cp -r /opt/gecosccui-$OLDVER /opt/gecosccui-$NEWVER
    sed -i 's|/opt/gecosccui-2.2.0|/opt/gecosccui-2.2.1|g' $SUPERV
    sed -i 's|/opt/gecosccui-2.2.0|/opt/gecosccui-2.2.1|g' /opt/gecosccui-$NEWVER/bin/*
    sed -i 's|/opt/gecosccui-2.2.0|/opt/gecosccui-2.2.1|g' /opt/gecosccui-$NEWVER/gecoscc.ini
    sed -i 's|/opt/gecosccui-2.2.0|/opt/gecosccui-2.2.1|g' /opt/gecosccui-$NEWVER/supervisord.conf

    cd /tmp
    curl -s -L -O $GCC221
    mkdir -p /tmp/$DATE
    tar xfz 2.2.1.tar.gz -C /tmp/$DATE

    source /opt/rh/python27/enable 
    source /opt/gecosccui-$NEWVER/bin/activate

    cd /tmp/$DATE/gecoscc-ui-2.2.1
    python setup.py build
    python setup.py install
    easy_install dist/gecoscc-2.2.1-py2.7.egg 
    cd /opt/gecosccui-$NEWVER/lib/python2.7/site-packages/gecoscc-2.2.1-py2.7.egg
    cp -r * /opt/gecosccui-$NEWVER/lib/python2.7/site-packages/
    chown -R gecoscc:gecoscc /opt/gecosccui-$NEWVER/sessions 
    chown -R gecoscc:gecoscc /opt/gecosccui-$NEWVER/supervisor
    chown -R gecoscc:gecoscc /opt/gecosccui-$NEWVER/supervisord.conf

    $SUPERV start

    echo 'done.'
}

function processGecosccini() {
    local CHANGED='no'

    echo -n "backing up $GCCINI on $GCCINI-$DATE... "
    cp -f $GCCINI $GCCINI-$DATE
    echo 'done.'

    if [ `grep -c "http://forja.guadalinex.org/webs/gecos/doc/v2/doku.php" $GCCINI` -eq '1' ] ; then
        echo -n "found wrong help URL --> changing... " && \
        sed -i 's|^help_manual_url = http://forja.guadalinex.org/webs/gecos/doc/v2/doku.php|help_manual_url = https://github.com/gecos-team/gecos-doc/wiki/Politicas:|' $GCCINI && \
        CHANGED='yes' && \
        echo 'done.'
    fi

    if [ `grep -c "^worker_class = gevent" $GCCINI` -eq '1' ] ; then
        echo -n "found wrong gevent definition --> changing... " && \
        sed -i 's/^worker_class = gevent/worker_class = gecoscc.socks.GecosGeventSocketIOWorker/' $GCCINI && \
        CHANGED='yes' && \
        echo 'done.'
    fi

    if [ `grep -c "v2.gecos.guadalinex.org/gems" $GCCINI` -eq '1' ] ; then
        echo -n "found wrong gems repository --> changing... " && \
        sed -i 's|^firstboot_api.gem_repo = http://v2.gecos.guadalinex.org/gems|firstboot_api.gem_repo = http://v3.gecos.guadalinex.org/gems|' $GCCINI && \
        CHANGED='yes' && \
        echo 'done.'
    fi

    if [ `grep -c "^timeout = 600" $GCCINI` -eq '1' ] ; then
        echo -n "found wrong timeout --> changing... " && \
        sed -i 's/^timeout = 600/timeout = 1800/' $GCCINI && \
        CHANGED='yes' && \
        echo 'done.'
    fi

    if [ `grep -c "http://v3.gecos.guadalinex.org/gecos/" $GCCINI` -eq '0' ] ; then
        echo -n "found no Guadalinex v3 repos --> changing... " && \
        sed -i 's|"http://v2.gecos.guadalinex.org/gecos/",|"http://v2.gecos.guadalinex.org/gecos/", "http://v3.gecos.guadalinex.org/gecos/",|' $GCCINI && \
        sed -i 's|"http://v2.gecos.guadalinex.org/ubuntu/",|"http://v2.gecos.guadalinex.org/ubuntu/", "http://v3.gecos.guadalinex.org/ubuntu/",|' $GCCINI && \
        sed -i 's|"http://v2.gecos.guadalinex.org/mint/"|"http://v2.gecos.guadalinex.org/mint/", "http://v3.gecos.guadalinex.org/mint/"|' $GCCINI && \
        CHANGED='yes' && \
        echo 'done.'
    fi

    if [ `grep -c "GECOS_VERSION" $GCCINI` -gt '0' ] ; then
        echo -n "found \$GECOS_VERSION variable --> changing... " && \
        sed -i "s/\${GECOS_VERSION}/$GCCVER/g" $GCCINI && \
        CHANGED='yes' && \
        echo 'done.'
    fi

    if [ x$CHANGED = 'xno' ] ; then
        echo -n "there had been no changes, deleting backup file... "
        [ -f $GCCINI-$DATE ] && rm -f $GCCINI-$DATE
        echo 'done.'
    fi
}

function processNginxConf() {
    if [ `grep -c proxy_http_version $NGINXC` -eq '0' ] ; then
        echo -n "nginx has no proxy_http_version definition --> changing... " && \
        sed -i '/proxy_pass http:\/\/@app;/a\\n      proxy_http_version 1.1;' $NGINXC
        echo 'done.'
        /etc/init.d/nginx restart
    fi
}

function updatePackagesLists() {
    if [ -x $GCCDIR/bin/pmanage ] ; then
        local LOG="$PWD/`date +%Y%m%d`_packages_list_upgrade.log"
        echo 'upgrading lists of packages...'
        [ -f /opt/rh/python27/enable ] && source /opt/rh/python27/enable
        [ -f $GCCDIR/bin/activate ]    && source $GCCDIR/bin/activate
        echo "a file called $LOG will contain all the output from this process"
        $GCCDIR/bin/pmanage $GCCINI synchronize_repositories >> $LOG 2>&1
        echo 'done.'
    else
        echo "WARNING: packages list upgrade hasn't been done because there is no pmanage executable"
    fi
}

if [ ! $(id -u) = 0 ]; then
    echo 'ERROR: you must be root to run this script'
    exit 1
fi

if [ ! -f $SUPERV ] ; then
    echo "ERROR: $SUPERV not found."
    exit 1
else
    CURVER=`grep '^EXECUTE=' $SUPERV | cut -d/ -f3 | cut -d- -f2`
    if [ $CURVER != '2.2.1' ] ; then
        updateGECOSCC
    else
        echo -n "Right version of gecoscc-ui has been detected. Do you want to overwrite it? (y/N): "
        read OVERWR

        if [ x"$OVERWR" = 'xy' ] ; then
            echo "Overwriting gecoscc-ui... "
            $SUPERV stop
            sed -i 's/2.2.1/2.2.0/g' $SUPERV
            mv /opt/gecosccui-$CURVER /opt/gecosccui-$CURVER-$DATE
            echo "done."
            echo "Former directory has been moved to /opt/gecosccui-$CURVER-$DATE"
            echo -n "Now will go through updating process. Press enter to continue... "
            read

            updateGECOSCC
        else
            echo "Doing nothing."
        fi
    fi
fi

GCCVER='2.2.1'
GCCDIR="/opt/gecosccui-$GCCVER"
GCCINI="$GCCDIR/gecoscc.ini"
PY_GCC="$GCCDIR/lib/python2.7/site-packages/gecoscc"

if [ ! -f $GCCINI ] ; then
    echo "ERROR: $GCCINI not found"
    echo 'Is this a real GECOSCC server?'
    exit 1
else
    processGecosccini
fi

if [ ! -f $NGINXC ] ; then
    echo "ERROR: $NGINXC not found"
    exit 1
else
    processNginxConf
fi

if [ x`rpm -qa chef` != x$CHEFCL ] ; then
    echo "chef package not found, installing version 13.5.3 --> installing... " && \
    rpm -Uvh $CHEFPK && \
    echo 'done.'
fi

echo 'restarting GECOSCC to apply changes...'
$SUPERV restart
echo 'done.'

updatePackagesLists

exit 0
