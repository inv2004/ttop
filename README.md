# ttop - System monitor service with historical access

![image](https://user-images.githubusercontent.com/4949069/208906443-0c92eed7-a56c-4e1e-bc01-ec5be911eae9.png)

- [x] TUI with critical values highlight
- [x] Saving historical snapshots via systemd.timer
- [x] Scroll via historical data
- [x] Ascii graph of historical stats

## Install
```bash
cd ~/.local/bin/ && curl ...
ttop -on # to enable data collector
```

## Uninstall
```bash
ttop -off
rm ~/.local/bin/ttop
```
