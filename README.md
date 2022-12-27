# ttop

System monitoring tool with TUI and historical data service

![image](https://user-images.githubusercontent.com/4949069/209717216-9015276a-9c02-4afb-a7ec-c154fae91f69.png)

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

### Static binary

```bash
wget https://github.com/inv2004/ttop/releases/latest/download/ttop
chmod +x ttop
mv ttop ~/bin/          # add into PATH if necessary
ttop --on               # enable data collector in user's systemd.timers
```

### Uninstall
```bash
ttop --off
rm ~/bin/ttop
```
