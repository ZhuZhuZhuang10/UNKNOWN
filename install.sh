#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# ---- Разбор входных аргументов ----
ENABLE_XRAY=false
ENABLE_HYSTERIA2=false
NODE_ID=""

for arg in "$@"; do
  case "$arg" in
    --xray)
      ENABLE_XRAY=true
      shift
      ;;
    --hysteria2)
      ENABLE_HYSTERIA2=true
      shift
      ;;
    --[0-9]*)
      NODE_ID="${arg#--}"
      shift
      ;;
    *)
      echo -e "${red}Неизвестный параметр: $arg${plain}"
      exit 1
      ;;
  esac
done
# ---- конец разбора аргументов ----

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}错误：${plain} 必须使用root用户运行此脚本！\n" && exit 1

# check os
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif grep -Eqi "alpine" /etc/issue 2>/dev/null; then
    release="alpine"
elif grep -Eqi "debian" /etc/issue 2>/dev/null; then
    release="debian"
elif grep -Eqi "ubuntu" /etc/issue 2>/dev/null; then
    release="ubuntu"
elif grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux" /etc/issue 2>/dev/null; then
    release="centos"
elif grep -Eqi "debian" /proc/version 2>/dev/null; then
    release="debian"
elif grep -Eqi "ubuntu" /proc/version 2>/dev/null; then
    release="ubuntu"
elif grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux" /proc/version 2>/dev/null; then
    release="centos"
elif grep -Eqi "arch" /proc/version 2>/dev/null; then
    release="arch"
else
    echo -e "${red}未检测到系统版本，请联系脚本作者！${plain}\n" && exit 1
fi

arch=$(uname -m)
if [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]]; then
    arch="64"
elif [[ $arch == "aarch64" || $arch == "arm64" ]]; then
    arch="arm64-v8a"
elif [[ $arch == "s390x" ]]; then
    arch="s390x"
else
    arch="64"
    echo -e "${red}检测架构失败，使用默认架构: ${arch}${plain}"
fi

echo "架构: ${arch}"

if [ "$(getconf WORD_BIT)" != '32' ] && [ "$(getconf LONG_BIT)" != '64' ]; then
    echo "本软件不支持 32 位系统(x86)，请使用 64 位系统(x86_64)。"
    exit 2
fi

# os version
if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
fi
if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
    os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
fi

if [[ x"${release}" == x"centos" ]]; then
    if [[ ${os_version} -le 6 ]]; then
        echo -e "${red}请使用 CentOS 7 或更高版本的系统！${plain}\n" && exit 1
    fi
    if [[ ${os_version} -eq 7 ]]; then
        echo -e "${yellow}注意： CentOS 7 无法使用 hysteria1/2 协议！${plain}\n"
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        echo -e "${red}请使用 Ubuntu 16 或更高版本的系统！${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red}请使用 Debian 8 或更高版本的系统！${plain}\n" && exit 1
    fi
fi

install_base() {
    case "$release" in
      centos)
        yum install epel-release wget curl unzip tar crontabs socat ca-certificates -y
        update-ca-trust force-enable
        ;;
      alpine)
        apk add wget curl unzip tar socat ca-certificates
        update-ca-certificates
        ;;
      debian)
        apt-get update -y
        apt install wget curl unzip tar cron socat ca-certificates -y
        update-ca-certificates
        ;;
      ubuntu)
        apt-get update -y
        apt install wget curl unzip tar cron socat ca-certificates -y
        update-ca-certificates
        ;;
      arch)
        pacman -Sy --noconfirm --needed wget curl unzip tar cron socat ca-certificates
        ;;
    esac
}

# 0: running, 1: not running, 2: not installed
check_status() {
    if [[ ! -f /usr/local/V2bX/V2bX ]]; then
        return 2
    fi
    if [[ x"${release}" == x"alpine" ]]; then
        temp=$(service V2bX status | awk '{print $3}')
        [[ x"${temp}" == x"started" ]] && return 0 || return 1
    else
        temp=$(systemctl status V2bX | grep Active | awk '{print $3}' | tr -d '()')
        [[ x"${temp}" == x"running" ]] && return 0 || return 1
    fi
}

install_V2bX() {
    local node_id="$1"
    local enable_xray="$2"
    local enable_hysteria2="$3"

    # удаляем старую установку
    [[ -d /usr/local/V2bX/ ]] && rm -rf /usr/local/V2bX/
    mkdir -p /usr/local/V2bX/ && cd /usr/local/V2bX/

    # получение и распаковка V2bX
    if [[ $# -eq 0 ]]; then
        last_version=$(curl -Ls "https://api.github.com/repos/wyx2685/V2bX/releases/latest" \
          | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        echo "检测到 V2bX 最新版本：${last_version}"
        url="https://github.com/wyx2685/V2bX/releases/download/${last_version}/V2bX-linux-${arch}.zip"
    else
        last_version="$node_id"
        url="https://github.com/wyx2685/V2bX/releases/download/${last_version}/V2bX-linux-${arch}.zip"
        echo "开始安装 V2bX ${last_version}"
    fi

    wget -q -N --no-check-certificate -O V2bX-linux.zip "$url" \
      || { echo -e "${red}下载失败${plain}"; exit 1; }
    unzip -o V2bX-linux.zip && rm -f V2bX-linux.zip
    chmod +x V2bX
    mkdir -p /etc/V2bX/
    cp geoip.dat geosite.dat /etc/V2bX/

    # Опциональная установка Xray/Hysteria2
    if [[ "$enable_xray" == true ]]; then
        echo "🔧 Устанавливаем Xray..."
        # здесь ваш код по установке Xray
    fi
    if [[ "$enable_hysteria2" == true ]]; then
        echo "🔧 Устанавливаем Hysteria2..."
        # здесь ваш код по установке Hysteria2
    fi

    # настройка systemd/openrc
    if [[ x"${release}" == x"alpine" ]]; then
        cat <<EOF > /etc/init.d/V2bX
#!/sbin/openrc-run
name="V2bX"; description="V2bX"
command="/usr/local/V2bX/V2bX"; command_args="server"
command_user="root"; pidfile="/run/V2bX.pid"; command_background="yes"
depend() { need net; }
EOF
        chmod +x /etc/init.d/V2bX
        rc-update add V2bX default
    else
        wget -q -N --no-check-certificate \
          -O /etc/systemd/system/V2bX.service \
          https://raw.githubusercontent.com/wyx2685/V2bX-script/master/V2bX.service
        systemctl daemon-reload
        systemctl enable V2bX
    fi

    # копирование дефолтных конфигов, запуск сервиса
    cp -n config.json dns.json route.json custom_outbound.json custom_inbound.json /etc/V2bX/
    curl -o /usr/bin/V2bX -Ls https://raw.githubusercontent.com/wyx2685/V2bX-script/master/V2bX.sh
    chmod +x /usr/bin/V2bX && ln -sf /usr/bin/V2bX /usr/bin/v2bx

    # старт/рестарт
    if [[ x"${release}" == x"alpine" ]]; then
        service V2bX start
    else
        systemctl restart V2bX
    fi
    sleep 2 && check_status
    status=$?
    [[ $status -eq 0 ]] && echo -e "${green}V2bX 启动成功${plain}" || echo -e "${red}V2bX 启动失败${plain}"

    cd "$cur_dir"
    rm -f install.sh
}

echo -e "${green}开始安装${plain}"
install_base
install_V2bX "$NODE_ID" "$ENABLE_XRAY" "$ENABLE_HYSTERIA2"
