# ssrmu2

`ssrmu2` is a modern-system compatibility wrapper for the legacy ShadowsocksR MuJSON installer workflow.

It is intended for fresh Debian/Ubuntu VPS images where the original `ssrmu.sh` fails because modern distributions no longer ship Python 2 as `/usr/bin/python`.

## Quick Test

```bash
wget -N --no-check-certificate https://raw.githubusercontent.com/SSTAPAPP/ssrmu2/main/ssrmu-modern.sh
chmod +x ssrmu-modern.sh
bash ssrmu-modern.sh
```

## What It Fixes

- Prepares Python 2.7 compatibility without replacing `/usr/bin/python`.
- Installs minimal dependencies such as `unzip`, `cron`, `iptables`, `net-tools`, and certificates.
- Patches the legacy installer at runtime so it prefers `/usr/local/bin/python`.
- Patches the SSR init script so `server.py` runs with Python 2.7.
- Adds a small systemd unit to restore legacy iptables rules on boot.

## User Choices

For the previously discussed `7 / 3 / 5` settings:

```text
Encryption: 7 = aes-256-ctr
Protocol:   3 = auth_aes128_md5
Obfs:       5 = tls1.2_ticket_auth
```

When asked whether to use `_compatible` for `tls1.2_ticket_auth`, choose `y` for easier client compatibility testing.

## Notes

This project keeps the legacy SSR runtime isolated as much as practical. The SSR server code itself is old Python 2 code, so a full Python 3 migration would require maintaining a fork of the server implementation rather than only modernizing the installer workflow.
