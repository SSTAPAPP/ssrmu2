# Modernization Notes

## Why the old workflow fails on Debian 13

The old `ssrmu.sh` workflow assumes an older Linux userland:

- `python` exists and is Python 2.
- `apt-get install python` works.
- SysV init scripts are enough for service management.
- `iptables` and ifupdown-style restore hooks are present by default.

On Debian 13, the default system has Python 3 only, no `python` command, and no Python 2 package in the normal repository. The SSR manyuser code is still Python 2 era code, so pointing `python` to Python 3 is not safe.

## What this repo changes

`ssrmu-modern.sh` is a compatibility launcher, not a replacement UI and not a branch patch for `SSTAPAPP/doubi`.

It keeps the original Toyo menu and flow. At runtime it:

- prepares basic dependencies;
- prepares a Python 2.7 runtime and `/usr/local/bin/python` compatibility link;
- downloads or reuses the original Toyo `ssrmu.sh` script;
- patches only the runtime working copy at `/root/ssrmu.sh`;
- keeps `/root/ssrmu-origin.sh` as the cached original download;
- patches `/etc/init.d/ssrmu` so the generated service uses `/usr/local/bin/python`;
- reloads systemd when the generated service changes.

The upstream Toyo repository is not modified by this repo.

## Current scope

This repo is meant to make the original script start on newer systems while preserving the original menu.

It does not fully port SSR to Python 3 and does not redesign the SSR user manager.

## Dependency note

The script does not depend on `SSTAPAPP/doubi`.

By default it downloads the original menu script from Toyo's backup repo:

```text
https://raw.githubusercontent.com/ToyoDAdoubiBackup/doubi/master/ssrmu.sh
```

You can override that source with:

```bash
SSR_ORIGINAL_URL=https://your-mirror.example/ssrmu.sh bash ssrmu-modern.sh
```

The SSR server archive is still downloaded by the original script from its own configured source.

## Suggested test plan

On a fresh Debian 13 VPS:

```bash
wget --no-check-certificate -O ssrmu-modern.sh https://raw.githubusercontent.com/SSTAPAPP/ssrmu2/main/ssrmu-modern.sh
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

Use integer GB values for traffic limits. The original script does not accept decimals such as `1.5`.

After installation, the original menu options can be used:

```text
5   view account information
10  start ShadowsocksR
11  stop ShadowsocksR
12  restart ShadowsocksR
13  view recent logs
```

For manual checks:

```bash
/usr/local/bin/python --version
systemctl status ssrmu --no-pager || service ssrmu status
ps aux | grep -E 'server.py|shadowsocks|ssr' | grep -v grep
ss -lntup | grep -E 'python|ssr|shadowsocks'
```
