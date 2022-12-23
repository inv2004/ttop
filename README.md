# ttop

System monitoring service tool with tui and historical data

![image](https://user-images.githubusercontent.com/4949069/209130620-80ae1624-6e8e-4f48-8d12-92412f472fb9.png)

- [x] Saving historical snapshots via systemd.timer
- [x] Scroll via historical data
- [x] TUI with critical values highlight
- [x] Ascii graph of historical stats (via https://github.com/Yardanico/asciigraph)
- [x] User-space only, doesn't require root permissions
- [x] Static build
- [ ] Docker-related info

## Install
```bash
wget https://github.com/inv2004/ttop/releases/latest/download/ttop
chmod +x ttop
mv ttop ~/.local/bin/   # add into PATH
ttop --on                # to enable data collector in systemd
```

## Uninstall
```bash
ttop --off
rm ~/.local/bin/ttop
```
