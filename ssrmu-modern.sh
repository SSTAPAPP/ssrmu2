#!/usr/bin/env bash
set -Eeuo pipefail

# Compatibility launcher for the original Toyo ssrmu.sh menu.
# It intentionally keeps the original UI and flow, and only prepares the
# runtime pieces that modern Debian/Ubuntu systems removed.

PATH=/usr/local/bin:/usr/local/sbin:/bin:/sbin:/usr/bin:/usr/sbin:~/bin
export PATH

VERSION="0.2.0"
ORIGINAL_URL="${SSR_ORIGINAL_URL:-https://raw.githubusercontent.com/ToyoDAdoubiBackup/doubi/master/ssrmu.sh}"
WORKDIR="${SSR_WORKDIR:-/root}"
ORIGINAL_SCRIPT="${SSR_ORIGINAL_SCRIPT:-${WORKDIR}/ssrmu-origin.sh}"
PATCHED_SCRIPT="${SSR_PATCHED_SCRIPT:-${WORKDIR}/ssrmu.sh}"
PY2_PREFIX="${PY2_PREFIX:-/opt/python2.7}"
PY2_BIN="${PY2_PREFIX}/bin/python2.7"
INIT_FILE="/etc/init.d/ssrmu"

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

cleanup_python_link_loops(){
  local f target resolved
  for f in /usr/local/bin/python /usr/local/bin/python2 /usr/local/bin/python2.7; do
    [[ -L "${f}" ]] || continue
    target="$(readlink "${f}" 2>/dev/null || true)"
    resolved="$(readlink -f "${f}" 2>/dev/null || true)"
    if [[ -z "${resolved}" || "${resolved}" == "${f}" || "${target}" == "${f}" || "${target}" == python || "${target}" == python2 || "${target}" == python2.7 ]]; then
      warn "removing broken Python compatibility link: ${f} -> ${target:-?}"
      rm -f "${f}"
    fi
  done
}

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
  mkdir -p /etc/network/if-pre-up.d /etc/iptables /etc/systemd/system /usr/local/bin "${WORKDIR}"
}

python_is_py2(){
  local bin="$1" resolved
  resolved="$(readlink -f "${bin}" 2>/dev/null || true)"
  [[ -n "${resolved}" && -x "${resolved}" ]] || return 1
  "${resolved}" - <<'PY' >/dev/null 2>&1
import sys
raise SystemExit(0 if sys.version_info[0] == 2 else 1)
PY
}

find_python2(){
  local c r resolved
  cleanup_python_link_loops
  for c in /usr/bin/python2.7 /usr/bin/python2 /bin/python2.7 /bin/python2 "${PY2_BIN}" python2.7 python2 python; do
    if [[ -x "${c}" ]]; then
      r="${c}"
    elif exists "${c}"; then
      r="$(command -v "${c}")"
    else
      continue
    fi
    resolved="$(readlink -f "${r}" 2>/dev/null || true)"
    [[ -n "${resolved}" ]] || continue
    case "${resolved}" in
      /usr/local/bin/python|/usr/local/bin/python2|/usr/local/bin/python2.7) continue ;;
    esac
    python_is_py2 "${resolved}" && echo "${resolved}" && return 0
  done
  return 1
}

link_python2(){
  local py2="$1" resolved
  resolved="$(readlink -f "${py2}" 2>/dev/null || true)"
  [[ -n "${resolved}" && -x "${resolved}" ]] || fatal "invalid Python2 runtime: ${py2}"
  python_is_py2 "${resolved}" || fatal "not a Python2 runtime: ${resolved}"
  rm -f /usr/local/bin/python /usr/local/bin/python2 /usr/local/bin/python2.7
  ln -s "${resolved}" /usr/local/bin/python
  ln -s "${resolved}" /usr/local/bin/python2
  ln -s "${resolved}" /usr/local/bin/python2.7
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
  cleanup_python_link_loops
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

ensure_cron(){
  if exists systemctl; then
    systemctl enable --now cron >/dev/null 2>&1 || systemctl enable --now crond >/dev/null 2>&1 || true
  fi
  service cron restart >/dev/null 2>&1 || service crond restart >/dev/null 2>&1 || true
}

install_iptables_restore_unit(){
  exists systemctl || return 0
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
}

download_original(){
  if [[ -f "${ORIGINAL_SCRIPT}" ]]; then
    info "Using cached original script: ${ORIGINAL_SCRIPT}"
  else
    info "Downloading original ssrmu.sh..."
    wget --no-check-certificate -O "${ORIGINAL_SCRIPT}" "${ORIGINAL_URL}"
  fi
}

patch_original(){
  cp -f "${ORIGINAL_SCRIPT}" "${PATCHED_SCRIPT}"
  chmod +x "${PATCHED_SCRIPT}"
  sed -i 's#^PATH=.*#PATH=/usr/local/bin:/usr/local/sbin:/bin:/sbin:/usr/bin:/usr/sbin:~/bin#' "${PATCHED_SCRIPT}"
  sed -i \
    -e 's#apt-get install -y python#apt-get install -y python2.7 || true#g' \
    -e 's#yum install -y python#yum install -y python2 || yum install -y python27 || true#g' \
    -e 's#apt-get install -y vim unzip cron net-tools#apt-get install -y vim-tiny unzip cron net-tools iptables ca-certificates curl#g' \
    -e 's#apt-get install -y vim unzip cron#apt-get install -y vim-tiny unzip cron net-tools iptables ca-certificates curl#g' \
    -e 's#yum install -y vim unzip crond net-tools#yum install -y vim-minimal unzip cronie net-tools iptables-services ca-certificates curl#g' \
    -e 's#yum install -y vim unzip crond#yum install -y vim-minimal unzip cronie net-tools iptables-services ca-certificates curl#g' \
    "${PATCHED_SCRIPT}"
}

patch_service(){
  [[ -f "${INIT_FILE}" ]] || return 0
  sed -i \
    -e 's#python_ver="python"#python_ver="/usr/local/bin/python"#g' \
    -e 's#python_ver=python#python_ver=/usr/local/bin/python#g' \
    "${INIT_FILE}" || true
  chmod +x "${INIT_FILE}" || true
}

service_patch_watch(){
  while true; do
    patch_service
    sleep 1
  done
}

main(){
  require_root
  load_os
  info "ssrmu2 compatibility launcher v${VERSION}"
  info "OS: ${OS_ID} ${OS_LIKE}"
  install_base_deps
  ensure_python2
  ensure_cron
  install_iptables_restore_unit
  download_original
  patch_original

  service_patch_watch &
  watcher_pid=$!
  trap 'kill "${watcher_pid}" >/dev/null 2>&1 || true' EXIT

  set +e
  bash "${PATCHED_SCRIPT}" "$@"
  rc=$?
  set -e

  patch_service
  kill "${watcher_pid}" >/dev/null 2>&1 || true
  trap - EXIT
  exit "${rc}"
}

main "$@"
