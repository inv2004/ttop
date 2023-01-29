# ttop

System monitoring tool with TUI and historical data service

![image](https://user-images.githubusercontent.com/4949069/214555373-d9a8288a-558b-488c-84fa-d18afb5bcbf5.png)

- [x] Saving historical snapshots via systemd.timer or crontab
- [x] Scroll via historical data
- [x] TUI with critical values highlight
- [x] External triggers (for notifications or other needs)
- [x] Ascii graph of historical stats (via https://github.com/Yardanico/asciigraph)
- [x] Temperature via [libsensors](https://github.com/lm-sensors/lm-sensors/)
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

### Notification
* stmp support was removed in prev version by the reason that static binary with ssl is more that 3Mb

At the moment `ttop` saves report files `alert.txt` (if any alert) or `info.txt` into data dir - `~/.cache/ttop/` or `/var/log/ttop` (for root or Arch)
