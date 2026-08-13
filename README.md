# hyprmoncfg for Omarchy

An Omarchy bar panel for [hyprmoncfg](https://hyprmoncfg.dev/). See the live display layout and active profile. Turn management on for automatic switching on monitor hotplug and lid events, or turn it off to hand displays cleanly back to Omarchy.

![hyprmoncfg for Omarchy](preview.png)

The panel is intentionally the full hyprmoncfg experience: it installs the stable AUR package, enables the user daemon, and uses automatic switching on monitor hotplug.

## Install

```sh
omarchy plugin add https://github.com/crmne/omarchy-hyprmoncfg.git --enable
```

If hyprmoncfg is missing, open the panel and choose **Install hyprmoncfg**. Omarchy opens its normal presented terminal and runs:

```sh
omarchy pkg aur add hyprmoncfg && systemctl --user enable --now hyprmoncfgd.service && setsid gtk-launch hyprmoncfg-omarchy >/dev/null 2>&1 &
```

The installer opens hyprmoncfg through its hidden Omarchy desktop launcher after starting the daemon. That launcher ships with the main package and carries Omarchy's standard `TUI.float` window identity, so the editor opens centered at the normal floating size without putting Omarchy-specific window logic in the panel. Saving a profile updates the panel immediately over IPC. The plugin never runs `yay` or requests privileges invisibly inside `omarchy-shell`.

## Requirements

- Omarchy Quattro with third-party shell plugins
- hyprmoncfg 1.12.0 or newer (installed from the panel when missing)

## Development

```sh
omarchy plugin validate .
node --test tests/model.test.js
```
