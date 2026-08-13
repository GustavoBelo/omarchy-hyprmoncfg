# hyprmoncfg for Omarchy

An Omarchy bar panel for [hyprmoncfg](https://hyprmoncfg.dev/). It shows the active monitor profile, switches saved profiles safely, and receives live updates from `hyprmoncfgd` over its Unix-socket IPC protocol.

The panel is intentionally the full hyprmoncfg experience: it installs the stable AUR package, enables the user daemon, and uses automatic switching on monitor hotplug.

## Install

```sh
omarchy plugin add https://github.com/crmne/omarchy-hyprmoncfg.git --enable
```

If hyprmoncfg is missing, open the panel and choose **Install hyprmoncfg**. Omarchy opens its normal presented terminal and runs:

```sh
omarchy pkg aur add hyprmoncfg && systemctl --user enable --now hyprmoncfgd
```

The plugin never runs `yay` or requests privileges invisibly inside `omarchy-shell`.

## Requirements

- Omarchy Quattro with third-party shell plugins
- hyprmoncfg 1.11.0 or newer (installed from the panel when missing)

## Development

```sh
omarchy plugin validate .
node --test tests/model.test.js
```
