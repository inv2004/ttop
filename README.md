# ttop - System monitor service with historical data

![image](https://user-images.githubusercontent.com/4949069/208906443-0c92eed7-a56c-4e1e-bc01-ec5be911eae9.png)

- [x] Saving historical snapshots via systemd.timer
- [x] Scroll via historical data
- [x] TUI with critical values highlight
- [x] Ascii graph of historical stats (via https://github.com/Yardanico/asciigraph)
- [x] user-space only, doesn't require root permissions
- [x] static build

## Install
```bash
wget https://github.com/inv2004/ttop/releases/latest/download/ttop
chmod +x ttop
mv ttop ~/.local/bin/   # add into PATH
ttop -on                # to enable data collector in systemd
```

## Uninstall
```bash
ttop -off
rm ~/.local/bin/ttop
```
