# sysinfo.sh

Tested on Ubuntu 22.04 and Unraid.

- For UPS stats you'll need to have `Network UPS Tools` installed.
- Network usage is collected from `vnstat`.
- Docker needs to be installed.
- Libvirtd needs to be installed, tool `virsh` is used.
- For smb info `smbd` needs to be installed, tool `testparm` is used.
- For physical disk info `smartmontools`/`hdparm` needs to be installed, tools `smartctl` and `hdparm` are used.

Script output will look like this:

```text
system info:
  Distro    : Ubuntu 22.04.4 LTS
  Kernel    : Linux 5.15.0-101-generic
  Uptime    : up 3 days, 17 hours, 23 minutes
  CPU       : 13th Gen Intel(R) Core(TM) i5-13400 (16 vCPU)
  Load      : 2.35 (1m), 0.68 (5m), 0.28 (15m)
  Processes : 577 (root), 38 (user), 615 (total)
  Updates   : 3 available

ip addresses:
  br0             : 192.168.1.3
  br-5f0a16907fa8 : 172.20.0.1
  docker0         : 172.17.0.1
  virbr0          : 192.168.122.1

temperatures:
  acpitz       : 27.8°C
  x86_pkg_temp : 32.0°C

ups info:
  [Back-UPS XS 1400U]
    Status  : OL
    Battery : 100%
    Runtime : 29:04 minutes
    Load    : 20% / 140W

docker status:
  Containers : 4 (0 exited)
  Images     : 4 (0 dangling)

  ┆ hotio ⏵ ┆ caddy ⏵ ┆ cloudflareddns ⏵ ┆ test ⏵ ┆ 

vm status:
  ┆ Ubuntu 22.04 ⏵ ┆ Windows XP ⏹ ┆ 

smb shares:
  ┆ Share ┆ Path           ┆ Public ┆ Writeable ┆ Valid Users ┆ Read List ┆ Write List ┆ 
  ┆ test  ┆ /mnt/user/test ┆ ✘      ┆ ✘         ┆ hotio       ┆           ┆ hotio      ┆ 

network stats:
  ┆        ┆            ┆         Rx ┆         Tx ┆      Total ┆ 
  ┆ enp1s0 ┆            ┆            ┆            ┆            ┆ 
  ┆        ┆ Today      ┆  10,72 MiB ┆   1,75 MiB ┆  12,47 MiB ┆ 
  ┆        ┆ This Month ┆ 347,39 MiB ┆  59,57 MiB ┆ 406,97 MiB ┆ 
  ┆        ┆ Total      ┆ 347,39 MiB ┆  59,57 MiB ┆ 406,97 MiB ┆ 
  ┆ enp3s0 ┆            ┆            ┆            ┆            ┆ 
  ┆        ┆ Today      ┆        0 B ┆        0 B ┆        0 B ┆ 
  ┆        ┆ This Month ┆   2,66 MiB ┆ 526,68 KiB ┆   3,17 MiB ┆ 
  ┆        ┆ Total      ┆   2,66 MiB ┆ 526,68 KiB ┆   3,17 MiB ┆ 

memory usage:
  mem                            30% used out of  16Gi
  ▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰

disk usage:
  /                                2% used out of 8.3G
  ▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰
  /boot                            4% used out of  33G
  ▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰
  /mnt/disk1                      76% used out of  10T
  ▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰
  /mnt/disk2                      60% used out of 8.0T
  ▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰
  /mnt/disk3                       1% used out of 4.0T
  ▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰

disk status:
  ┆ Device ┆ Tran ┆ Model                            ┆ Temp ┆ Health  ┆ Power On     ┆ 
  ┆ sda    ┆ usb  ┆ Flash Drive (32G)                ┆      ┆         ┆              ┆  
  ┆ sdb    ┆ sata ┆ Samsung SSD 860 EVO 250GB (250G) ┆ 29°C ┆ healthy ┆ 02y 037d 03h ┆ ⏺
  ┆ sdc    ┆ sata ┆ Samsung SSD 850 EVO 250GB (250G) ┆ 30°C ┆ healthy ┆ 03y 357d 09h ┆ ⏺
```
