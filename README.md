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
  Uptime    : up 2 days, 11 hours
  CPU       : 13th Gen Intel(R) Core(TM) i5-13400 (1 vCPU)
  Load      : 0.00 (1m), 0.00 (5m), 0.00 (15m)
  Processes : 198 (root), 15 (user), 213 (total)

ups info:
  [Back-UPS XS 1400U]
    Status  : OL
    Battery : 100%
    Runtime : 41:40 minutes
    Load    : 15% / 105W

docker status:
  Containers : 4 (0 exited)
  Images     : 4 (0 dangling)

  | plex: up | caddy: up | cloudflareddns: up | test: up | 

vm status:
  | Ubuntu 22.04:        running  | Windows 10: shut off | Windows 7: shut off | 
  | Windows Server 2008: shut off | Windows XP: shut off | 

smb shares:
  | Share     | Path           | Public | Writeable | Valid Users | Read List | Write List | 
  | testshare | /mnt/pool/test | no     | no        | test        |           | test       | 

network usage:
  |        |            |         Rx |         Tx |      Total | 
  | enp1s0 |            |            |            |            | 
  |        | Today      |  65,54 MiB |  12,81 MiB |  78,34 MiB | 
  |        | This Month | 324,16 MiB |  56,37 MiB | 380,53 MiB | 
  |        | Total      | 324,16 MiB |  56,37 MiB | 380,53 MiB | 
  | enp3s0 |            |            |            |            | 
  |        | Today      |        0 B |        0 B |        0 B | 
  |        | This Month |   2,66 MiB | 526,68 KiB |   3,17 MiB | 
  |        | Total      |   2,66 MiB | 526,68 KiB |   3,17 MiB | 

memory usage:
  mem                            14% used out of 2,0Gi
  [==================================================]
  swap                            0% used out of 2,0Gi
  [==================================================]

disk usage:
  /                               44% used out of  14G
  [==================================================]
  /boot                            8% used out of 2,0G
  [==================================================]
  /mnt/pool                        1% used out of 3,0G
  [==================================================]
  /mnt/cache                       1% used out of 2,0G
  [==================================================]

disk status:
  | Device | Tran | Model                            | Temp | Health  | Power On     | State       | 
  | sda    | usb  | Flash Drive (32G)                | *    | *       | *            | *           | 
  | sdb    | sata | Samsung SSD 860 EVO 250GB (250G) | 24C  | healthy | 02y 036d 19h | active/idle | 
  | sdc    | sata | Samsung SSD 850 EVO 250GB (250G) | 25C  | healthy | 03y 357d 01h | active/idle | 

```
