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

if [[ $(id -u) != 0 ]]; then
    echo Please run this script as root.
    exit 1
fi

identify_os_and_architecture() {
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
VERSION=$(curl -fsSL https://api.github.com/repos/decred/decred-binaries/releases/latest | grep tag_name | sed -E 's/.*"v(.*)".*/\1/')
TARBALL="decred-linux-$MACHINE-$VERSION.tar.gz"
DOWNLOADURL="https://github.com/decred/decred-binaries/releases/download/v$VERSION/$TARBALL"
TMPDIR="$(mktemp -d)"

DCRD_HOME="/home/decred"
BINARYPATH="$DCRD_HOME/decred/dcrd"
CONFIGPATH="$DCRD_HOME/.dcrd/dcrd.conf"

#检查是否存在用户、进程和端口
#检查磁盘、内存和IP是否符合公共节点条件

#创建用户/用户组
#下载二进制文件并拷贝到$BINARYPATH
#下载systemd服务配置文件
#