# ttop

System monitoring tool with TUI and historical data service

![image](https://user-images.githubusercontent.com/4949069/214555373-d9a8288a-558b-488c-84fa-d18afb5bcbf5.png)

- [x] Saving historical snapshots via systemd.timer or crontab
- [x] Scroll via historical data
- [x] TUI with critical values highlight
- [x] Send email alerts
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

### Configuration file example
`$HOME/.config/ttop.conf` or `/etc/ttop.conf`
```ini
# [data]
# path=/var/log/ttop
# if path is not defined:
#   if /var/log/ttop exists then uses it
#   else it uses $HOME/.cache/ttop

# [smtp]
# host = smtp.gmail.com
# if host is defined - email alerts are enabled, you can check configuration via "ttop --checksmtp"
# user = gmail-user
# pass = gmail-app-passcode
# from = "from@gmail.com"
# to = "to@gmail.com"
# ssl = true
# debug = false
```
