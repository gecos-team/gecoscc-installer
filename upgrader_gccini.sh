#!/bin/bash

PATH="/bin:/usr/bin:/sbin:/usr/sbin"
LANG="C"
DATE=`date +%Y%m%d%H%M`
GCCDIR="/opt/gecosccui-2.2.0"
GCCINI="$GCCDIR/gecoscc.ini"
GCCVER="2.2.0"
CHEFPK="https://packages.chef.io/files/stable/chef/13.5.3/el/6/chef-13.5.3-1.el6.x86_64.rpm"
CHEFCL="chef-13.5.3-1.el6.x86_64"

if [ ! $(id -u) = 0 ]; then
    echo 'ERROR: debe ejecutar este script como root'
    exit 1
fi

echo -n "haciendo backup de $GCCINI en $GCCINI-$DATE.backup... "
cp -f $GCCINI $GCCINI-$DATE.backup
echo "hecho."

if [ `grep -c "http://forja.guadalinex.org/webs/gecos/doc/v2/doku.php" $GCCINI` -eq '1' ] ; then
    echo -n "encontrado enlace a ayuda incorrecto --> cambiando... " && \
    sed -i 's|^help_manual_url = http://forja.guadalinex.org/webs/gecos/doc/v2/doku.php|help_manual_url = https://github.com/gecos-team/gecos-doc/wiki/Politicas:|' $GCCINI && \
    echo "hecho."
fi

if [ `grep -c "^worker_class = gevent" $GCCINI` -eq '1' ] ; then
    echo -n "encontrado gevent incorrecto --> cambiando... " && \
    sed -i 's/^worker_class = gevent/worker_class = gecoscc.socks.GecosGeventSocketIOWorker/' $GCCINI && \
    echo "hecho."
fi

if [ `grep -c "v2.gecos.guadalinex.org/gems" $GCCINI` -eq '1' ] ; then
    echo -n "encontrado repo gemas incorrecto --> cambiando... " && \
    sed -i 's|^firstboot_api.gem_repo = http://v2.gecos.guadalinex.org/gems|firstboot_api.gem_repo = http://v3.gecos.guadalinex.org/gems|' $GCCINI && \
    echo "hecho."
fi

if [ `grep -c "^timeout = 600" $GCCINI` -eq '1' ] ; then
    echo -n "encontrado timeout incorrecto --> cambiando... " && \
    sed -i 's/^timeout = 600/timeout = 1800/' $GCCINI && \
    echo "hecho."
fi

if [ `grep -c "http://v3.gecos.guadalinex.org/gecos/" $GCCINI` -eq '0' ] ; then
    echo -n "no se ha encontrado repos v3 --> cambiando... " && \
    sed -i 's|"http://v2.gecos.guadalinex.org/gecos/",|"http://v2.gecos.guadalinex.org/gecos/", "http://v3.gecos.guadalinex.org/gecos/",|' $GCCINI && \
    sed -i 's|"http://v2.gecos.guadalinex.org/ubuntu/",|"http://v2.gecos.guadalinex.org/ubuntu/", "http://v3.gecos.guadalinex.org/ubuntu/",|' $GCCINI && \
    sed -i 's|"http://v2.gecos.guadalinex.org/mint/"|"http://v2.gecos.guadalinex.org/mint/", "http://v3.gecos.guadalinex.org/mint/"|' $GCCINI && \
    echo "hecho."
fi

if [ `grep -c "$GECOS_VERSION" $GCCINI` -gt '0' ] ; then
    echo -n "encontrada variable \$GECOS_VERSION --> cambiando... " && \
    sed -i "s/\${GECOS_VERSION}/$GCC_VER/g" $GCCINI && \
    echo "hecho."
fi

if [ x`rpm -qa chef` != x$CHEFCL ] ; then
    echo "no encontrado cliente chef 13.5.3 --> instalando... " && \
    rpm -Uvh $CHEFPK && \
    echo "hecho."
fi

if [ -x $GCCDIR/bin/pmanage ] ; then
    echo "lanzando la sincronización de listas de paquetes..."
    [ -f /opt/rh/python27/enable ] && source /opt/rh/python27/enable
    [ -f $GCCDIR/bin/activate ]    && source $GCCDIR/bin/activate
    $GCCDIR/bin/pmanage $GCCINI synchronize_repositories
    echo "hecho."
else
    echo "AVISO: no se ha lanzado la sincronización de listas de paquetes porque no hay fichero pmanage."
fi

exit 0
