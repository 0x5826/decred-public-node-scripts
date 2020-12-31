#!/bin/bash
set -euo pipefail

function check_root_privilege() {
  if [[ "$UID" -ne '0' ]]; then
    echo "[ERROR]: You must run this script as root!"
    exit 1
  fi
}

function check_linux_archrchitecture() {
  if [[ "$(uname)" == 'Linux' ]]; then
  case "$(uname -m)" in
    'i386' | 'i686')
      MACHINE='386'
      ;;
    'amd64' | 'x86_64')
      MACHINE='amd64'
      ;;
    'armv7' | 'armv7l')
      MACHINE='arm'
      ;;
    'armv8' | 'aarch64')
      MACHINE='arm64'
      ;;
    *)
      echo "[ERROR]: The Architecture is not supported."
      exit 1
      ;;
    esac
  else
    echo "[ERROR]: This OS is not supported."
    exit 1
  fi
}

function check_linux_distribution() {
  if [[ ! -f '/etc/os-release' ]]; then
    echo "[ERROR]: Don't use outdated Linux distributions."
    exit 1
  fi

  if [[ -f /.dockerenv ]] || grep -q 'docker\|lxc' /proc/1/cgroup && [[ "$(type -P systemctl)" ]]; then
    true
  elif [[ -d /run/systemd/system ]] || grep -q systemd <(ls -l /sbin/init); then
    true
  else
    echo "[ERROR]: Only Linux distributions using systemd are supported."
    exit 1
  fi
}

function check_memory_and_disk() {
  free_mem=$(free -m|awk 'NR==2' |awk '{print$7}')
  if [ $free_mem -lt 768 ]
  then 
    echo "[ERROR]: The memory request for 768MB at least, But only $free_mem MB."
    exit 1
  fi

  free_disk=$(df -B G /home |awk '/\//{print$4}' | awk '{sub(/.{1}$/,"")}1' | sed 's/G//')
  if [ $free_disk -lt 8 ]
  then 
    echo "[ERROR]: The dcrd blockdata request for 8GB at least, But only $free_disk GB."
    exit 1
  fi
}

function set_package_management() {
  if [[ "$(type -P apt)" ]]; then
    PACKAGE_MANAGEMENT_UPDATE='apt update'
    PACKAGE_MANAGEMENT_INSTALL='apt -y --no-install-recommends install'
    PACKAGE_MANAGEMENT_REMOVE='apt purge'
    package_provide_tput='ncurses-bin'
  elif [[ "$(type -P dnf)" ]]; then
    PACKAGE_MANAGEMENT_UPDATE='dnf update'
    PACKAGE_MANAGEMENT_INSTALL='dnf -y install'
    PACKAGE_MANAGEMENT_REMOVE='dnf remove'
    package_provide_tput='ncurses'
  elif [[ "$(type -P yum)" ]]; then
    PACKAGE_MANAGEMENT_UPDATE='yum update'
    PACKAGE_MANAGEMENT_INSTALL='yum -y install'
    PACKAGE_MANAGEMENT_REMOVE='yum remove'
    package_provide_tput='ncurses'
  elif [[ "$(type -P zypper)" ]]; then
    PACKAGE_MANAGEMENT_UPDATE='zypper update'
    PACKAGE_MANAGEMENT_INSTALL='zypper install -y --no-recommends'
    PACKAGE_MANAGEMENT_REMOVE='zypper remove'
    package_provide_tput='ncurses-utils'
  elif [[ "$(type -P pacman)" ]]; then
    PACKAGE_MANAGEMENT_UPDATE='pacman update'
    PACKAGE_MANAGEMENT_INSTALL='pacman -Syu --noconfirm'
    PACKAGE_MANAGEMENT_REMOVE='pacman -Rsn'
    package_provide_tput='ncurses'
  else
    echo "[ERROR]: The script does not support the package manager in this operating system."
    exit 1
  fi
}

function install_necessary_software() {
  ${PACKAGE_MANAGEMENT_UPDATE}
  if ${PACKAGE_MANAGEMENT_INSTALL} "curl" "wget" "systemd" ; then
    echo "[INFO]: curl wget systemd is installed."
  else
    echo "[ERROR]: Installation of curl wget failed, please check your network."
    exit 1
  fi
}

function set_install_variables() {
  USER="dcrd"
  GROUP="dcrd"
  DCRD_USER_HOME="/home/$USER"
  DCRD_DATA_HOME="/home/$USER/.dcrd"
  BINARYDIR="$DCRD_USER_HOME/decred"
  BINARYPATH="$DCRD_USER_HOME/decred/dcrd"
  CONFIGPATH="$DCRD_USER_HOME/.dcrd/dcrd.conf"
  RPCUSER=$(openssl rand 16 | base64)
  RPCPASS=$(openssl rand 16 | base64)
  TMPDIR="$(mktemp -d)"
  INTERFACE_IPv4=$(ifconfig -a|grep inet|grep -v 127.0.0.1|grep -v inet6|awk '{print $2}'|tr -d "addr:")
  INTERNET_IPv4=$(curl -s ipv4.ip.sb)
  VERSION=$(curl -fsSL https://api.github.com/repos/decred/decred-binaries/releases/latest | grep tag_name | sed -E 's/.*"(.*)".*/\1/')
  DECRED_ARCHIVE="decred-linux-$MACHINE-$VERSION.tar.gz"
  MANIFEST_SIGN="decred-$VERSION-manifest.txt.asc"
  MANIFEST="decred-$VERSION-manifest.txt"
  BASEURL="https://github.com/decred/decred-binaries/releases/download/$VERSION"
  SERVICEURL="https://raw.githubusercontent.com/decred/dcrd/master/contrib/services/systemd/dcrd.service"
  WIKIURL="https://www.github.com/0x5826"
}

function check_dcrd_env() {
  if [ -d "$DCRD_USER_HOME" ]
  then
    echo "[WARN]：$DCRD_USER_HOME existed."
  fi

  if [ -d "$DCRD_DATA_HOME" ]
  then
    echo "[WARN]: $DCRD_DATA_HOME existed."
  fi

  if [ -d "$BINARYPATH" ]
  then
    echo "[WARN]: $DCRD_DATA_HOME existed."
  fi

  if [ -z "$INTERNET_IPv4" ]
  then
    echo "[ERROR]: Can't detect any internel ip address!"
    exit 1
  elif [ "$INTERFACE_IPv4" != "$INTERNET_IPv4" ]
  then
    echo "[WARN]: Your interface IP:$INTERFACE_IPv4 and Internet IP:$INTERNET_IPv4 are inconsistent, some conditions refer to $WIKIURL"
    echo "[WARN]: dcrd.config will be setted: externalip=$INTERNET_IPv4."
  fi
}

function download_and_verifiy_dcrd() {
  cd "$TMPDIR"
  echo "[INFO]: Downloading $DECRED_ARCHIVE..."
  $(type -P curl) -LO --retry 5 --retry-delay 10 --retry-max-time 60 "$BASEURL/$DECRED_ARCHIVE" || $(type -P wget) -q -t 5 "$BASEURL/$DECRED_ARCHIVE"
  $(type -P curl) -LO --retry 5 --retry-delay 10 --retry-max-time 60 "$BASEURL/$MANIFEST_SIGN" || $(type -P wget) -q -t 5 "$BASEURL/$MANIFEST_SIGN"
  $(type -P curl) -LO --retry 5 --retry-delay 10 --retry-max-time 60 "$BASEURL/$MANIFEST" || $(type -P wget) -q -t 5 "$BASEURL/$MANIFEST"
  $(type -P curl) -LO --retry 5 --retry-delay 10 --retry-max-time 60 "$SERVICEURL" || $(type -P wget) -q -t 5 "$SERVICEURL"
  SHA256SUM=$(grep "$DECRED_ARCHIVE" $MANIFEST | $(type -P sha256sum ) -c -)
  if [[ "$SHA256SUM" =~ "OK" ]]; then
    echo "[INFO]: Download finished and Verified"
  else
    echo "[ERROR]: Check failed! Please check your network or try again."
    rm -f $TMPDIR
    exit 1
  fi
}

function create_usr_dcrd() {
  groupadd $GROUP > /dev/null 2>&1
  useradd -m -g $GROUP -s /sbin/nologin $USER > /dev/null 2>&1
  mkdir -p $DCRD_DATA_HOME && chown dcrd:dcrd $DCRD_DATA_HOME
  mkdir -p $BINARYDIR && chown -R dcrd:dcrd $BINARYDIR
}

function install_dcrd() {
  echo "[INFO]: Installing dcrd……"
  cd $TMPDIR
  tar zxf $DECRED_ARCHIVE
  cp -f "decred-linux-$MACHINE-$VERSION/dcrd" $BINARYPATH && chown dcrd:dcrd $BINARYPATH &&chmod a+x $BINARYPATH
  cp -f "dcrd.service" /etc/systemd/system/dcrd.service
  
  echo "[INFO]: Generating dcrd.conf……"
  echo "externalip=$INTERNET_IPv4" > $CONFIGPATH
  echo "rpcuser=$RPCUSER" >> $CONFIGPATH
  echo "rpcpass=$RPCPASS" >> $CONFIGPATH

  echo "[INFO]: Running dcrd node program……"
  systemctl daemon-reload
  systemctl enable dcrd.service
  systemctl start dcrd.service

  dcrd_status=$(systemctl status dcrd.service)
  if [[ $dcrd_status =~ "running" ]]
  then
      rm -rf $TMPDIR
      echo "[INFO]: dcrd is running, Clean tmp files……"
      echo "[INFO]: dcrd Install Finished!"
      echo "[INFO]: dcrd data directory:$DCRD_DATA_HOME"
      echo "[INFO]: dcrd binary directory:$BINARYPATH"
  else
      systemctl status dcrd.service
      exit 1
  fi
}

function upgrade_dcrd() {
  echo "[INFO]: stop dcrd node program……"
  systemctl stop dcrd.service
  cd "$TMPDIR"
  ##
  echo "[INFO]: starting dcrd node program……"
  dcrd_status=$(systemctl status dcrd.service)
  if [[ $str =~ "running" ]]
  then
      echo "[INFO]: dcrd is running, Clean $TMPDIR……"
      rm -rf "$TMPDIR"
  else
      echo "[ERROR]: There is something wrong with running dcrd. info:"
      systemctl status dcrd.service
      exit 1
  fi
}

function uninstall_dcrd() {
  echo "[INFO]: stop dcrd node program……"
  systemctl stop dcrd.service
  echo "[INFO]: disable dcrd node program on boot and delete dcrd.service……"
  systemctl disable dcrd.service
  rm -f /etc/systemd/system/dcrd.service
  echo "[INFO]: Delete USER:dcrd/GROUP:dcrd/dcrd's home."
  userdel -r $USER
  groupdel $GROUP
}
