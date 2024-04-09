# sysinfo.sh

Tested on Ubuntu 22.04 and Unraid.

- For UPS stats you'll need to have `Network UPS Tools` installed.
- Network usage is collected from `vnstat`.
- Docker needs to be installed.
- Libvirtd needs to be installed, tool `virsh` is used.
- For smb info `smbd` needs to be installed, tool `testparm` is used.
- For physical disk info `smartmontools`/`hdparm` needs to be installed, tools `smartctl` and `hdparm` are used.

Script output will look like this:

![sysinfo.sh output](https://hotio.dev/img/sysinfo.png)
