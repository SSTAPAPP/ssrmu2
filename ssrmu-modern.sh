#!/usr/bin/env bash
set -Eeuo pipefail

PATH=/usr/local/bin:/usr/local/sbin:/bin:/sbin:/usr/bin:/usr/sbin:~/bin
export PATH

VERSION="0.1.0"
SSR_DIR="/usr/local/shadowsocksr"
SSR_ZIP_URL="${SSR_ZIP_URL:-https://github.com/ToyoDAdoubiBackup/shadowsocksr/archive/manyuser.zip}"
PY2_PREFIX="${PY2_PREFIX:-/opt/python2.7}"
PY2_BIN="${PY2_PREFIX}/bin/python2.7"
PYTHON_LINK="/usr/local/bin/python"
INIT_FILE="/etc/init.d/ssrmu"
LOG_FILE="${SSR_DIR}/ssserver.log"
MUDB_FILE="${SSR_DIR}/mudb.json"
API_FILE="${SSR_DIR}/userapiconfig.py"

info(){ echo -e "\033[32m[INFO]\033[0m $*"; }
warn(){ echo -e "\033[33m[WARN]\033[0m $*" >&2; }
err(){ echo -e "\033[31m[ERROR]\033[0m $*" >&2; }
fatal(){ err "$*"; exit 1; }
exists(){ command -v "$1" >/dev/null 2>&1; }

require_root(){ [[ ${EUID} -eq 0 ]] || fatal "please run as root"; }

load_os(){
  OS_ID="unknown"; OS_LIKE=""
  if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_LIKE="${ID_LIKE:-}"
  fi
}

is_debian_like(){ [[ "${OS_ID} ${OS_LIKE}" == *debian* || "${OS_ID} ${OS_LIKE}" == *ubuntu* ]]; }
is_rhel_like(){ [[ "${OS_ID} ${OS_LIKE}" == *rhel* || "${OS_ID} ${OS_LIKE}" == *fedora* || "${OS_ID} ${OS_LIKE}" == *centos* || "${OS_ID} ${OS_LIKE}" == *rocky* || "${OS_ID} ${OS_LIKE}" == *alma* ]]; }

install_base_deps(){
  if is_debian_like; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y --no-install-recommends wget curl ca-certificates unzip cron iptables net-tools procps sed grep gawk coreutils tar gzip xz-utils vim-tiny || true
  elif is_rhel_like; then
    local pm="yum"; exists dnf && pm="dnf"
    ${pm} -y makecache || true
    ${pm} -y install wget curl ca-certificates unzip cronie iptables iptables-services net-tools procps-ng sed grep gawk coreutils tar gzip xz vim-minimal || true
  else
    warn "unknown OS ${OS_ID}; trying apt-compatible dependency install"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update || true
    apt-get install -y --no-install-recommends wget curl ca-certificates unzip cron iptables net-tools procps sed grep gawk coreutils tar gzip xz-utils vim-tiny || true
  fi
  exists wget || fatal "wget is required"
  exists unzip || fatal "unzip is required"
  mkdir -p /etc/network/if-pre-up.d /etc/iptables /etc/systemd/system /usr/local/bin
}

python_is_py2(){
  local bin="$1"
  [[ -x "${bin}" || -n "$(command -v "${bin}" 2>/dev/null)" ]] || return 1
  "${bin}" - <<'PY' >/dev/null 2>&1
import sys
raise SystemExit(0 if sys.version_info[0] == 2 else 1)
PY
}

find_python2(){
  local c r
  for c in python python2.7 python2 /usr/bin/python2.7 /usr/local/bin/python2.7 "${PY2_BIN}"; do
    if exists "${c}"; then
      r="$(command -v "${c}")"
      python_is_py2 "${r}" && echo "${r}" && return 0
    elif [[ -x "${c}" ]]; then
      python_is_py2 "${c}" && echo "${c}" && return 0
    fi
  done
  return 1
}

link_python2(){
  local py2="$1"
  ln -sf "${py2}" /usr/local/bin/python
  ln -sf "${py2}" /usr/local/bin/python2
  ln -sf "${py2}" /usr/local/bin/python2.7
  info "Python runtime: $(/usr/local/bin/python --version 2>&1)"
}

install_python2_archive(){
  is_debian_like || return 1
  info "Trying Debian bullseye archive for Python 2.7..."
  local src="/etc/apt/sources.list.d/ssrmu2-python2-bullseye.list"
  local pref="/etc/apt/preferences.d/ssrmu2-python2-bullseye"
  cat >"${src}" <<'EOF'
deb http://archive.debian.org/debian bullseye main
EOF
  cat >"${pref}" <<'EOF'
Package: *
Pin: release n=bullseye
Pin-Priority: 100
EOF
  apt-get -o Acquire::Check-Valid-Until=false update || true
  DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::Check-Valid-Until=false install -y --no-install-recommends python2.7-minimal python2.7 || true
  rm -f "${src}" "${pref}"
  apt-get update || true
  find_python2 >/dev/null 2>&1
}

build_python2(){
  info "Building Python 2.7.18 under ${PY2_PREFIX}; this can take a few minutes..."
  if is_debian_like; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y --no-install-recommends build-essential wget ca-certificates tar gzip make gcc zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev libffi-dev xz-utils || true
  else
    local pm="yum"; exists dnf && pm="dnf"
    ${pm} -y groupinstall "Development Tools" || true
    ${pm} -y install gcc make wget tar gzip zlib-devel bzip2-devel readline-devel sqlite-devel libffi-devel xz-devel || true
  fi
  mkdir -p /usr/local/src
  cd /usr/local/src
  wget --no-check-certificate -O Python-2.7.18.tgz https://www.python.org/ftp/python/2.7.18/Python-2.7.18.tgz
  rm -rf Python-2.7.18
  tar -xzf Python-2.7.18.tgz
  cd Python-2.7.18
  ./configure --prefix="${PY2_PREFIX}" --enable-shared
  make -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)"
  make altinstall
  echo "${PY2_PREFIX}/lib" >/etc/ld.so.conf.d/python2.7-local.conf
  ldconfig || true
}

ensure_python2(){
  local py2
  if py2="$(find_python2 2>/dev/null)"; then link_python2 "${py2}"; return 0; fi

  if is_debian_like; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y --no-install-recommends python2.7 python2 || true
  elif is_rhel_like; then
    local pm="yum"; exists dnf && pm="dnf"
    ${pm} -y install python2 python2-libs || ${pm} -y install python27 || true
  fi

  if py2="$(find_python2 2>/dev/null)"; then link_python2 "${py2}"; return 0; fi
  if install_python2_archive && py2="$(find_python2 2>/dev/null)"; then link_python2 "${py2}"; return 0; fi
  build_python2
  py2="$(find_python2 2>/dev/null)" || fatal "unable to prepare Python 2.7"
  link_python2 "${py2}"
}

fetch_ip(){
  local ip=""
  ip="$(wget -qO- -t1 -T2 ipinfo.io/ip 2>/dev/null || true)"
  [[ -z "${ip}" ]] && ip="$(wget -qO- -t1 -T2 api.ip.sb/ip 2>/dev/null || true)"
  [[ -z "${ip}" ]] && ip="$(wget -qO- -t1 -T2 members.3322.org/dyndns/getip 2>/dev/null || true)"
  [[ -z "${ip}" ]] && ip="VPS_IP"
  echo "${ip}"
}

install_ssr_files(){
  [[ -e "${SSR_DIR}" ]] && fatal "${SSR_DIR} already exists; uninstall first or move it away"
  info "Downloading SSR manyuser server..."
  cd /usr/local
  rm -rf manyuser.zip shadowsocksr-manyuser
  wget --no-check-certificate -O manyuser.zip "${SSR_ZIP_URL}"
  unzip -q manyuser.zip
  [[ -d /usr/local/shadowsocksr-manyuser ]] || fatal "SSR archive extraction failed"
  mv /usr/local/shadowsocksr-manyuser "${SSR_DIR}"
  rm -f manyuser.zip
  cd "${SSR_DIR}"
  cp config.json user-config.json
  cp mysql.json usermysql.json
  cp apiconfig.py userapiconfig.py
  sed -i "s/API_INTERFACE = 'sspanelv2'/API_INTERFACE = 'mudbjson'/" userapiconfig.py
  sed -i 's/ \/\/ only works under multi-user mode//g' user-config.json
  if [[ -x jq-linux64 && "$(uname -m)" == "x86_64" ]]; then mv jq-linux64 jq; elif [[ -x jq-linux32 ]]; then mv jq-linux32 jq; fi
  [[ -f jq ]] && chmod +x jq || true
}

set_server_pub_addr(){
  local addr="$1"
  [[ -f "${API_FILE}" ]] || return 0
  sed -i "s/SERVER_PUB_ADDR = '127.0.0.1'/SERVER_PUB_ADDR = '${addr}'/" "${API_FILE}"
}

write_init_script(){
  cat >"${INIT_FILE}" <<'EOF'
#!/bin/bash
### BEGIN INIT INFO
# Provides:          ShadowsocksR
# Required-Start:    $network $local_fs $remote_fs
# Required-Stop:     $network $local_fs $remote_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: ShadowsocksR mudbjson server
### END INIT INFO

NAME="ShadowsocksR"
FOLDER="/usr/local/shadowsocksr"
BIN="/usr/local/shadowsocksr/server.py"
PYTHON="/usr/local/bin/python"
LOG="/usr/local/shadowsocksr/ssserver.log"

pidof_ssr(){ ps -ef | grep server.py | grep -v grep | grep -v init.d | awk '{print $2}'; }

case "$1" in
  start)
    PID="$(pidof_ssr)"
    [[ -n "$PID" ]] && echo "[INFO] $NAME already running: $PID" && exit 0
    cd "$FOLDER" || exit 1
    ulimit -n 512000
    nohup "$PYTHON" "$BIN" a >> "$LOG" 2>&1 &
    sleep 2
    PID="$(pidof_ssr)"
    [[ -n "$PID" ]] && echo "[INFO] $NAME started: $PID" || { echo "[ERROR] $NAME start failed"; exit 1; }
    ;;
  stop)
    PID="$(pidof_ssr)"
    [[ -z "$PID" ]] && echo "[INFO] $NAME is not running" && exit 1
    kill -9 $PID
    echo "[INFO] $NAME stopped"
    ;;
  restart)
    "$0" stop || true
    "$0" start
    ;;
  status)
    PID="$(pidof_ssr)"
    [[ -n "$PID" ]] && echo "[INFO] $NAME running: $PID" || { echo "[INFO] $NAME is not running"; exit 1; }
    ;;
  *)
    echo "Usage: $0 {start|stop|restart|status}"
    exit 1
    ;;
esac
EOF
  chmod +x "${INIT_FILE}"
  update-rc.d -f ssrmu defaults >/dev/null 2>&1 || true
  if exists systemctl; then systemctl daemon-reload >/dev/null 2>&1 || true; fi
}

iptables_rule(){
  local bin="$1" action="$2" proto="$3" port="$4"
  exists "${bin}" || return 0
  if [[ "${action}" == add ]]; then
    "${bin}" -C INPUT -m state --state NEW -m "${proto}" -p "${proto}" --dport "${port}" -j ACCEPT >/dev/null 2>&1 || \
    "${bin}" -I INPUT -m state --state NEW -m "${proto}" -p "${proto}" --dport "${port}" -j ACCEPT >/dev/null 2>&1 || true
  else
    while "${bin}" -C INPUT -m state --state NEW -m "${proto}" -p "${proto}" --dport "${port}" -j ACCEPT >/dev/null 2>&1; do
      "${bin}" -D INPUT -m state --state NEW -m "${proto}" -p "${proto}" --dport "${port}" -j ACCEPT >/dev/null 2>&1 || break
    done
  fi
}

save_iptables(){
  iptables-save >/etc/iptables.up.rules 2>/dev/null || true
  ip6tables-save >/etc/ip6tables.up.rules 2>/dev/null || true
  cat >/etc/network/if-pre-up.d/iptables <<'EOF'
#!/bin/bash
test -s /etc/iptables.up.rules && command -v iptables-restore >/dev/null 2>&1 && iptables-restore < /etc/iptables.up.rules || true
test -s /etc/ip6tables.up.rules && command -v ip6tables-restore >/dev/null 2>&1 && ip6tables-restore < /etc/ip6tables.up.rules || true
EOF
  chmod +x /etc/network/if-pre-up.d/iptables
  if exists systemctl; then
    cat >/etc/systemd/system/ssr-iptables-restore.service <<'EOF'
[Unit]
Description=Restore iptables rules for ShadowsocksR
DefaultDependencies=no
Before=network-pre.target
Wants=network-pre.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'test -s /etc/iptables.up.rules && command -v iptables-restore >/dev/null 2>&1 && iptables-restore < /etc/iptables.up.rules || true; test -s /etc/ip6tables.up.rules && command -v ip6tables-restore >/dev/null 2>&1 && ip6tables-restore < /etc/ip6tables.up.rules || true'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl enable ssr-iptables-restore.service >/dev/null 2>&1 || true
  fi
}

add_firewall_port(){
  local port="$1"
  iptables_rule iptables add tcp "${port}"
  iptables_rule iptables add udp "${port}"
  iptables_rule ip6tables add tcp "${port}"
  iptables_rule ip6tables add udp "${port}"
  save_iptables
}

choose_method(){
  echo "请选择加密方式:"
  echo " 1 none  2 rc4  3 rc4-md5  4 rc4-md5-6"
  echo " 5 aes-128-ctr  6 aes-192-ctr  7 aes-256-ctr"
  echo " 8 aes-128-cfb  9 aes-192-cfb  10 aes-256-cfb"
  echo " 14 salsa20  15 chacha20  16 chacha20-ietf"
  read -r -p "(默认: 5 aes-128-ctr): " x; x="${x:-5}"
  case "$x" in
    1) echo none;; 2) echo rc4;; 3) echo rc4-md5;; 4) echo rc4-md5-6;; 5) echo aes-128-ctr;; 6) echo aes-192-ctr;; 7) echo aes-256-ctr;;
    8) echo aes-128-cfb;; 9) echo aes-192-cfb;; 10) echo aes-256-cfb;; 14) echo salsa20;; 15) echo chacha20;; 16) echo chacha20-ietf;; *) echo aes-128-ctr;;
  esac
}

choose_protocol(){
  echo "请选择协议插件:"
  echo " 1 origin  2 auth_sha1_v4  3 auth_aes128_md5  4 auth_aes128_sha1  5 auth_chain_a  6 auth_chain_b"
  read -r -p "(默认: 3 auth_aes128_md5): " x; x="${x:-3}"
  case "$x" in
    1) echo origin;; 2) echo auth_sha1_v4;; 3) echo auth_aes128_md5;; 4) echo auth_aes128_sha1;; 5) echo auth_chain_a;; 6) echo auth_chain_b;; *) echo auth_aes128_md5;;
  esac
}

choose_obfs(){
  echo "请选择混淆插件:"
  echo " 1 plain  2 http_simple  3 http_post  4 random_head  5 tls1.2_ticket_auth"
  read -r -p "(默认: 1 plain): " x; x="${x:-1}"
  local obfs
  case "$x" in
    1) obfs=plain;; 2) obfs=http_simple;; 3) obfs=http_post;; 4) obfs=random_head;; 5) obfs=tls1.2_ticket_auth;; *) obfs=plain;;
  esac
  if [[ "${obfs}" != plain ]]; then
    read -r -p "是否设置混淆兼容原版(_compatible)? [Y/n]: " yn; yn="${yn:-y}"
    [[ "${yn}" =~ ^[Yy]$ ]] && obfs="${obfs}_compatible"
  fi
  echo "${obfs}"
}

prompt_user(){
  read -r -p "用户名(默认: doubi): " SSR_USER; SSR_USER="${SSR_USER:-doubi}"; SSR_USER="${SSR_USER// /}"
  read -r -p "端口(默认: 2333): " SSR_PORT; SSR_PORT="${SSR_PORT:-2333}"
  [[ "${SSR_PORT}" =~ ^[0-9]+$ && "${SSR_PORT}" -ge 1 && "${SSR_PORT}" -le 65535 ]] || fatal "invalid port"
  read -r -p "密码(默认: doub.io): " SSR_PASS; SSR_PASS="${SSR_PASS:-doub.io}"
  SSR_METHOD="$(choose_method)"
  SSR_PROTOCOL="$(choose_protocol)"
  SSR_OBFS="$(choose_obfs)"
  read -r -p "设备数限制(默认: 无限): " SSR_PROTOCOL_PARAM; SSR_PROTOCOL_PARAM="${SSR_PROTOCOL_PARAM:-}"
  read -r -p "单线程限速 KB/s(默认: 无限): " SSR_SPEED_CON; SSR_SPEED_CON="${SSR_SPEED_CON:-0}"
  read -r -p "用户总限速 KB/s(默认: 无限): " SSR_SPEED_USER; SSR_SPEED_USER="${SSR_SPEED_USER:-0}"
  read -r -p "总流量 GB(默认: 无限): " SSR_TRANSFER; SSR_TRANSFER="${SSR_TRANSFER:-838868}"
  read -r -p "禁止访问端口(默认: 空): " SSR_FORBID; SSR_FORBID="${SSR_FORBID:-}"
}

add_user(){
  [[ -d "${SSR_DIR}" ]] || fatal "SSR is not installed"
  prompt_user
  cd "${SSR_DIR}"
  if /usr/local/bin/python mujson_mgr.py -l | grep -w "port ${SSR_PORT}$" >/dev/null 2>&1; then fatal "port ${SSR_PORT} already exists"; fi
  if /usr/local/bin/python mujson_mgr.py -l | grep -w "user \[${SSR_USER}]" >/dev/null 2>&1; then fatal "user ${SSR_USER} already exists"; fi
  /usr/local/bin/python mujson_mgr.py -a -u "${SSR_USER}" -p "${SSR_PORT}" -k "${SSR_PASS}" -m "${SSR_METHOD}" -O "${SSR_PROTOCOL}" -G "${SSR_PROTOCOL_PARAM}" -o "${SSR_OBFS}" -s "${SSR_SPEED_CON}" -S "${SSR_SPEED_USER}" -t "${SSR_TRANSFER}" -f "${SSR_FORBID}"
  add_firewall_port "${SSR_PORT}"
  info "User added: ${SSR_USER} port ${SSR_PORT} method ${SSR_METHOD} protocol ${SSR_PROTOCOL} obfs ${SSR_OBFS}"
}

list_users(){
  [[ -d "${SSR_DIR}" ]] || fatal "SSR is not installed"
  cd "${SSR_DIR}"
  /usr/local/bin/python mujson_mgr.py -l || true
}

install_all(){
  require_root; load_os; info "OS: ${OS_ID} ${OS_LIKE}"
  install_base_deps
  ensure_python2
  install_ssr_files
  read -r -p "用户配置中显示的服务器IP或域名(默认自动检测): " pub; pub="${pub:-$(fetch_ip)}"
  set_server_pub_addr "${pub}"
  write_init_script
  add_user
  "${INIT_FILE}" start
  info "Install finished. Run: ${INIT_FILE} status"
}

uninstall_all(){
  require_root
  [[ -x "${INIT_FILE}" ]] && "${INIT_FILE}" stop || true
  update-rc.d -f ssrmu remove >/dev/null 2>&1 || true
  rm -rf "${SSR_DIR}" "${INIT_FILE}"
  info "SSR removed. Python2 compatibility runtime was kept intentionally."
}

show_status(){
  [[ -x "${INIT_FILE}" ]] && "${INIT_FILE}" status || fatal "service is not installed"
}

view_log(){
  [[ -f "${LOG_FILE}" ]] || fatal "log file not found"
  tail -n 100 "${LOG_FILE}"
}

menu(){
  echo "  SSRMU2 modern manager [v${VERSION}]"
  echo "  1. 安装 ShadowsocksR 并创建首个用户"
  echo "  3. 卸载 ShadowsocksR"
  echo "  5. 查看用户列表"
  echo "  7. 添加用户配置"
  echo " 10. 启动 ShadowsocksR"
  echo " 11. 停止 ShadowsocksR"
  echo " 12. 重启 ShadowsocksR"
  echo " 13. 查看最近日志"
  echo "  0. 退出"
  echo
  read -r -p "请输入数字: " n
  case "${n}" in
    1) install_all;;
    3) uninstall_all;;
    5) list_users;;
    7) require_root; load_os; install_base_deps; ensure_python2; add_user; "${INIT_FILE}" restart || true;;
    10) "${INIT_FILE}" start;;
    11) "${INIT_FILE}" stop;;
    12) "${INIT_FILE}" restart;;
    13) view_log;;
    0) exit 0;;
    *) fatal "invalid selection";;
  esac
}

menu
