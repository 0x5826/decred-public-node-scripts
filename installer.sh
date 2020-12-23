#!/bin/bash
set -euo pipefail

if [[ $(id -u) != 0 ]]; then
  echo "[ERROR]Please run this script as root."
  exit 1
fi

function prompt() {
    while true; do
        read -p "$1 [y/N] " yn
        case $yn in
            [Yy] ) return 0;;
            [Nn]|"" ) return 1;;
        esac
    done
}
USER="dcrd"
GROUP="dcrd"
DCRD_USER_HOME="/home/$USER"
DCRD_DATA_HOME="/home/$USER/.dcrd"
BINARYDIR="$DCRD_USER_HOME/decred"
BINARYPATH="$DCRD_USER_HOME/decred/dcrd"
CONFIGPATH="$DCRD_USER_HOME/.dcrd/dcrd.conf"
TMPDIR="$(mktemp -d)"
INTERFACE_IPv4=$(ifconfig -a|grep inet|grep -v 127.0.0.1|grep -v inet6|awk '{print $2}'|tr -d "addr:")
INTERNET_IPv4=$(curl -s ipv4.ip.sb)
VERSION=$(curl -fsSL https://api.github.com/repos/decred/decred-binaries/releases/latest | grep tag_name | sed -E 's/.*"v(.*)".*/\1/')
TARBALL="decred-linux-$MACHINE-v$VERSION.tar.gz"
DOWNLOADURL="https://github.com/decred/decred-binaries/releases/download/v$VERSION/$TARBALL"
SERVICEURL="https://raw.githubusercontent.com/decred/dcrd/master/contrib/services/systemd/dcrd.service"

function check_environment() {
  egrep "^$GROUP" /etc/group >& /dev/null
  if [ $? -eq 0 ]
  then
    echo "[WARN]Found user: dcrd."
  fi

  egrep "^$USER" /etc/passwd >& /dev/null
  if [ $? -eq 0 ]
  then
    echo "[WARN]Found group: dcrd."
  fi

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

  dcrd_port=$(netstat -an | grep ":9108 " | awk '$1 == "tcp" && $NF == "LISTEN" {print $0}')
  if [ -n "$dcrd_port" ]
  then
    echo "[ERROR]Found another program listening 9108 Port."
    exit 1
  fi

  if [ $INTERFACE_IPv4 -ne $INTERNET_IPv4 ]
  then
    echo "[WARN]Your interface IP:$interface_ipv4 and Internet IP:$internet_ipv4 are inconsistent, some conditions refer to $knowsurl"
    echo "[WARN]Dcrd Node will use Internet IP for externalIP."
  fi
}

function download_dcrd() {
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
  fi

  if [[ ! -f '/etc/os-release' ]]; then
    echo "[ERROR]Don't use outdated Linux distributions."
    exit 1
  fi

  cd "$TMPDIR"
  echo "[INFO]Downloading $TARBALL..."
  curl -LO --progress-bar "$DOWNLOADURL" || wget -q --show-progress "$DOWNLOADURL"
  echo "[INFO]Unpacking $TARBALL..."
  tar zxf "$TARBALL"
  echo "[INFO]Downloading dcrd.service..."
  curl -LO --progress-bar "$SERVICEURL" || wget -q --show-progress "$SERVICEURL"
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
  cp -f "$TMPDIR/decred-linux-$MACHINE-v$VERSION/dcrd" $BINARYPATH && chown dcrd:dcrd $BINARYPATH &&chmod a+x $BINARYPATH
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
  echo "externalip=$INTERNET_IPv4" >> $CONFIGPATH

# Step 4 Run dcrd.conf
  echo "[INFO]Running dcrd node program……"
  systemd start dcrd.service
  dcrd_status=$(systemctl status dcrd.service)
  if [[ $str =~ "running" ]]
  then
      echo "[INFO]dcrd is running, Clean tmp files……"
      rm -rf "$TMPDIR"
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
  echo "[INFO]Downloading $TARBALL..."
  curl -LO --progress-bar "$DOWNLOADURL" || wget -q --show-progress "$DOWNLOADURL"
  echo "[INFO]Unpacking $TARBALL..."
  tar zxf "$TARBALL"
  cp -f "$TMPDIR/decred-linux-$MACHINE-v$VERSION/dcrd" $BINARYPATH && chown dcrd:dcrd $BINARYPATH &&chmod a+x $BINARYPATH
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