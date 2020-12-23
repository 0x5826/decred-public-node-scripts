#!/bin/bash
set -euo pipefail

function prompt() {
    while true; do
        read -p "$1 [y/N] " yn
        case $yn in
            [Yy] ) return 0;;
            [Nn]|"" ) return 1;;
        esac
    done
}

function check_environment() {
  if [[ $(id -u) != 0 ]]; then
    echo "[ERROR]Please run this script as root!"
    exit 1
  fi

  egrep "^$GROUP" /etc/group >& /dev/null
  if [ $? -eq 0 ]
  then
    echo "[WARN]Found user: dcrd!"
  fi
  
  egrep "^$USER" /etc/passwd >& /dev/null
  if [ $? -eq 0 ]
  then
    echo "[WARN]Found group: dcrd!"
  fi

  free_mem=$(free -m|awk 'NR==2' |awk '{print$7}')
  if [ $free_mem -lt 768 ]
  then 
    echo "[ERROR]The memory request for 760MB at least"
    exit 1
  fi

  free_disk=$(df -B G /|awk '/\//{print$4}' | awk '{sub(/.{1}$/,"")}1' | sed 's/G//')
  if [ $free_disk -lt 8 ]
  then 
    echo "[ERROR]The disk request for 8GB at least"
    exit 1
  fi

  dcrd_port=$(netstat -an | grep ":9108 " | awk '$1 == "tcp" && $NF == "LISTEN" {print $0}')
  if [ -n $dcrd_port ]
  then
    echo "[ERROR]Found another program listening 9108 Port!"
    exit 1
  fi
}

function identify_os_and_architecture() {
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
        echo "error: The architecture is not supported."
        exit 1
        ;;
    esac
    if [[ ! -f '/etc/os-release' ]]; then
      echo "error: Don't use outdated Linux distributions."
      exit 1
    fi

# Last binary
VERSION=$(curl -fsSL https://api.github.com/repos/decred/decred-binaries/releases/latest | grep tag_name | sed -E 's/.*"v(.*)".*/\1/')
TARBALL="decred-linux-$MACHINE-$VERSION.tar.gz"
DOWNLOADURL="https://github.com/decred/decred-binaries/releases/download/v$VERSION/$TARBALL"
TMPDIR="$(mktemp -d)"

# Environment
USER="dcrd"
GROUP="dcrd"
DCRD_HOME="/home/$USER"
BINARYPATH="$DCRD_HOME/decred/dcrd"
CONFIGPATH="$DCRD_HOME/.dcrd/dcrd.conf"
