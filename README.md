# ttop

System monitoring tool with historical data service, triggers and top-like TUI

![image](https://github.com/inv2004/ttop/assets/4949069/29aa89bc-a34d-4ba4-854f-2d1b3dd4dcf4.png)


- [x] Saving historical snapshots via systemd.timer or crontab
- [x] Scroll via historical data
- [x] External triggers (for notifications or other needs)
- [x] Docker-related info
- [x] Ascii graph of historical stats (via https://github.com/Yardanico/asciigraph)
- [x] TUI with critical values highlights
- [x] Search filters: `@u` - user u, `#d` - docker d
- [x] Temperature via `sysfs`
- [x] User-space only, doesn't require root permissions
- [x] Static build
- [x] Threads tree

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
ttop --on               # Optional: enable data collector in user's systemd.timers or crontab
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

### Triggers / Notifications
* stmp support was removed in prev version by the reason that static binary with ssl is more that 3Mb

From v0.8.1 you can trigger external tool, for example curl, to send notifications

![image](https://user-images.githubusercontent.com/4949069/215402008-eb0325f9-3e6e-4908-a6aa-d7b3b64f09db.png)

### Config example
`~/.config/ttop.toml` or `/etc/ttop.toml`

#### My default server's config

```toml
[[trigger]]
cmd = "$HOME/bin/tel.sh"
```

#### Config with all parameters described

```toml
light = false            # set true for light term (default = false)

# docker = "/var/run/docker.sock"   # docker's socket path

# [data]
# path = "/var/log/ttop" # custom storage path (default = if exists /var/log/ttop, else ~/.cache/ttop )

[[trigger]]              # telegram example
on_alert = true          # execute trigger on alert (true if no other on_* provided)
on_info = true           # execute trigger without alert (default = false)
debug = false            # output stdout/err from cmd (default = false)
cmd = '''
read -d '' TEXT
curl -X POST \
  -H 'Content-Type: application/json' \
  -d "{\"chat_id\": $CHAT_ID, \"text\": \"$TEXT\", \"disable_notification\": $TTOP_INFO}" \
  https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage
'''

# cmd receives text from stdin. The following env vars are set:
#   TTOP_ALERT (true|false) - if alert
#   TTOP_INFO  (true|false) - opposite to alert
#   TTOP_TYPE  (alert|info) - trigger type
#   TTOP_HOST               - host name
# you can find your CHAT_ID by send smth to your bot and run:
#    curl https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/getUpdates

[[trigger]]               # smtp example
cmd = '''
read -d '' TEXT
TEXT="Subject: ttop $TTOP_TYPE from $TTOP_HOST

$TEXT"
echo "$TEXT" | curl --ssl-reqd \
  --url 'smtps://smtp.gmail.com:465' \
  --user 'login:password' \
  --mail-from 'from@gmail.com' \
  --mail-rcpt 'to@gmail.com' \
  --upload-file -
'''
```
