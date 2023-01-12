# ttop

11

System monitoring tool with TUI and historical data service

![image](https://user-images.githubusercontent.com/4949069/209717216-9015276a-9c02-4afb-a7ec-c154fae91f69.png)

- [x] Saving historical snapshots via systemd.timer or crontab
- [x] Scroll via historical data
- [x] TUI with critical values highlight
- [x] Ascii graph of historical stats (via https://github.com/Yardanico/asciigraph)
- [x] User-space only, doesn't require root permissions
- [x] Static build
- [x] Threads tree
- [ ] Docker-related info
- [ ] "red" flag notifications via ?telegram?

## Install

### Arch/AUR
```bash
yay -S ttop             # enables systemd.timers automatically
```

### Static binary

```bash
wget https://github.com/inv2004/ttop/releases/latest/download/ttop
chmod +x ttop
mv ttop ~/bin/          # add into PATH if necessary
ttop --on               # enable data collector in user's systemd.timers or crontab
```

### Uninstall
```bash
ttop --off
rm ~/bin/ttop
```

### Build from source
```bash
curl https://nim-lang.org/choosenim/init.sh -sSf | sh    # Nim setup from nim-lang.org

git clone https://github.com/inv2004/ttop
cd ttop
nimble -d:release build
```
