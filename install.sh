#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}错误：${plain} 必须使用root用户运行此脚本！\n" && exit 1

# check os
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "alpine"; then
    release="alpine"
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux"; then
    release="centos"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux"; then
    release="centos"
elif cat /proc/version | grep -Eqi "arch"; then
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

if [ "$(getconf WORD_BIT)" != '32' ] && [ "$(getconf LONG_BIT)" != '64' ] ; then
    echo "本软件不支持 32 位系统(x86)，请使用 64 位系统(x86_64)，如果检测有误，请联系作者"
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
        echo -e "${red}注意： CentOS 7 无法使用hysteria1/2协议！${plain}\n"
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
    if [[ x"${release}" == x"centos" ]]; then
        yum install epel-release wget curl unzip tar crontabs socat ca-certificates -y
        update-ca-trust force-enable
    elif [[ x"${release}" == x"alpine" ]]; then
        apk add wget curl unzip tar socat ca-certificates
        update-ca-certificates
    elif [[ x"${release}" == x"debian" ]]; then
        apt-get update -y
        apt install wget curl unzip tar cron socat ca-certificates -y
        update-ca-certificates
    elif [[ x"${release}" == x"ubuntu" ]]; then
        apt-get update -y
        apt install wget curl unzip tar cron socat -y
        apt-get install ca-certificates wget -y
        update-ca-certificates
    elif [[ x"${release}" == x"arch" ]]; then
        pacman -Sy
        pacman -S --noconfirm --needed wget curl unzip tar cron socat
        pacman -S --noconfirm --needed ca-certificates wget
    fi
}

# 0: running, 1: not running, 2: not installed
check_status() {
    if [[ ! -f /usr/local/V2bX/V2bX ]]; then
        return 2
    fi
    if [[ x"${release}" == x"alpine" ]]; then
        temp=$(service V2bX status | awk '{print $3}')
        if [[ x"${temp}" == x"started" ]]; then
            return 0
        else
            return 1
        fi
    else
        temp=$(systemctl status V2bX | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
        if [[ x"${temp}" == x"running" ]]; then
            return 0
        else
            return 1
        fi
    fi
}

# Check IPv6 support
check_ipv6_support() {
    if ip -6 addr | grep -q "inet6"; then
        echo "1"
    else
        echo "0"
    fi
}

add_node_config() {
    local core_type=$1
    local NodeID=$2
    local ApiHost=$3
    local ApiKey=$4

    if [ "$core_type" == "--xray" ]; then
        core="xray"
        core_xray=true
        NodeType="vless"
    elif [ "$core_type" == "--hysteria2" ]; then
        core="hysteria2"
        core_hysteria2=true
        NodeType="hysteria2"
    else
        echo -e "${red}无效的核心类型。请选择 --xray 或 --hysteria2。${plain}"
        exit 1
    fi

    if [[ ! "$NodeID" =~ ^[0-9]+$ ]]; then
        echo -e "${red}错误：NodeID 必须为正整数。${plain}"
        exit 1
    fi

    fastopen=true
    if [ "$NodeType" == "hysteria2" ]; then
        fastopen=false
        istls="y"
    fi

    certmode="none"
    certdomain="example.com"
    if [[ "$istls" == "y" || "$istls" == "Y" ]]; then
        certmode="self"
        certdomain="example.com"
    fi

    ipv6_support=$(check_ipv6_support)
    listen_ip="0.0.0.0"
    if [ "$ipv6_support" -eq 1 ]; then
        listen_ip="::"
    fi

    node_config=""
    if [ "$core" == "xray" ]; then
        node_config=$(cat <<EOF
{
    "Core": "$core",
    "ApiHost": "$ApiHost",
    "ApiKey": "$ApiKey",
    "NodeID": $NodeID,
    "NodeType": "$NodeType",
    "Timeout": 30,
    "ListenIP": "0.0.0.0",
    "SendIP": "0.0.0.0",
    "DeviceOnlineMinTraffic": 200,
    "EnableProxyProtocol": false,
    "EnableUot": true,
    "EnableTFO": true,
    "DNSType": "UseIPv4",
    "CertConfig": {
        "CertMode": "$certmode",
        "RejectUnknownSni": false,
        "CertDomain": "$certdomain",
        "CertFile": "/etc/V2bX/fullchain.cer",
        "KeyFile": "/etc/V2bX/cert.key",
        "Email": "v2bx@github.com",
        "Provider": "cloudflare",
        "DNSEnv": {
            "EnvName": "env1"
        }
    }
}
EOF
)
    elif [ "$core" == "hysteria2" ]; then
        node_config=$(cat <<EOF
{
    "Core": "$core",
    "ApiHost": "$ApiHost",
    "ApiKey": "$ApiKey",
    "NodeID": $NodeID,
    "NodeType": "$NodeType",
    "Hysteria2ConfigPath": "/etc/V2bX/hy2config.yaml",
    "Timeout": 30,
    "ListenIP": "",
    "SendIP": "0.0.0.0",
    "DeviceOnlineMinTraffic": 200,
    "CertConfig": {
        "CertMode": "$certmode",
        "RejectUnknownSni": false,
        "CertDomain": "$certdomain",
        "CertFile": "/etc/V2bX/fullchain.cer",
        "KeyFile": "/etc/V2bX/cert.key",
        "Email": "v2bx@github.com",
        "Provider": "cloudflare",
        "DNSEnv": {
            "EnvName": "env1"
        }
    }
}
EOF
)
    fi
    nodes_config+=("$node_config")
}

generate_config_file() {
    local core_type=$1
    local NodeID=$2
    local ApiHost=$3
    local ApiKey=$4

    nodes_config=()
    core_xray=false
    core_hysteria2=false

    add_node_config "$core_type" "$NodeID" "$ApiHost" "$ApiKey"

    cores_config="["
    if [ "$core_xray" = true ]; then
        cores_config+="
    {
        \"Type\": \"xray\",
        \"Log\": {
            \"Level\": \"error\",
            \"ErrorPath\": \"/etc/V2bX/error.log\"
        },
        \"OutboundConfigPath\": \"/etc/V2bX/custom_outbound.json\",
        \"RouteConfigPath\": \"/etc/V2bX/route.json\"
    },"
    fi
    if [ "$core_hysteria2" = true ]; then
        cores_config+="
    {
        \"Type\": \"hysteria2\",
        \"Log\": {
            \"Level\": \"error\"
        }
    },"
    fi
    cores_config+="]"
    cores_config=$(echo "$cores_config" | sed 's/},]$/}]/')

    cd /etc/V2bX || { echo -e "${red}无法切换到 /etc/V2bX 目录！${plain}"; exit 1; }
    mv config.json config.json.bak 2>/dev/null || true
    nodes_config_str="${nodes_config[*]}"
    formatted_nodes_config="${nodes_config_str%,}"

    cat <<EOF > /etc/V2bX/config.json
{
    "Log": {
        "Level": "error",
        "Output": ""
    },
    "Cores": $cores_config,
    "Nodes": [$formatted_nodes_config]
}
EOF

    cat <<EOF > /etc/V2bX/custom_outbound.json
[
    {
        "tag": "IPv4_out",
        "protocol": "freedom",
        "settings": {
            "domainStrategy": "UseIPv4v6"
        }
    },
    {
        "tag": "IPv6_out",
        "protocol": "freedom",
        "settings": {
            "domainStrategy": "UseIPv6"
        }
    },
    {
        "protocol": "blackhole",
        "tag": "block"
    }
]
EOF

    cat <<EOF > /etc/V2bX/route.json
{
    "domainStrategy": "AsIs",
    "rules": [
        {
            "outboundTag": "block",
            "ip": [
                "geoip:private"
            ]
        },
        
        {
            "outboundTag": "block",
            "ip": [
                "127.0.0.1/32",
                "10.0.0.0/8",
                "fc00::/7",
                "fe80::/10",
                "172.16.0.0/12"
            ]
        },
        {
            "outboundTag": "block",
            "protocol": [
                "bittorrent"
            ]
        },
        {
            "outboundTag": "IPv4_out",
            "network": "udp,tcp"
        }
    ]
}
EOF

    if [ "$core_hysteria2" = true ]; then
        cat <<EOF > /etc/V2bX/hy2config.yaml
quic:
  initStreamReceiveWindow: 16777216
  maxStreamReceiveWindow: 16777216
  initConnReceiveWindow: 67108864
  maxConnReceiveWindow: 67108864
  maxIdleTimeout: 60s
  maxIncomingStreams: 2048
  disablePathMTUDiscovery: false

ignoreClientBandwidth: false
disableUDP: false
udpIdleTimeout: 60s
resolver:
  type: system
acl:
  inline:
    - direct(geosite:google)
masquerade:
  type: 404
EOF
    fi

    echo -e "${green}V2bX 配置文件生成完成,正在 перезапускаем службу${plain}"
    if [[ x"${release}" == x"alpine" ]]; then
        service V2bX restart
    else
        systemctl restart V2bX
    fi
}

install_V2bX() {
    local version=""
    local core_type=""
    local node_id=""
    local api_host=""
    local api_key=""

    # Debug output for arguments
    echo -e "${yellow}Полученные аргументы: $@${plain}"

    # Parse command-line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --xray|--hysteria2)
                core_type="$1"
                shift
                ;;
            --[0-9]*)
                node_id="${1/--/}"
                shift
                ;;
            --api)
                if [[ -n "$2" && "$2" != --* ]]; then
                    api_host="$2"
                    shift 2
                else
                    echo -e "${red}Ошибка: --api требует URL (например, https://core2.bibihy.top)${plain}"
                    exit 1
                fi
                ;;
            --apikey)
                if [[ -n "$2" && "$2" != --* ]]; then
                    api_key="$2"
                    shift 2
                else
                    echo -e "${red}Ошибка: --apikey требует значение ключа${plain}"
                    exit 1
                fi
                ;;
            *)
                if [[ "$1" != --* ]]; then
                    version="$1"
                    shift
                else
                    echo -e "${red}Неизвестный аргумент: $1${plain}"
                    exit 1
                fi
                ;;
        esac
    done

    # Validate arguments
    if [[ -n "$core_type" && -n "$node_id" && -n "$api_host" && -n "$api_key" ]]; then
        echo -e "${yellow}Параметры: core_type=$core_type, node_id=$node_id, api_host=$api_host, api_key=$api_key${plain}"
    elif [[ -n "$core_type" || -n "$node_id" || -n "$api_host" || -n "$api_key" ]]; then
        echo -e "${red}Ошибка: Необходимо указать все параметры (--xray или --hysteria2, --<nodeid>, --api, --apikey)${plain}"
        exit 1
    fi

    if [[ -e /usr/local/V2bX/ ]]; then
        rm -rf /usr/local/V2bX/
    fi

    mkdir /usr/local/V2bX/ -p
    cd /usr/local/V2bX/

    if [[ -z "$version" ]]; then
        last_version=$(curl -Ls "https://api.github.com/repos/wyx2685/V2bX/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$last_version" ]]; then
            echo -e "${red}检测 V2bX 版本失败，可能是超出 Github API 限制，请稍后再试，或手动 указать V2bX 版本安装${plain}"
            exit 1
        fi
        echo -e "检测到 V2bX 最新版本：${last_version}，开始安装"
        wget -q -N --no-check-certificate -O /usr/local/V2bX/V2bX-linux.zip https://github.com/wyx2685/V2bX/releases/download/${last_version}/V2bX-linux-${arch}.zip
    else
        last_version=$version
        url="https://github.com/wyx2685/V2bX/releases/download/${last_version}/V2bX-linux-${arch}.zip"
        echo -e "开始安装 V2bX $version"
        wget -q -N --no-check-certificate -O /usr/local/V2bX/V2bX-linux.zip ${url}
    fi

    if [[ $? -ne 0 ]]; then
        echo -e "${red}下载 V2bX 失败，请确保 ваш сервер может скачать файлы с Github${plain}"
        exit 1
    fi

    unzip V2bX-linux.zip
    rm V2bX-linux.zip -f
    chmod +x V2bX
    mkdir /etc/V2bX/ -p
    cp geoip.dat /etc/V2bX/
    cp geosite.dat /etc/V2bX/

    if [[ x"${release}" == x"alpine" ]]; then
        rm /etc/init.d/V2bX -f
        cat <<EOF > /etc/init.d/V2bX
#!/sbin/openrc-run

name="V2bX"
description="V2bX"

command="/usr/local/V2bX/V2bX"
command_args="server"
command_user="root"

pidfile="/run/V2bX.pid"
command_background="yes"

depend() {
        need net
}
EOF
        chmod +x /etc/init.d/V2bX
        rc-update add V2bX default
    else
        rm /etc/systemd/system/V2bX.service -f
        file="https://github.com/wyx2685/V2bX-script/raw/master/V2bX.service"
        wget -q -N --no-check-certificate -O /etc/systemd/system/V2bX.service ${file}
        systemctl daemon-reload
        systemctl stop V2bX
        systemctl enable V2bX
    fi

    echo -e "${green}V2bX ${last_version}${plain} 安装完成，已设置开机自启"

    # Handle configuration based on arguments
    if [[ -n "$core_type" && -n "$node_id" && -n "$api_host" && -n "$api_key" ]]; then
        cp config.json /etc/V2bX/ 2>/dev/null || true
        cp dns.json /etc/V2bX/ 2>/dev/null || true
        cp route.json /etc/V2bX/ 2>/dev/null || true
        cp custom_outbound.json /etc/V2bX/ 2>/dev/null || true
        cp custom_inbound.json /etc/V2bX/ 2>/dev/null || true
        generate_config_file "$core_type" "$node_id" "$api_host" "$api_key"
    else
        # Default behavior if no arguments are provided
        if [[ ! -f /etc/V2bX/config.json ]]; then
            cp config.json /etc/V2bX/
            echo -e ""
            echo -e "全新安装，请先参看教程：https://v2bx.v-50.me/，配置必要的内容"
            first_install=true
        else
            if [[ x"${release}" == x"alpine" ]]; then
                service V2bX start
            else
                systemctl start V2bX
            fi
            sleep 2
            check_status
            if [[ $? == 0 ]]; then
                echo -e "${green}V2bX 重启成功${plain}"
            else
                echo -e "${red}V2bX 可能启动失败，请稍后使用 V2bX log 查看日志信息，若无法启动，则可能更改了配置格式，请前往 wiki 查看：https://github.com/V2bX-project/V2bX/wiki${plain}"
            fi
            first_install=false
        fi
        cp dns.json /etc/V2bX/ 2>/dev/null || true
        cp route.json /etc/V2bX/ 2>/dev/null || true
        cp custom_outbound.json /etc/V2bX/ 2>/dev/null || true
        cp custom_inbound.json /etc/V2bX/ 2>/dev/null || true
    fi

    curl -o /usr/bin/V2bX -Ls https://raw.githubusercontent.com/wyx2685/V2bX-script/master/V2bX.sh
    chmod +x /usr/bin/V2bX
    if [ ! -L /usr/bin/v2bx ]; then
        ln -s /usr/bin/V2bX /usr/bin/v2bx
        chmod +x /usr/bin/v2bx
    fi
    cd $cur_dir
    rm -f install.sh
    echo -e ""
    echo "V2bX 管理脚本使用方法 (兼容使用V2bX执行，大小写不敏感): "
    echo "------------------------------------------"
    echo "V2bX              - 显示管理菜单 (功能更多)"
    echo "V2bX start        - 启动 V2bX"
    echo "V2bX stop         - 停止 V2bX"
    echo "V2bX restart      - 重启 V2bX"
    echo "V2bX status       - 查看 V2bX 状态"
    echo "V2bX enable       - 设置 V2bX 开机自启"
    echo "V2bX disable      - 取消 V2bX 开机自启"
    echo "V2bX log          - 查看 V2bX 日志"
    echo "V2bX x25519       - 生成 x25519 密钥"
    echo "V2bX generate     - 生成 V2bX 配置文件"
    echo "V2bX update       - 更新 V2bX"
    echo "V2bX update x.x.x - 更新 V2bX 指定版本"
    echo "V2bX install      - 安装 V2bX"
    echo "V2bX uninstall    - 卸载 V2bX"
    echo "V2bX version      - 查看 V2bX 版本"
    echo "------------------------------------------"
}

echo -e "${green}开始安装${plain}"
install_base
install_V2bX "$@"
