# ssrmu2

`ssrmu2` is a compatibility launcher for the original Toyo `ssrmu.sh` ShadowsocksR MuJSON script.

The goal is **not** to redesign the menu. The launcher keeps the original `ssrmu.sh` UI and flow, then fixes the runtime assumptions that break on modern systems such as Debian 13.

## Quick Test

```bash
wget -N --no-check-certificate https://raw.githubusercontent.com/SSTAPAPP/ssrmu2/main/ssrmu-modern.sh
chmod +x ssrmu-modern.sh
bash ssrmu-modern.sh
```

You should see the original menu title:

```text
ShadowsocksR MuJSON一键管理脚本 [v1.0.26]
```

Menu option `1` installs ShadowsocksR and creates the first user.

## What The Launcher Fixes

- Prepares Python 2.7 compatibility without replacing `/usr/bin/python`.
- Removes broken `/usr/local/bin/python*` symlink loops if an earlier test created them.
- Installs minimal dependencies such as `unzip`, `cron`, `iptables`, `net-tools`, and certificates.
- Patches the downloaded original script copy so `/usr/local/bin` is first in `PATH`.
- Prevents the original script from failing on removed `python` package names.
- Watches and patches `/etc/init.d/ssrmu` so `server.py` runs with `/usr/local/bin/python`.
- Adds a small systemd unit to restore legacy iptables rules on boot.

## User Choices

For the previously discussed `7 / 3 / 5` settings:

```text
Encryption: 7 = aes-256-ctr
Protocol:   3 = auth_aes128_md5
Obfs:       5 = tls1.2_ticket_auth
```

When asked whether to use `_compatible` for `tls1.2_ticket_auth`, choose `y` for easier client compatibility testing.

## External Source

By default this launcher downloads the original `ssrmu.sh` from Toyo's backup repo at runtime:

```text
https://raw.githubusercontent.com/ToyoDAdoubiBackup/doubi/master/ssrmu.sh
```

You can override it with your own mirror:

```bash
SSR_ORIGINAL_URL=https://example.com/ssrmu.sh bash ssrmu-modern.sh
```

The SSR server archive is still downloaded by the original script from its configured source.

## Notes

The SSR server code itself is old Python 2 code. A full Python 3 migration would require maintaining a fork of the server implementation, so this launcher keeps Python 2.7 isolated under `/usr/local/bin` or `/opt/python2.7` and avoids touching `/usr/bin/python`.
