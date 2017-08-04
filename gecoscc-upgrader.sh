#!/usr/bin/env bash

# GECOS Control Center Upgrader
# Download it from http://bit.ly/gecoscc-installer

# Authors:
#  Diego Martínez Castañeda <dmartinez@solutia-it.es>
#
# Copyright 2017, Junta de Andalucia
# http://www.juntadeandalucia.es/
#
# Released under EUPL License V 1.1
# http://www.osor.eu/eupl

#set -o nounset

# network check, before variables assignement
curl -k -o - "https://www.google.es/" 1>/dev/null 2>&1
if [ $? -ne 0 ] ; then
    echo "Not Connected! Please check your network configuration and try again."
    exit 1
fi

# Variables

# -- general variables
LANG=C
PATH="/bin:/usr/bin:/sbin:/usr/sbin"
NAME="gecoscc-upgrader"
LOGF="$HOME/$NAME.log"
DATE=`date +%Y%m%d%H%M`
MANPATH="/usr/share/man/"
NO_RAMCHECK='no'
PIVOTAL_PEM='no'

# -- gecoscc variables
GCC_GCCNAME="gecoscc-installer.sh"
GCC_INSTURL="https://raw.githubusercontent.com/gecos-team/gecoscc-installer/2.2.0/$GCC_GCCNAME"
GCC_DWN_INS=`curl -s -L -o /tmp/$GCC_GCCNAME $GCC_INSTURL`
GCC_VERSION=`cat /tmp/$GCC_GCCNAME | grep 'export GECOSCC_VERSION'      | cut -d"'" -f2`
#GCC_TPL_DIR=`cat /tmp/$GCC_GCCNAME | grep 'export TEMPLATES_URL'        | cut -d'"' -f2 | sed -e 's/$GECOSCC_VERSION/'"$GCC_VERSION"'/'`
GCC_TPL_DIR="https://raw.githubusercontent.com/gecos-team/gecoscc-installer/master/templates"
GCC_OHAI_CB=`cat /tmp/$GCC_GCCNAME | grep 'export GECOSCC_OHAI_URL'     | cut -d'"' -f2 | sed -e 's/$GECOSCC_VERSION/'"$GCC_VERSION"'/'`
GCC_WSMG_CB=`cat /tmp/$GCC_GCCNAME | grep 'export GECOSCC_POLICIES_URL' | cut -d'"' -f2 | sed -e 's/$GECOSCC_VERSION/'"$GCC_VERSION"'/'`
GCC_SUPER_D="/etc/init.d/supervisord"
if [ -f $GCC_SUPER_D ] ; then
    GCC_OLD_DIR="/opt/`grep '^EXECUTE' $GCC_SUPER_D | cut -d'/' -f3`"
    GCC_INI_OLD="$GCC_OLD_DIR/gecoscc.ini"
fi
GCC_INI_NEW="$GCC_OPT_DIR/gecoscc.ini"
GCC_EPELPKG="http://dl.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-8.noarch.rpm"
GCC_EPELRPO="https://copr.fedoraproject.org/coprs/rhscl/centos-release-scl/repo/epel-6/rhscl-centos-release-scl-epel-6.repo"
GCC_SCLREPO="https://raw.githubusercontent.com/gecos-team/gecoscc-installer/$GCC_VERSION/templates/scl.repo"
GCC_PYT_DIR="/opt/rh/python27"
GCC_PYT_LST="pip virtualenv"
GCC_OPT_DIR="/opt/gecosccui-$GCC_VERSION"
#GCC_GECOSUI="https://github.com/gecos-team/gecoscc-ui/archive/master.zip"
GCC_GECOSUI="https://github.com/gecos-team/gecoscc-ui/archive/$GCC_VERSION.zip"
GCC_GCC_DIR="/opt/gecoscc/media"
GCC_MED_DIR="$GCC_GCC_DIR/media"
#GCC_TOOLURL="https://raw.githubusercontent.com/gecos-team/gecoscc-installer/$GCC_VERSION/tools"
GCC_TOOLURL="https://raw.githubusercontent.com/gecos-team/gecoscc-installer/master/tools"
GCC_GCC_PSR="$GCC_TOOLURL/gecoscc-parser.py"
GCC_INI_OLD="$GCC_OLD_DIR/gecoscc.ini"
GCC_INI_NEW="$GCC_OPT_DIR/gecoscc.ini"
GCC_SUP_CFG="$GCC_OPT_DIR/supervisord.conf"
GCC_SUP_USR=`cat /tmp/$GCC_GCCNAME | grep 'export SUPERVISOR_USER_NAME' | cut -d'"' -f2 | cut -d= -f2`
GCC_SUP_PWD=`cat /tmp/$GCC_GCCNAME | grep 'export SUPERVISOR_PASSWORD'  | cut -d'"' -f2 | cut -d= -f2`
CHCK_US_LOG="$HOME/$DATE-check-users-report.log"
CHCK_DB_LOG="$HOME/$DATE-check-database-report.log"

# -- chef variables
CHEFVERSION=`cat /tmp/$GCC_GCCNAME | grep 'export CHEF_SERVER_VERSION' | cut -d'"' -f2`
CHEF_11_PKG="https://packages.chef.io/files/stable/chef-server/11.1.7/el/6/chef-server-11.1.7-1.el6.x86_64.rpm"
CHEF_11_DIR="/opt/chef-server"
CHEF_11_BIN="$CHEF_11_DIR/bin"
CHEF_11_VAR="/var$CHEF_11_DIR"
CHEF_11_NGX="$CHEF_11_VAR/nginx"
CHEF_11_BCK="$CHEF_11_DIR/backups/$DATE"
CHEF_11_PNT="$CHEF_11_DIR/backups/.last"
CHEF_11_ETC="/etc/chef-server"
CHEF_11_CNF="$CHEF_11_ETC/chef-server.rb"
CHEF_11_KNF="$HOME/.chef/knife.rb"
CHEF_12_PKG="https://packages.chef.io/files/stable/chef-server/$CHEFVERSION/el/6/chef-server-core-$CHEFVERSION-1.el6.x86_64.rpm"
CHEF_12_CLT="https://packages.chef.io/files/stable/chef/$CHEFVERSION/el/6/chef-$CHEFVERSION-1.el6.x86_64.rpm"
CHEF_12_DIR="/opt/opscode"
CHEF_12_BIN="$CHEF_12_DIR/bin"
CHEF_12_ETC="/etc/opscode"
CHEF_12_NGX="/var$CHEF_12_DIR/nginx"
CHEF_12_BCK="$CHEF_12_DIR/backups/$DATE"
CHEF_12_PNT="$CHEF_12_DIR/backups/.last"
CHEF_12_CNF="/etc/opscode/chef-server.rb"
CHEF_12_TMP="/etc/opscode/chef-server.rb.tmp"
CHEF_12_SSL="$HOME/.chef/trusted_certs"

# -- iptables variables
IPTABLESBCK="$CHEF_12_BCK/iptables_rules.backup"

# -- whiptail variables
MENU_OPTION="False"
WHIP__TITLE="GCC upgrading process"
WHIP_BTITLE="GECOSCC Upgrading"
WHIP_SPRUSR="What is the name of your Chef Superuser?"
WHIP_UPGTXT="
This program performs a complete upgrade of GECOS Control Center (GCC)
and all its components.

You must follow the order in the menu to accomplish the process.

Please, note that some parts of the process must be applied on servers
with certain services (i.e. chef-server), make sure you apply every
option on the right server. Otherwise might have problems.

Please, choose an option:"
WHIP_FINISH="


================ Your GECOSCC service has been upgrade! ================

You must RESTART the server before run the next menu options. After that
you'll have gecoscc-$GCC_VERSION working.

There's a log file of the process in:
- $LOGF"

# Functions

function amIroot() {
    if [ ! $(id -u) = 0 ]; then
        echo 'ERROR: this script must be run as root.'
        exit 2
    fi
}

function write2log() {
    echo -e "[`date +%FT%T%Z`] $NAME: $1" >> $LOGF
    # uncomment to print messages on stdout
    #echo -e "[`date +%FT%T%Z`] $NAME: $1"
}

function OS_checking() {
    if [ -f /etc/redhat-release ] ; then
        [ `grep -c -i 'CentOS'  /etc/redhat-release` -ge "1" ] && \
            export OS_SYS='centos'
        [ `grep -c -i 'Red Hat' /etc/redhat-release` -ge "1" ] && \
            export OS_SYS='redhat'
        export OS_VER=`cat /etc/redhat-release|egrep -o '[0-9].[0-9]'|cut -d'.' -f1`
    else
        write2log "Operating System not supported: wrong operating system."
        echo -e "Operating System not supported: wrong operating system."
        echo -e "Please, check documentation for more information:"
        echo -e "\n\thttps://github.com/gecos-team/gecoscc-installer/blob/master/README.md"
        echo -e "\nAborting installation process."
        exit 3
    fi

    if [ $OS_VER -gt "6" ] ; then
        write2log "Operating System not supported: wrong version."
        echo -e "Operating System not supported: wrong version."
        echo -e "Please, check documentation for more information:"
        echo -e "\n\thttps://github.com/gecos-team/gecoscc-installer/blob/master/README.md"
        echo -e "\nAborting installation process."
        exit 4
    fi
}

function checkOutput() {
    # $1: content of $?
    # $2: command executed
    if [ "$1" -eq '0' ] ; then
        write2log "done."
    else
        write2log "ERROR: executing $2"
        exit 5
    fi
}

function parsingArgs() {
    write2log "parsing arguments..."
    for VARIABLE in "$@" ; do
        write2log "arg: $VARIABLE"
        case $VARIABLE in
            '--no-ram-check') NO_RAMCHECK='yes' ;;
            '--pivotal-pem' ) shift
                if [ -f $1 ] ; then
                    PIVOTAL_PEM="$1"
                else
                    write2log "file provided by argument doesn't exist."
                fi
                ;;
        esac
        shift
    done
}

function checkPrerequisites() {
    write2log "checking prerequisites..."

    # RAM memory
    if [ $NO_RAMCHECK != 'yes' ] ; then
        RAM_MEMORY=`free -m | grep '^Mem:' | awk '{print $2}'`
        if [ $RAM_MEMORY -lt 4096 ] ; then
            write2log "ERROR: low RAM memory ($RAM_MEMORY MB)"
            echo -e "ERROR: low RAM memory"
            echo -e "\nChef 12 will need, at least, 4GB of RAM and it is mandatory to suit it."
            echo -e "Please, update your system before run $NAME again."
            echo -e "\nIn case you want to continue executing $NAME, it will:"
            echo -e " - BE UNDER YOUR OWN RISK"
            echo -e " - MAY CAUSE UNEXPECTED ERRORS"
            echo -e "\nIf you want to run $NAME anyway, use the parameter '--no-ram-check'."
            exit 6
        fi
    else
        write2log "RAM check avoided by user"
    fi

    # FQDN
    FQDN_ERROR=''
    FQDN_NAME=`hostname -s`
    FQDN_DOMA=`hostname -d`
    FQDN_FQDN=`hostname -f`
    FQDN_HOST=`grep HOSTNAME /etc/sysconfig/network | cut -d= -f2 | tr '[:upper:]' '[:lower:]'`

    [ $FQDN_NAME == "localhost" ]             && FQDN_ERROR="hostname is localhost"
    [ -z $FQDN_DOMA ]                         && FQDN_ERROR="no domain name"
    [ $FQDN_FQDN != "$FQDN_NAME.$FQDN_DOMA" ] && FQDN_ERROR="bad domain name"
    [ $FQDN_HOST != $FQDN_FQDN ]              && FQDN_ERROR="uppercase characters"

    if [ "$FQDN_ERROR" != '' ] ; then
        write2log "ERROR: $FQDN_ERROR"
        echo -e "ERROR: $FQDN_ERROR"
        echo -e "Please check your system's name and domain in:"
        echo -e " - /etc/sysconfig/network"
        echo -e " - /etc/hosts"
        echo -e "in order to have a well formed FQDN and reboot your server."
        echo -e "Remember you must use lower characters."
        echo -e "Try executing 'hostname -[s|d|f]' to check your complete FQDN."
        exit 7
    fi
}

function showLogo() {
    whiptail --backtitle "$WHIP_BTITLE" --msgbox '
                               ____ ____
      __ _  ___  ___ ___  ___ / ___/ ___|
     / _` |/ _ \/ __/ _ \/ __| |  | |
    | (_| |  __/ (_| (_) \__ \ |__| |___
     \__, |\___|\___\___/|___/\____\____|
     |___/
          ...Upgrading process...
    ' 16 50
}

function showMenu() {
    export MENU_OPTION=`whiptail --title "$WHIP__TITLE" --backtitle "$WHIP_BTITLE" \
        --menu \
        "$WHIP_UPGTXT" 24 78 8 \
        "Upgrade Chef"    "Upgrade Chef 11 to Chef 12       " \
        "Delete Chef 11"  "Delete ALL Chef 11 data, for good" \
        " "               "                                 " \
        "Upgrade GECOSCC" "Upgrade GECOS Control Center     " \
        "Check users"     "Check users permissions          " \
        "Check database"  "Check database integrity         " \
        " "               "                                 " \
        "Exit"            "Exit                             " \
        3>&1 1>&2 2>&3`
}

function downloadURL() {
    # $1: URL to download
    # $2: if exists, full path of the file

    if [ -z "$2" ] ; then
        local CURL_ARGS="-O"
    else
        local CURL_ARGS="-o $2"
    fi

    curl -s -L -f $CURL_ARGS $1

    if [ $? -ne '0' ] ; then
        write2log "ERROR: failed downloading $1"
        echo -e   "ERROR: failed downloading $1"
        echo -e   "Please, check the URL and run upgrader again."
        exit 8
    fi
}

function installPackage() {
    if [ ! `rpm -qa $*` ] ; then
        write2log "yum install $*"
        yum install -y $*
        checkOutput "$?" "yum install $*"
    fi
}

function reconfiguringChef() {
    # $1: chef main number version [11|12]

    [ $1 == "11" ] && local CHEF_CURR_VER="chef-server"
    [ $1 == "12" ] && local CHEF_CURR_VER="opscode"

    write2log "performing chef-server-ctl reconfigure... "
    /opt/$CHEF_CURR_VER/bin/chef-server-ctl reconfigure 2>&1> /dev/null
    checkOutput "$?" "chef ($CHEF_CURR_VER) reconfigure"
}

function preparingChef11() {
    write2log "preparing Chef..."

    if [ ! -d $CHEF_11_DIR ] ; then
        write2log "Chef installation not found in $CHEF_11_DIR"
        exit 8
    fi

    [ ! -d $CHEF_11_BCK ] && mkdir -p $CHEF_11_BCK
    [ ! -d $CHEF_12_BCK ] && mkdir -p $CHEF_12_BCK

    write2log "iptables rules saved in $IPTABLESBCK"
    iptables-save > $IPTABLESBCK
    write2log "flusing iptables rules"
    iptables -F

    write2log "fixing max nesting number"
    CHEF_VERS=`/opt/chef-server/embedded/bin/gem spec chef| grep -A3 '^name: chef' | grep '  version:' | cut -d: -f2 | tr -d ' '`
    sed -i 's/self.to_hash.to_json(\*a)/self.to_hash.to_json(*a, :max_nesting => 1000)/g' \
        $CHEF_11_DIR/embedded/lib/ruby/gems/1.9.1/gems/chef-$CHEF_VERS/lib/chef/cookbook/metadata.rb

    write2log "seeking for knife program"
    if [ ! -f /opt/chef/bin/knife ] ; then
        write2log "/opt/chef/bin/knife not found"
        echo "ERROR: /opt/chef/bin/knife not found. Please solve this issue"
        echo "       and execute $NAME again."
        exit 9
    fi

    write2log "fixing cookbooks issues"
    if [ ! -f /tmp/knife.rb ] ; then
        write2log "/tmp/knife.rb not found. Trying default configuration"
        GCC_KNIFE="-s https://`hostname -f`:443 -u admin -k $CHEF_11_ETC/admin.pem"
    else
        GCC_KNIFE="-c /tmp/knife.rb"
    fi

    KNIFE_TEST=`/opt/chef/bin/knife cookbook list $GCC_KNIFE 2> /dev/null | grep -c ^chef-client`
    if [ $KNIFE_TEST -eq "0" ] ; then
        write2log "failed getting cookbooks list"
        echo "ERROR: unable to get cookbook list. Please solve this"
        echo "       error and restart upgrading process."
        exit 10
    fi

    COOKBOOKDIR="/tmp/upgrader_cb" 
    [ -d $COOKBOOKDIR ] && rm -rf $COOKBOOKDIR
    mkdir -p $COOKBOOKDIR

    for COOKBOOK in ohai-gecos gecos_ws_mgmt
     do
        case $COOKBOOK in
            'ohai-gecos')
                COOK__URL=$GCC_OHAI_CB
                COOK_NAME="ohai"
                COOK__DEF="ohai-gecos"
            ;;
            'gecos_ws_mgmt')
                COOK__URL=$GCC_WSMG_CB
                COOK_NAME="management"
                COOK__DEF="gecos_ws_mgmt"
            ;;
        esac

        installPackage unzip
        mkdir -p $COOKBOOKDIR/$COOK_NAME
        downloadURL $COOK__URL $COOKBOOKDIR/$COOK_NAME/$GCC_VERSION.zip
        unzip -qo -d $COOKBOOKDIR/$COOK_NAME $COOKBOOKDIR/$COOK_NAME/$GCC_VERSION.zip
        if [ $? != '0' ] ; then
            write2log "ERROR: unziping $COOKBOOKDIR/$COOK_NAME/$GCC_VERSION.zip failed."
            exit 10
        fi
        CB_VERS=`ls -d $COOKBOOKDIR/$COOK_NAME/gecos-workstation-$COOK_NAME* | cut -d'-' -f5`
        mv $COOKBOOKDIR/$COOK_NAME/gecos-workstation-$COOK_NAME-cookbook-$CB_VERS \
            $COOKBOOKDIR/$COOK_NAME/$COOK__DEF
        /opt/chef/bin/knife cookbook upload $COOK__DEF -o $COOKBOOKDIR/$COOK_NAME $GCC_KNIFE
        /opt/chef/bin/knife cookbook delete $COOK__DEF -a -y $GCC_KNIFE
        /opt/chef/bin/knife cookbook upload $COOK__DEF -o $COOKBOOKDIR/$COOK_NAME $GCC_KNIFE
     done
}

function installingChef() {
    write2log "installing Chef (11 and 12)"

    for CHEF_CURRENT in chef-server chef-server-core ; do
        write2log "processing: $CHEF_CURRENT"

        [ -d ./packages ] && CHEF_PACKAGES="YES"

        case $CHEF_CURRENT in
            "chef-server")
                CHEF_RUNUPD="1"
                CHEF_VERS_1=11 && CHEF_VERS_2=1  && CHEF_VERS_3=7
                CHEF_VERNUM=`rpm -qa $CHEF_CURRENT | cut -d'-' -f3`
                if [ -d "./packages" ] ; then
                    CHEF_ACTION="-Uvh ./packages/chef-server-11.1.7-1.el6.x86_64.rpm"
                else
                    CHEF_ACTION="-Uvh $CHEF_11_PKG"
                fi
                ;;
            "chef-server-core")
                CHEF_RUNUPD="0"
                CHEF_VERS_1=12 && CHEF_VERS_2=14 && CHEF_VERS_3=0
                CHEF_VERNUM=`rpm -qa $CHEF_CURRENT | cut -d'-' -f4`
                if [ -d "./packages" ] ; then
                    CHEF_ACTION="-ivh ./packages/chef-server-core-$CHEFVERSION-1.el6.x86_64.rpm"
                else
                    CHEF_ACTION="-ivh $CHEF_12_PKG"
                fi
                ;;
        esac

        CHEF_CURR_1=`echo $CHEF_VERNUM | cut -d'.' -f1`
        CHEF_CURR_2=`echo $CHEF_VERNUM | cut -d'.' -f2`
        CHEF_CURR_3=`echo $CHEF_VERNUM | cut -d'.' -f3`

        if [ "$CHEF_CURR_1" == "$CHEF_VERS_1" -a "$CHEF_CURR_2" == "$CHEF_VERS_2" -a "$CHEF_CURR_3" == "$CHEF_VERS_3" ] ; then
            write2log "$CHEF_CURRENT: $CHEF_CURR_1.$CHEF_CURR_2.$CHEF_CURR_3. No need for update"
        else
            write2log "stopping chef 11 server... "
            $CHEF_11_BIN/chef-server-ctl stop

            if [ -f $GCC_SUPER_D ] ; then
                write2log "stopping supervisord... "
                $GCC_SUPER_D stop
            fi

            if [ -f /etc/init.d/nginx ] ; then
                if [ `pidof -s nginx` ] ; then
                    write2log "stopping nginx... "
                    /etc/init.d/nginx stop
                fi
            fi

            write2log "executing $CHEF_ACTION"
            rpm --nosignature $CHEF_ACTION
            checkOutput "$?" "rpm $CHEF_ACTION"

            if [ $CHEF_RUNUPD == "1" ] ; then
                write2log "executing chef upgrade..."
                $CHEF_11_BIN/chef-server-ctl upgrade
                checkOutput "$?" "chef12 upgrade"
                $CHEF_11_BIN/chef-server-ctl restart
            fi
        fi
    done

    write2log "copying CA files"
    [ ! -d $CHEF_12_NGX ] && mkdir -p $CHEF_12_NGX
    cp -r $CHEF_11_NGX/ca $CHEF_12_NGX
}

function exportingChef11() {
    write2log "backing up information in $CHEF_11_BCK"

    write2log "fixing max nesting number"
    sed -i 's/self.to_hash.to_json(\*a)/self.to_hash.to_json(*a, :max_nesting => 1000)/g' \
        $CHEF_11_DIR/embedded/lib/ruby/gems/1.9.1/gems/chef-11.12.2/lib/chef/cookbook/metadata.rb

    write2log "setting up chef servers in order to backup information..."
    $CHEF_12_BIN/chef-server-ctl stop
    $CHEF_11_BIN/chef-server-ctl restart

    [ ! -d $CHEF_11_BCK ] && mkdir -p $CHEF_11_BCK
    [ ! -d $CHEF_12_BCK ] && mkdir -p $CHEF_12_BCK

    $CHEF_12_BIN/chef-server-ctl \
        chef12-upgrade-download  \
        --download-only \
        --chef11-data-dir $CHEF_11_BCK
    checkOutput "$?" "chef chef12-upgrade-download"

    write2log "saving last state in $CHEF_11_PNT..."
    echo "$CHEF_11_BCK" > $CHEF_11_PNT

    [  -x /etc/init.d/nginx ] && /etc/init.d/nginx stop
    $CHEF_11_BIN/chef-server-ctl stop
    $CHEF_12_BIN/chef-server-ctl stop

    write2log "upgrading chef-server-ctl-12"
    $CHEF_12_BIN/chef-server-ctl \
        upgrade \
        --yes \
        --org-name          default \
        --full-org-name     default \
        --user              admin \
        --key               /etc/chef-server/admin.pem \
        --chef11-data-dir   $CHEF_11_BCK \
        --chef12-data-dir   $CHEF_12_BCK
    checkOutput "$?" "upgrading chef-server-ctl-12"

    write2log "transforming data from chef 11 to chef 12 format..."
    $CHEF_12_BIN/chef-server-ctl \
        chef12-upgrade-data-transform \
        --chef11-data-dir `cat $CHEF_11_PNT` \
        --chef12-data-dir $CHEF_12_BCK \
        --org-name        default \
        --full-org-name   default
    checkOutput "$?" "chef chef12-upgrade-data-transform"

    write2log "saving last state in $CHEF_12_PNT..."
    echo "$CHEF_12_BCK" > $CHEF_12_PNT
}

function finishedWarning() {
    whiptail --title "$WHIP__TITLE" --backtitle "$WHIP_BTITLE" \
        --msgbox "$WHIP_FINISH" 18 78
}

function checksWarning() {
    WHIP_CHECKS="




There is a log file of the process and it might be checked in case there
is wrong data:

- $1"

    whiptail --title "$WHIP__TITLE" --backtitle "$WHIP_BTITLE" \
        --msgbox "$WHIP_CHECKS" 18 78
}

function loadingUpChef12() {
    write2log "uploading data to chef 12..."

    [ ! -L /usr/bin/erl ] && ln -s $CHEF_12_DIR/embedded/bin/erl /usr/bin/

    $CHEF_12_BIN/chef-server-ctl restart

    write2log "fixing chef11 exported users JSON"
    sed -i 's/"username"/"name"/' `cat $CHEF_12_PNT`/users/*.json

    if [ ! -f $CHEF_12_PNT ] ; then
        whiptail --title "$WHIP__TITLE" --backtitle "$WHIP_BTITLE" \
            --msgbox "Please, select Phase 1 before Phase 2." 18 78
    else
        write2log "uploading data"
        CHEF_12_BCK=`cat $CHEF_12_PNT`
        $CHEF_12_BIN/private-chef-ctl restart rabbitmq
        $CHEF_12_BIN/chef-server-ctl \
            chef12-upgrade-upload \
            --chef12-data-dir $CHEF_12_BCK \
            --org-name        default
        checkOutput "$?" "chef chef12-upgrade-upload"
    fi
}

function changingFromChef11ToChef12() {
    write2log "performing the change to Chef 12..."

    CHEF_11_SUP=`whiptail --title "$WHIP__TITLE" --backtitle "$WHIP_BTITLE" --inputbox "$WHIP_SPRUSR" 8 78 "superuser" 3>&1 1>&2 2>&3`

    sed -i '1 i\\n# Chef 11 server setup\n' $CHEF_11_CNF
    cat $CHEF_12_CNF $CHEF_11_CNF > $CHEF_12_TMP
    mv $CHEF_12_TMP $CHEF_12_CNF

    reconfiguringChef "12"

    [ -f $GCC_SUPER_D ] && $GCC_SUPER_D restart
    [ -f /etc/init.d/nginx ]      && /etc/init.d/nginx      restart

    write2log "granting permissions to admin user"
    $CHEF_12_BIN/chef-server-ctl \
        grant-server-admin-permissions \
        $CHEF_11_SUP
}

function updatingChefClient() {
    CHEF_CLTVER=`rpm -qa chef | cut -d- -f2`
    case $CHEF_CLTVER in
        "")
            CHEF_12_OPT="-ivh"
            ;;
        "$CHEFVERSION")
            write2log "chef client already in lastest version"
            CHEF_12_OPT="NOP"
            ;;
        *)
            CHEF_12_OPT="-Uvh"
            ;;
    esac

    if [ $CHEF_12_OPT != 'NOP' ] ; then
        write2log "executing rpm $CHEF_12_OPT $CHEF_12_CLT"
        rpm $CHEF_12_OPT $CHEF_12_CLT
        checkOutput "$?" "rpm $CHEF_12_OPT $CHEF_12_CLT"
    fi

    if [ -f $CHEF_11_KNF ] ; then
        write2log "updating ~/.chef/knife.rb"
        CHEF_NODNAM=`grep node_name              $CHEF_11_KNF | cut -d"'" -f2`
        CHEF_SRVURL=`grep chef_server_url        $CHEF_11_KNF | cut -d"'" -f2`
        CHEF_CLTKEY=`grep client_key             $CHEF_11_KNF | cut -d"'" -f2`
        CHEF_VALNAM=`grep validation_client_name $CHEF_11_KNF | cut -d"'" -f2`
        CHEF_VALKEY=`grep validation_key         $CHEF_11_KNF | cut -d"'" -f2`

        [ ! -d $CHEF_12_SSL ] && mkdir -p $CHEF_12_SSL

        $CHEF_12_BIN/knife configure -y  \
            --config                 $CHEF_11_KNF \
            --server-url             $CHEF_SRVURL \
            --user                   $CHEF_NODNAM \
            --admin-client-key       $CHEF_CLTKEY \
            --validation-client-name $CHEF_VALNAM \
            --validation-key         $CHEF_VALKEY \
            --repository             ''
        $CHEF_12_BIN/knife ssl fetch
    fi

}

function disablingChef11() {
    if [ -f /etc/init/chef-server-runsvdir.conf ] ; then
        echo "manual" > /etc/init/chef-server-runsvdir.override
    fi
}

function deleteChef11() {
    write2log "deleting chef 11 completely"

    DEL_CHF_MSG="If you are completely sure about deleting Chef 11 data and want to continue with it, write:

                             'Yes, I am sure!'"
    DELETE_CHEF=`whiptail --title "$WHIP__TITLE" --backtitle "$WHIP_BTITLE" --inputbox "$DEL_CHF_MSG" 11 78 "" 3>&1 1>&2 2>&3`

    if [ "$DELETE_CHEF" == "Yes, I am sure!" ] ; then
        if [ `rpm -qa chef-server` ] ; then
            write2log "deleting chef-server package... "
            rpm -e chef-server
            checkOutput "$?" "rpm erase chef-server"
        fi

        write2log "deleting file and directories"
        [ -d $CHEF_11_DIR ] && rm -rf $CHEF_11_DIR
        [ -d $CHEF_11_VAR ] && rm -rf $CHEF_11_VAR
        [ -f $CHEF_11_CNF ] && rm -f  $CHEF_11_CNF

        [ -f $CHEF_11_ETC/chef-server-running.json ] && \
            rm -f  $CHEF_11_ETC/chef-server-running.json
        [ -f $CHEF_11_ETC/chef-server-secrets.json ] && \
            rm -f  $CHEF_11_ETC/chef-server-secrets.json
    fi
}

function checkForPivotalPEM() {
    write2log "checking for pivotal certificate..."

    if [ $PIVOTAL_PEM != 'no' ] ; then
        write2log "user provide a certificate in $PIVOTAL_PEM. Using it."
    else
        if [ -f $CHEF_12_ETC/pivotal.pem ] ; then
            PIVOTAL_PEM="$CHEF_12_ETC/pivotal.pem"
        else
            write2log "ERROR: $CHEF_12_ETC/pivotal.pem not found"
            echo -e   "ERROR: $CHEF_12_ETC/pivotal.pem not found"
            echo -e   " You must provide the upgrader with pivotal's certificate in the path"
            echo -e   "                  $CHEF_12_ETC/pivotal.pem\n"
            echo -e   " In case you have the file in other location, pass it to the script with"
            echo -e   " the argument --pivotal-pem.\n"
            echo -e   " i.e.: $NAME --pivotal-pem /tmp/cert_chef_piv.pem"
            exit 12
        fi
    fi
}

function installingPython27() {
    write2log "updating python to 2.7..."

    write2log "installing epel repo"
    [ ! `rpm -qa epel-release` ] && rpm -ivh $GCC_EPELPKG

    if [ $OS_SYS = 'centos' ] ; then
        installPackage centos-release-scl
    else
        if [ ! `rpm -qa centos-release-scl` ] ; then
            write2log "installing scl repo in redhat"
            yum-config-manager --enable rhel-server-rhscl-6-rpms
            yum-config-manager --add-repo $GCC_EPELRPO
            yum install -y centos-release-scl
            yum-config-manager --add-repo $GCC_SCLREPO
        fi
    fi

    write2log "updating python 2.6 to python 2.7.8"
    installPackage python27-python-2.7.8-18.el6.x86_64 \
                   python27-python-libs-2.7.8-18.el6.x86_64 \
                   python27-python-devel-2.7.8-18.el6.x86_64

    installPackage python27-1.1-25.el6.x86_64

    if [ -z $MANPATH ] ; then
        unset MANPATH
        MANPATH="/usr/share/man/"
    fi

    source $GCC_PYT_DIR/enable

    write2log "installing all python programs"
    for PYTHON_PROG in $GCC_PYT_LST ; do
        write2log "pip install upgrade $PYTHON_PROG"
        pip install --upgrade $PYTHON_PROG
        checkOutput "$?" "pip install upgrade $PYTHON_PROG"
    done

    write2log "creating the virtualenv"
    if [ ! -d $GCC_OPT_DIR ] ; then
        write2log "creating virtualenv in $GCC_OPT_DIR"
        virtualenv -p $GCC_PYT_DIR/root/usr/bin/python2.7 $GCC_OPT_DIR
        checkOutput "$?" "creating virtualenv in $GCC_OPT_DIR"
    else
        write2log "virtualenv already created in $GCC_OPT_DIR"
    fi

    write2log "activating the virtualenv"
    PS1="gecoscc_2.2|\u@\h:\w> "
    source $GCC_OPT_DIR/bin/activate
}

function installingGCC22() {
    write2log "installing GECOSCC 2.2"

    write2log "pip install upgrade supervisor"
    pip install --upgrade supervisor
    checkOutput "$?" "pip install upgrade supervisor"

    write2log "installing gecosccui"
    if [ `pip show gecoscc | grep -c '^Version: 2.2.0'` == '1' ] ; then
        write2log "gecoscc-ui version 2.2.0 already installed"
    else
        write2log "pip install upgrade gecoscc-ui"
        pip install --upgrade $GCC_GECOSUI
        checkOutput "$?" "pip install upgrade gecoscc-ui"
    fi
}

function configuringGCC22() {
    write2log "configuring GECOSCC 2.2"

    write2log "parsing gecoscc.ini"
    downloadURL $GCC_GCC_PSR
    downloadURL $GCC_TPL_DIR/gecoscc.tpl
    downloadURL $GCC_TPL_DIR/gecoscc.sub
    chmod 755 gecoscc-parser.py

    [ -f $GCC_INI_NEW ] && rm -f $GCC_INI_NEW
    write2log "parsing $GCC_INI_OLD"
    ./gecoscc-parser.py \
        $GCC_INI_OLD    \
        gecoscc.tpl     \
        gecoscc.sub     \
        $GCC_INI_NEW
    checkOutput "$?" "parsing $GCC_INI_OLD"

    write2log "configuring $GCC_SUPER_D"
    [ -f $GCC_SUPER_D ] && mv $GCC_SUPER_D $GCC_SUPER_D.gcc-upg
    downloadURL $GCC_TPL_DIR/supervisord $GCC_SUPER_D
    sed -i 's/${GECOSCC_VERSION}/'"$GCC_VERSION"'/g' $GCC_SUPER_D
    chmod 755 $GCC_SUPER_D

    write2log "configuring supervisord.conf"
    [ -f $GCC_SUP_CFG ] && mv $GCC_SUP_CFG $GCC_SUP_CFG.gcc-upg
    downloadURL $GCC_TPL_DIR/supervisord.conf $GCC_SUP_CFG
    sed -i 's/${GECOSCC_VERSION}/'"$GCC_VERSION"'/g'      $GCC_SUP_CFG
    sed -i 's/${SUPERVISOR_USER_NAME}/'"$GCC_SUP_USR"'/g' $GCC_SUP_CFG
    sed -i 's/${SUPERVISOR_PASSWORD}/'"$GCC_SUP_PWD"'/g'  $GCC_SUP_CFG

    write2log "checking gecoscc dirs"
    [ ! -d $GCC_OPT_DIR/supervisor/run ] && mkdir -p $GCC_OPT_DIR/supervisor/run
    [ ! -d $GCC_OPT_DIR/supervisor/log ] && mkdir -p $GCC_OPT_DIR/supervisor/log
    chkconfig supervisord on

    write2log "creating gecoscc user"
    [ ! `id -u gecoscc 2> /dev/null` ] && \
        adduser -d $GCC_OPT_DIR \
            -r \
            -s /bin/false \
            gecoscc

    [ ! -d $GCC_OPT_DIR/sessions ] && \
         mkdir -p $GCC_OPT_DIR/sessions
    [ ! -d $GCC_MED_DIR/users ] && \
         mkdir -p $GCC_MED_DIR/users
    
    chown -R gecoscc:gecoscc $GCC_GCC_DIR
    chown -R gecoscc:gecoscc $GCC_OPT_DIR/sessions/
    chown -R gecoscc:gecoscc $GCC_OPT_DIR/supervisor/
}

function fixingGevent() {
    write2log "fixing gevent-socketio error"
    sed -i 's/"Access-Control-Max-Age", 3600/"Access-Control-Max-Age", "3600"/' \
        $GCC_OPT_DIR/lib/python2.7/site-packages/socketio/handler.py
    sed -i 's/"Access-Control-Max-Age", 3600/"Access-Control-Max-Age", "3600"/' \
        $GCC_OPT_DIR/lib/python2.7/site-packages/socketio/transports.py
}

function fixingSharedMemory() {
    write2log "fixing celery and gunicorn issue with shared memory"
    sed  -i 's/^tmpfs/#tmpfs/' /etc/fstab
    echo -e "none\t\t\t/dev/shm\t\ttmpfs\trw,nosuid,nodev,noexec\t0 0" >> /etc/fstab 
}

function executePmanage() {
    local VERSION=$1
    local COMMAND=$2
    PS1="gecoscc-upgrader> "

    if [ $# -eq "3" ] ; then
        OUTPUT=$3
    else
        OUTPUT=$LOGF
    fi

    case $VERSION in
        "11")
            PMANAGE="$GCC_OLD_DIR/bin/pmanage"
            GCC_INI="$GCC_INI_OLD"
            PY_ENAB="not_enabled"
            GCC_ACT="$GCC_OLD_DIR/bin/activate"
            CHEFETC=$CHEF_11_ETC
            PM_USER="admin"
            ;;
        "12")
            PMANAGE="$GCC_OPT_DIR/bin/pmanage"
            GCC_INI="$GCC_INI_NEW"
            PY_ENAB="$GCC_PYT_DIR/enable"
            GCC_ACT="$GCC_OPT_DIR/bin/activate"
            CHEFETC=$CHEF_12_ETC
            PM_USER="pivotal"
            ;;
    esac

    write2log "executing pmanage: $VERSION $COMMAND"

    [ -f $PY_ENAB ] && source $PY_ENAB
    [ -f $GCC_ACT ] && source $GCC_ACT

    $PMANAGE \
        $GCC_INI \
        $COMMAND \
        -a $PM_USER \
        -k $PIVOTAL_PEM >> $OUTPUT 2>&1
    checkOutput "$?" "executing pmanage: ver $VERSION comm $COMMAND"
}
###############################################################################
#                                MAIN                                         #
###############################################################################

amIroot

write2log "Starting up upgrading process for GECOSCC..."

# Uncomment in case you want fresh log
#[ -f $LOGF ] && rm -f $LOGF

[ -f $GCC_PYT_DIR/enable ] && source $GCC_PYT_DIR/enable

OS_checking
parsingArgs "$@"
checkPrerequisites
showLogo

while [ "$MENU_OPTION" != "Exit" ] ; do

    showMenu

    case $MENU_OPTION in
        "Upgrade Chef")
            write2log "Upgrading Chef 11 to Chef 12"
            preparingChef11
            reconfiguringChef "11"
            installingChef
            exportingChef11
            loadingUpChef12
            changingFromChef11ToChef12
            updatingChefClient
            disablingChef11
            write2log "Finished Upgrading Chef 11 to Chef 12"
            ;;
        "Delete Chef 11")
            write2log "Deleting Chef 11 data"
            deleteChef11
            write2log "Finished Deleting Chef 11 data"
            ;;
        "Upgrade GECOSCC")
            write2log "Upgrading GECOSCC"
            checkForPivotalPEM
            installingPython27
            installingGCC22
            configuringGCC22
            installPackage redis
            chkconfig --level 3 redis on
            fixingGevent
            fixingSharedMemory
            executePmanage "12" "import_policies"
            finishedWarning
            write2log "Finished Upgrading GECOSCC"
            ;;
        "Check users")
            write2log "Checking users permissions"
            executePmanage "12" "migrate_to_chef12" $CHCK_US_LOG
            write2log "Finished Checking users permissions"
            checksWarning $CHCK_US_LOG
            ;;
        "Check database")
            write2log "Checking database integrity"
            executePmanage "12" "check_node_policies" $CHCK_DB_LOG
            write2log "Finished Checking database integrity"
            checksWarning $CHCK_DB_LOG
            ;;
    esac
done

write2log "Exiting..."

exit 0

