# ssrmu2

`ssrmu2` is a standalone modern-system manager for the legacy ShadowsocksR MuJSON server.

It is intended for fresh Debian/Ubuntu VPS images where the old `ssrmu.sh` workflow fails because modern distributions no longer ship Python 2 as `/usr/bin/python`.

## Quick Test

```bash
wget -N --no-check-certificate https://raw.githubusercontent.com/SSTAPAPP/ssrmu2/main/ssrmu-modern.sh
chmod +x ssrmu-modern.sh
bash ssrmu-modern.sh
```

Menu option `1` installs ShadowsocksR and creates the first user.

## What It Does

- Prepares Python 2.7 compatibility without replacing `/usr/bin/python`.
- Installs minimal dependencies such as `unzip`, `cron`, `iptables`, `net-tools`, and certificates.
- Downloads the SSR manyuser server archive and configures `mudbjson` mode.
- Creates an `/etc/init.d/ssrmu` service that runs `server.py` with `/usr/local/bin/python`.
- Adds iptables rules for each created user port.
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

This repository no longer depends on `SSTAPAPP/doubi` or a branch inside that repo.

By default the script downloads the SSR manyuser server archive from:

```text
https://github.com/ToyoDAdoubiBackup/shadowsocksr/archive/manyuser.zip
```

You can override it with your own mirror:

```bash
SSR_ZIP_URL=https://example.com/manyuser.zip bash ssrmu-modern.sh
```

## Notes

The SSR server code itself is old Python 2 code. A full Python 3 migration would require maintaining a fork of the server implementation, so this project keeps Python 2.7 isolated under `/usr/local/bin` or `/opt/python2.7` and avoids touching `/usr/bin/python`.
