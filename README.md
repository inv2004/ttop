# ttop

System monitoring tool with TUI and historical data service

![image](https://user-images.githubusercontent.com/4949069/209586812-11385ba4-2618-4fda-bf04-d0379cc13f04.png)

- [x] Saving historical snapshots via systemd.timer
- [x] Scroll via historical data
- [x] TUI with critical values highlight
- [x] Ascii graph of historical stats (via https://github.com/Yardanico/asciigraph)
- [x] User-space only, doesn't require root permissions
- [x] Static build
- [x] Threads tree
- [ ] Docker-related info

## Install

### Arch/AUR
```bash
yay -S ttop
```

### Download

```bash
wget https://github.com/inv2004/ttop/releases/latest/download/ttop
chmod +x ttop
mv ttop ~/.local/bin/   # add into PATH
ttop --on               # to enable data collector in systemd
```

### Uninstall
```bash
ttop --off
rm ~/.local/bin/ttop
```
