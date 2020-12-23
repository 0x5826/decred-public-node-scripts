#!/bin/bash
set -euo pipefail

function check_root() {
  if [[ "$UID" -ne '0' ]]; then
    echo "error: You must run this script as root!"
    exit 1
  fi
}

function check_os_arch() {
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
      echo "[ERROR]The architecture is not supported."
      exit 1
      ;;
    esac
    if [[ ! -f '/etc/os-release' ]]; then
      echo "error: Don't use outdated Linux distributions."
      exit 1
    fi

    if [[ -f /.dockerenv ]] || grep -q 'docker\|lxc' /proc/1/cgroup && [[ "$(type -P systemctl)" ]]; then
      true
    elif [[ -d /run/systemd/system ]] || grep -q systemd <(ls -l /sbin/init); then
      true
    else
      echo "error: Only Linux distributions using systemd are supported."
      exit 1
    fi
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
      echo "error: The script does not support the package manager in this operating system."
      exit 1
    fi
  else
    echo "error: This operating system is not supported."
    exit 1
  fi
}

function install_software() {
  ${PACKAGE_MANAGEMENT_UPDATE}
  if ${PACKAGE_MANAGEMENT_INSTALL} "curl" "wget" ; then
    echo "[INFO]curl wget is installed."
  else
    echo "[ERROR]Installation of curl wget failed, please check your network."
    exit 1
  fi
}

function check_os_resources() {
  free_mem=$(free -m|awk 'NR==2' |awk '{print$7}')
  if [ $free_mem -lt 768 ]
  then 
    echo "[ERROR]The memory request for 768MB at least, But only $free_mem MB."
    exit 1
  fi

  free_disk=$(df -B G /home |awk '/\//{print$4}' | awk '{sub(/.{1}$/,"")}1' | sed 's/G//')
  if [ $free_disk -lt 8 ]
  then 
    echo "[ERROR]The disk request for 8GB at least, But only $free_disk GB."
    exit 1
  fi
}

function set_env_variables() {
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

function check_dcrd_env () {
  egrep "^$GROUP" /etc/group >& /dev/null
  if [ $? -eq 0 ]
  then
    echo "[WARN]Found user:$GROUP."
  fi

  egrep "^$USER" /etc/passwd >& /dev/null
  if [ $? -eq 0 ]
  then
    echo "[WARN]Found group:$USER."
  fi

  if [ -d "$DCRD_USER_HOME" ]
  then
    echo "[WARN]$DCRD_USER_HOME existed"
  fi

  if [ -d "$DCRD_DATA_HOME" ]
  then
    read -p "[WARN]$DCRD_DATA_HOME existed, Do you want to delete $DCRD_DATA_HOME [Y/n] " yn
    case $yn in
        [Yy] )
        rm -rf $DCRD_DATA_HOME
        echo "[INFO]$DCRD_DATA_HOME deleted."
        ;;
        [Nn]|"" )
        echo "[WARN]The existed diretory may cause unexpected problem!"
        ;;
    esac
  # Step 3 Generate dcrd.con
  fi

  if [ -d "$BINARYPATH" ]
  then
    read -p "[WARN]$BINARYPATH existed, Do you want to delete $BINARYPATH [Y/n] " yn
    case $yn in
        [Yy] )
        rm -rf $BINARYPATH
        echo "[INFO]$BINARYPATH deleted."
        ;;
        [Nn]|"" )
        echo "[WARN]The existed diretory may cause unexpected problem!"
        ;;
    esac
  fi

  dcrd_port=$(netstat -an | grep ":9108 " | awk '$1 == "tcp" && $NF == "LISTEN" {print $0}')
  if [ -n "$dcrd_port" ]
  then
    echo "[ERROR]Another program listening 9108 Port."
    exit 1
  fi

  if [ "$INTERFACE_IPv4" != "$INTERNET_IPv4" ]
  then
    echo "[WARN]Your interface IP:$INTERFACE_IPv4 and Internet IP:$INTERNET_IPv4 are inconsistent, some conditions refer to $WIKIURL"
    echo "[WARN]Dcrd Node will use Internet IP for dcrd.conf."
  fi
}

function download_dcrd() {
  cd "$TMPDIR"
  echo "[INFO]Downloading $DECRED_ARCHIVE..."
  $(type -P curl) -LO --retry 5 --retry-delay 10 --retry-max-time 60 "$BASEURL/$DECRED_ARCHIVE" || $(type -P wget) -q -t 5 "$BASEURL/$DECRED_ARCHIVE"
  $(type -P curl) -LO --retry 5 --retry-delay 10 --retry-max-time 60 "$BASEURL/$MANIFEST_SIGN" || $(type -P wget) -q -t 5 "$BASEURL/$MANIFEST_SIGN"
  $(type -P curl) -LO --retry 5 --retry-delay 10 --retry-max-time 60 "$BASEURL/$MANIFEST" || $(type -P wget) -q -t 5 "$BASEURL/$MANIFEST"
  SHA256SUM=$(grep "$DECRED_ARCHIVE" $MANIFEST | $(type -P sha256sum ) -c -)
  if [[ "$SHA256SUM" =~ "OK" ]]; then
    echo "[INFO]Download finished and Verify"
  else
    echo "[ERROR]Check failed! Please check your network or try again."
    rm -f $TMPDIR
    exit 1
  fi
}

function install_dcrd() {
  echo "[INFO]Installing dcrd……"
  # Step 1 create dcrd dcrd
  egrep "^$GROUP" /etc/group >& /dev/null
  if [ $? -ne 0 ]
  then
      groupadd $GROUP
  fi

  egrep "^$USER" /etc/passwd >& /dev/null
  if [ $? -ne 0 ]
  then
      useradd -m -g $GROUP -s /sbin/nologin $USER
  fi
  # Step 2 COPY binary and systemd service file
  mkdir -p $DCRD_DATA_HOME && chown dcrd:dcrd $DCRD_DATA_HOME
  mkdir -p $BINARYDIR && chown -R dcrd:dcrd $BINARYDIR
  cd "$TMPDIR"
  tar zxf $DECRED_ARCHIVE
  cp -f "$TMPDIR/decred-linux-$MACHINE-$VERSION/dcrd" $BINARYPATH && chown dcrd:dcrd $BINARYPATH &&chmod a+x $BINARYPATH
  cp -f "$TMPDIR/dcrd.service" /etc/systemd/system/dcrd.service
  
  read -p "[INFO]Start dcrd at boot: [Y/n] " yn
    case $yn in
        [Yy] )
        systemd enable dcrd.service
        ;;
        [Nn]|"" )
        echo "[INFO]You can use command 'systemd enable dcrd.service' to enable it later."
        ;;
    esac
  # Step 3 Generate dcrd.conf
  echo "[INFO]Generating dcrd.conf……"
  echo "externalip=$INTERNET_IPv4" > $CONFIGPATH
  echo "rpcuser=$RPCUSER" >> $CONFIGPATH
  echo "rpcpass=$RPCPASS" >> $CONFIGPATH

  # Step 4 Run dcrd
  echo "[INFO]Running dcrd node program……"
  systemd start dcrd.service
  dcrd_status=$(systemctl status dcrd.service)
  if [[ $str =~ "running" ]]
  then
      echo "[INFO]dcrd is running, Clean tmp files……"
      rm -rf "$TMPDIR"
      echo "[INFO]Install Finished!"
      echo "[INFO]dcrd data directory:$DCRD_DATA_HOME"
      echo "[INFO]dcrd binary directory:$BINARYPATH"
  else
      echo "[ERROR]There is something wrong with running dcrd. info:"
      systemctl status dcrd.service
      exit 1
  fi
}

function upgrade_dcrd() {
  echo "[INFO]stop dcrd node program……"
  systemctl stop dcrd.service
  cd "$TMPDIR"
  ##
  echo "[INFO]starting dcrd node program……"
  dcrd_status=$(systemctl status dcrd.service)
  if [[ $str =~ "running" ]]
  then
      echo "[INFO]dcrd is running, Clean $TMPDIR……"
      rm -rf "$TMPDIR"
  else
      echo "[ERROR]There is something wrong with running dcrd. info:"
      systemctl status dcrd.service
      exit 1
  fi
}

function uninstall_dcrd() {
  echo "[INFO]stop dcrd node program……"
  systemctl stop dcrd.service
  echo "[INFO]disable dcrd node program on boot and delete dcrd.service……"
  systemctl disable dcrd.service
  rm -f /etc/systemd/system/dcrd.service
  echo "[INFO]Delete USER:dcrd/GROUP:dcrd/dcrd's home."
  userdel -r $USER
  groupdel $GROUP
}

check_root
check_os_arch
check_os_resources
install_software
set_env_variables
check_dcrd_env
download_dcrd
install_dcrd