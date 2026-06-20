# Modernization Notes

## Why the old workflow fails on Debian 13

The old `ssrmu.sh` workflow assumes an old Linux userland:

- `python` exists and is Python 2.
- `apt-get install python` works.
- SysV init scripts are enough for service management.
- `iptables` and ifupdown-style restore hooks are present by default.

On Debian 13, the default system has Python 3 only, no `python` command, and no Python 2 package in the normal repository. The SSR manyuser code is still Python 2 era code, so pointing `python` to Python 3 is not safe.

## What this repo changes

`ssrmu-modern.sh` is not a branch patch for `SSTAPAPP/doubi`. It is an independent manager script in `SSTAPAPP/ssrmu2`.

It directly implements the core SSR MuJSON lifecycle:

- prepare dependencies
- prepare Python 2.7 compatibility
- download SSR manyuser server archive
- configure `mudbjson`
- create `/etc/init.d/ssrmu`
- add users through `mujson_mgr.py`
- add firewall rules
- start/stop/restart/list users

## Current feature scope

Implemented:

- install first user
- add user
- list users
- start/stop/restart service
- show recent log
- uninstall SSR files
- iptables rule persistence helper

Not yet ported from the old all-in-one script:

- BBR helper menu
- ServerSpeeder / LotServer helper menu
- traffic reset cron menu
- detailed SSR link/QR rendering
- BT/PT/SPAM iptables helper
- libsodium helper path for chacha20 choices

The first test target is the install path with choices `7 / 3 / 5` on Debian 13.

## Dependency note

The script does not depend on `SSTAPAPP/doubi`.

It still downloads the SSR server archive from the default backup source:

```text
https://github.com/ToyoDAdoubiBackup/shadowsocksr/archive/manyuser.zip
```

For long-term independence, mirror that zip yourself and run:

```bash
SSR_ZIP_URL=https://your-mirror.example/manyuser.zip bash ssrmu-modern.sh
```

## Suggested test plan

On a fresh Debian 13 VPS:

```bash
wget -N --no-check-certificate https://raw.githubusercontent.com/SSTAPAPP/ssrmu2/main/ssrmu-modern.sh
chmod +x ssrmu-modern.sh
bash ssrmu-modern.sh
```

Then choose:

```text
1  install
7  encryption aes-256-ctr
3  protocol auth_aes128_md5
5  obfs tls1.2_ticket_auth
y  compatible obfs
```

After installation:

```bash
/usr/local/bin/python --version
/etc/init.d/ssrmu status
cd /usr/local/shadowsocksr && /usr/local/bin/python mujson_mgr.py -l
iptables -S | grep <your-port>
tail -n 100 /usr/local/shadowsocksr/ssserver.log
```
