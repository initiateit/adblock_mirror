# Adobe Telemetry Blocklist Mirror

This repository is an automated mirror of the Adobe telemetry blocking hosts list from [a.dove.isdumb.one/list.txt](https://a.dove.isdumb.one/list.txt).

## Purpose

This hosts file blocks Adobe telemetry and licensing check servers without interfering with other Adobe functionality such as AI generation, downloads, and other network features.

## Original Source

- **Source URL**: https://a.dove.isdumb.one/list.txt
- **Original Project**: [a-dove-is-dumb](https://github.com/ignaciocastro/a-dove-is-dumb) by [ignaciocastro](https://github.com/ignaciocastro)
- **Telegram Updates**: https://a.dove.isdumb.one/telegram

## How It Works

This repository automatically syncs with the source list daily via GitHub Actions. If changes are detected, they are automatically committed to this repository.

## Usage

### Using the hosts file

1. Download the [list.txt](list.txt) file
2. Append it to your system's hosts file:
   - **Windows**: `C:\Windows\System32\drivers\etc\hosts`
   - **Linux/macOS**: `/etc/hosts`
3. Save the file

The entries use the `0.0.0.0` format to block connections to Adobe telemetry domains.

### Reachable Blocklist

**How it works:**
- Domains are checked weekly
- Once verified as reachable, domains remain in the list
- Only new domains are checked on subsequent runs (incremental scanning)
- Updated automatically via GitHub Actions

**Usage:**
Download [watchdog_list.txt](watchdog_list.txt) and append it to your hosts file instead of list.txt if you prefer a smaller list containing only verified reachable domains.

## Automated Updates

This mirror is updated automatically via GitHub Actions:
- **Schedule**: Daily at midnight UTC
- **Manual**: Can be triggered manually from the Actions tab in this repository

## License

This is a mirror of the original project. Please refer to the [original repository](https://github.com/ignaciocastro/a-dove-is-dumb) for license information.
