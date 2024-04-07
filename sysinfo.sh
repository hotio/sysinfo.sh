#!/bin/bash

#######################################################
## CONFIGURATION                                     ##
#######################################################
COLUMNS_DOCKER=4
COLUMNS_VM=3
SMB_TABLE_WIDTH=120
DISK_USAGE_FILTER="/mnt/disks"
#DISK_USAGE_FILTER="user|user0|libvirt|disk"
DISK_STATUS_FILTER="DONOTFILTER"
#DISK_STATUS_FILTER="sda|sas"
DISK_STATUS_HIDE_SERIAL=true
#######################################################

[[ -f /etc/default/hotio-sysinfo ]] && source /etc/default/hotio-sysinfo

# colors
W="\e[0;39m"
G="\e[1;32m"
white=$W
green=$G
red="\e[1;31m"
yellow="\e[1;33m"
dim="\e[2m"
undim="\e[0m"

#######################################################
## SYSINFO                                           ##
#######################################################
DISTRO=$(source /etc/os-release && echo "${PRETTY_NAME}")
KERNEL=$(uname -sr)
UPTIME=$(uptime -p)

# get load averages
read -r LOAD1 LOAD5 LOAD15 <<< "$(awk '{print $1,$2,$3}' < /proc/loadavg)"

# get processes
PROCESS=$(ps -eo user= | sort | uniq -c | awk '{print $2,$1}')
PROCESS_ALL=$(awk '{print $2}' <<< "$PROCESS" | awk '{SUM += $1} END {print SUM}')
PROCESS_USER=$(grep -v root <<< "$PROCESS" | awk '{print $2}' | awk '{SUM += $1} END {print SUM}')
PROCESS_ROOT=$((PROCESS_ALL - PROCESS_USER))

# get processors
PROCESSOR=$(grep "model name" /proc/cpuinfo | awk -F ':' '{print $2}')
PROCESSOR_NAME=$(head -1 <<< "${PROCESSOR}" | xargs)
PROCESSOR_COUNT=$(wc -l <<< "${PROCESSOR}")

# print results
out="
system info:
  Distro    : $DISTRO
  Kernel    : $KERNEL
  Uptime    : $UPTIME
  CPU       : $PROCESSOR_NAME ($G$PROCESSOR_COUNT$W vCPU)
  Load      : $G$LOAD1$W (1m), $G$LOAD5$W (5m), $G$LOAD15$W (15m)
  Processes : $G$PROCESS_ROOT$W (root), $G$PROCESS_USER$W (user), $G$PROCESS_ALL$W (total)
"

printf "%b" "$out"

#######################################################
## UPS                                               ##
#######################################################
sec2min() { printf "%d:%02d" "$((10#$1 / 60))" "$((10#$1 % 60))"; }

out=""
while read -r line; do
    ups_stats=$(upsc "${line}" 2> /dev/null)
    unset ups_model ups_battery ups_runtime ups_load ups_status
    grep -q ups.model: <<< "${ups_stats}" && ups_model="  [$(grep ups.model: <<< "${ups_stats}" | awk -F': ' '{print $2}' | xargs)]\n"
    grep -q battery.charge: <<< "${ups_stats}" && ups_battery="    Battery : $(grep battery.charge: <<< "${ups_stats}" | awk -F': ' '{print $2}')%\n"
    grep -q battery.runtime: <<< "${ups_stats}" && ups_runtime="    Runtime : $(sec2min "$(grep battery.runtime: <<< "${ups_stats}" | awk '{print $2}')") minutes\n"
    grep -q ups.load: <<< "${ups_stats}" && grep -q ups.realpower.nominal: <<< "${ups_stats}" && ups_load="    Load    : $(grep ups.load: <<< "${ups_stats}" | awk '{print $2}')% / $(( $(grep ups.realpower.nominal: <<< "${ups_stats}" | awk '{print $2}')*$(grep ups.load: <<< "${ups_stats}" | awk '{print $2}')/100 ))W\n"
    grep -q ups.status: <<< "${ups_stats}" && ups_status=$(grep ups.status: <<< "${ups_stats}" | awk '{print $2}')
    if [[ ${ups_status} == "OL" ]]; then
        ups_status="    Status  : $G${ups_status}$W\n"
    elif [[ ${ups_status} == "CHRG" ]]; then
        ups_status="    Status  : $yellow${ups_status}$W\n"
    elif [[ -n ${ups_status} ]]; then
        ups_status="    Status  : $red${ups_status}$W\n"
    fi
    out+="${ups_model}${ups_status}${ups_battery}${ups_runtime}${ups_load}"
done < <(grep ^MONITOR /etc/nut/upsmon.conf | awk '{print $2}')

printf "\nups info:\n"
[[ -n ${out} ]] && printf '%b' "${out}"
[[ -z ${out} ]] && printf '%b'  "  no ups\n"

#######################################################
## DOCKER                                            ##
#######################################################
COLUMNS=${COLUMNS_DOCKER}

mapfile -t containers < <(docker ps --all --format '{{.Names}}\t{{.Status}}' | sort -k1 | awk '{ print $1,$2 }')

out=""
for i in "${!containers[@]}"; do
    read -r name status <<< "${containers[i]}"

    image=$(docker inspect --format='{{.Config.Image}}' "$name" 2> /dev/null)
    image_digest=$(docker image inspect --format='{{.Id}}' "$image" 2> /dev/null)
    container_digest=$(docker inspect --format='{{.Image}}' "$name" 2> /dev/null)
    update_status=""
    [[ "$image_digest" != "$container_digest" ]] && update_status='*'

    if [[ "${status}" == "Up" ]]; then
        out+="${name}:,${green}${status,,}${undim}${update_status},| "
    else
        out+="${name}:,${red}${status,,}${undim}${update_status},| "
    fi

    if [ $(((i+1) % COLUMNS)) -eq 0 ]; then
        out+="\n"
    fi
done

containers_all=$(docker ps --all --format '{{.Names}}' | wc -l)
containers_exited=$(docker ps --all --format '{{.Names}}' --filter "status=exited" | wc -l)
images_all=$(docker images --format '{{.ID}}' | wc -l)
images_dangling=$(docker images --format '{{.ID}}' --filter "dangling=true" | wc -l)

printf "\ndocker status:\n"
printf "  Containers : %s (%s exited)\n" "${containers_all}" "${containers_exited}"
printf "  Images     : %s (%s dangling)\n\n" "${images_all}" "${images_dangling}"
[[ -n ${out} ]] && printf '%b' "${out}\n" | column -ts ',' -o ' ' | sed -e 's/^/  | /'
[[ -z ${out} ]] && printf '%b'  "  no containers\n"

#######################################################
## VM                                                ##
#######################################################
COLUMNS=${COLUMNS_VM}

virsh_output=$(virsh list --all 2> /dev/null)
column2=$(grep -ob "Name" <<< "${virsh_output}" | grep -oE "[0-9]+")
column3=$(grep -ob "State" <<< "${virsh_output}" | grep -oE "[0-9]+")
column2_length=$((column3-column2))

out=""
while IFS= read -r vm; do
    name=$(xargs <<< "${vm:${column2}:${column2_length}}")
    status=$(xargs <<< "${vm:${column3}}")

    if [[ "${status}" == "running" ]]; then
        out+="${name}:,${green}${status,,}${undim},| "
    elif [[ "${status}" == "paused" ]]; then
        out+="${name}:,${yellow}${status,,}${undim},| "
    elif [[ "${status}" == "shut off" ]]; then
        out+="${name}:,${white}${status,,}${undim},| "
    else
        out+="${name}:,${red}${status,,}${undim},| "
    fi

    if [ $(((i+1) % COLUMNS)) -eq 0 ]; then
        out+="\n"
    fi
done < <(sed -e '1,2d' -e '/^$/d' <<< "${virsh_output}")

printf "\nvm status:\n"
[[ -n ${out} ]] && printf '%b' "${out}\n" | column -ts ',' -o ' ' | sed -e 's/^/  | /'
[[ -z ${out} ]] && printf '%b'  "  no virtual machines\n"

#######################################################
## SAMBA                                             ##
#######################################################
out=""
while read -r share; do
    share_path=$(testparm -s -v --section-name "${share}" --parameter-name "path" 2> /dev/null)
    public=$(testparm -s -v --section-name "${share}" --parameter-name "public" 2> /dev/null)
    writeable=$(testparm -s -v --section-name "${share}" --parameter-name "writeable" 2> /dev/null)
    valid_users=$(testparm -s -v --section-name "${share}" --parameter-name "valid users" 2> /dev/null)
    read_list=$(testparm -s -v --section-name "${share}" --parameter-name "read list" 2> /dev/null)
    write_list=$(testparm -s -v --section-name "${share}" --parameter-name "write list" 2> /dev/null)
    out+="|${share}|${share_path}|${public,,}|${writeable,,}|${valid_users}|${read_list}|${write_list}|\n"
done < <(testparm -s 2> /dev/null | grep '\[.*\]' | grep -v -E "global|homes|printers" | sed -e 's/\[//' -e 's/\]//')

printf "\nsmb shares:\n"
[[ -n ${out} ]] && printf '%b' " ${out}" | column -t -o ' | ' -s '|' --table-wrap 6,7,8 --output-width "${SMB_TABLE_WIDTH}" -N " ,Share,Path,Public,Writeable,Valid Users,Read List,Write List"
[[ -z ${out} ]] && printf '%b'  "  no shares exported\n"

#######################################################
## NETWORK USAGE                                     ##
#######################################################
out=""
while read -r interface; do
    out+="|${interface}|||||\n"
    results=$(vnstat --oneline "${interface}" 2> /dev/null)
    # today
    rx=$(awk -F ";" '{print $4}' <<< "${results}")
    tx=$(awk -F ";" '{print $5}' <<< "${results}")
    total=$(awk -F ";" '{print $6}' <<< "${results}")
    out+="||Today|$rx|$tx|$total|\n"

    # this month
    rx=$(awk -F ";" '{print $9}' <<< "${results}")
    tx=$(awk -F ";" '{print $10}' <<< "${results}")
    total=$(awk -F ";" '{print $11}' <<< "${results}")
    out+="||This Month|$rx|$tx|$total|\n"

    # total
    rx=$(awk -F ";" '{print $13}' <<< "${results}")
    tx=$(awk -F ";" '{print $14}' <<< "${results}")
    total=$(awk -F ";" '{print $15}' <<< "${results}")
    out+="||Total|$rx|$tx|$total|\n"
done < <(vnstat --json 2> /dev/null | jq -r '.interfaces | .[].name')

[[ -n ${out} ]] && printf "\nnetwork usage:\n"
[[ -n ${out} ]] && printf '%b' " ${out}" | column -t -R '4,5,6' -o ' | ' -s '|' -N " , , ,Rx,Tx,Total"

#######################################################
## MEMORY                                            ##
#######################################################
max_usage=95
warn_usage=80
bar_width=50

printf "\nmemory usage:\n"

while read -r line; do
    title=$(awk -F ':' '{print $1}' <<< "$line")
    total=$(awk '{print $2}' <<< "$line")
    usage=$(awk '{print $3}' <<< "$line")
    usage_perc=$(((usage*100)/total))
    used_width=$(((usage_perc*bar_width)/100))

    [[ "${usage_perc}" -ge "0" ]] && color=${green}
    [[ "${usage_perc}" -ge "${warn_usage}" ]] && color=${yellow}
    [[ "${usage_perc}" -ge "${max_usage}" ]] && color=${red}

    bar="[${color}"
    for ((i=0; i<used_width; i++)); do
        bar+="="
    done
    bar+="${white}${dim}"
    for ((i=used_width; i<bar_width; i++)); do
        bar+="="
    done
    bar+="${undim}]"

    total=$(numfmt --to iec-i --format "%f" "$total")
    printf "  %-31s%+3s used out of %+5s\n" "${title,,}" "$usage_perc%" "$total"
    printf "  %b\n" "${bar}"
done < <(free --bytes | awk '$2 != 0' | tail -n+2)

#######################################################
## DISKSPACE                                         ##
#######################################################
max_usage=95
warn_usage=80
bar_width=50
filter_disks=${DISK_USAGE_FILTER}

printf "\ndisk usage:\n"

while read -r line; do
    usage_perc=$(awk '{print $2}' <<< "$line"| sed 's/%//')
    used_width=$(((usage_perc*bar_width)/100))

    [[ "${usage_perc}" -ge "0" ]] && color=${green}
    [[ "${usage_perc}" -ge "${warn_usage}" ]] && color=${yellow}
    [[ "${usage_perc}" -ge "${max_usage}" ]] && color=${red}

    bar="[${color}"
    for ((i=0; i<used_width; i++)); do
        bar+="="
    done
    bar+="${white}${dim}"
    for ((i=used_width; i<bar_width; i++)); do
        bar+="="
    done
    bar+="${undim}]"

    awk '{ printf("  %-32s%+3s used out of %+4s\n", $1, $2, $3); }' <<< "${line}"
    printf "  %b\n" "${bar}"
done < <(df -h -x squashfs -x tmpfs -x devtmpfs -x overlay --output=target,pcent,size | grep -v -E "${filter_disks}" | tail -n+2)

#######################################################
## DISKSTATUS                                        ##
#######################################################
WARN_TEMP_HDD=35
MAX_TEMP_HDD=40
WARN_TEMP_SSD=40
MAX_TEMP_SSD=60
SSD_LIFE_TRESHOLD=90
filter_disks=${DISK_STATUS_FILTER}

function displaytime {
    if [[ ${1} != "*" ]]; then
        local T=$1
        local Y=$((T/24/365))
        local D=$((T/24%365))
        local H=$((T%24))
        printf '%02dy ' $Y
        printf '%03dd ' $D
        printf '%02dh' $H
    else
        printf '%s' "$1"
    fi
}

serial_header=",Serial"; [[ ${DISK_STATUS_HIDE_SERIAL} == true ]] && serial_header=""
out=""
while read -r disk; do
    device=$(jq -r '.name' <<< "${disk}")
    label=$(jq -r '.label' <<< "${disk}")
    device_label="${device}"
    [[ ${label} != null ]] && device_label="${device} (${label})"
    capacity=$(jq -r '.size' <<< "${disk}" | numfmt --to si --round nearest)
    model="$(jq -r '.model' <<< "${disk}") (${capacity})"
    serial=$(jq -r '.serial' <<< "${disk}")
    tran=$(jq -r '.tran' <<< "${disk}")
    if smartctl --info "/dev/${device}" | grep -q 'SMART support is: Enabled'; then
        state=$(hdparm -C "/dev/${device}" 2> /dev/null | grep 'drive state is:' | awk -F ':' '{print $2}' | xargs)
        smart_available=true
    else
        state="*"
        smart_available=false
    fi
    temp="*"
    power_on_hours="*"
    health="*"
    temp_color=${white}
    health_color=${white}

    if [[ ${smart_available} == true ]] && [[ ${state} == "active/idle" ]]; then
        json=$(smartctl -n standby -xj "/dev/${device}")
        temp=$(jq -r '.temperature.current' <<< "${json}")
        power_on_hours=$(jq -r '.power_on_time.hours' <<< "${json}")
        health=healthy
        health_color=${green}
        if [[ ${tran} == "sata" ]] || [[ ${tran} == "sas" ]]; then
            pending=$(jq -r '.ata_smart_attributes.table[] | select(.id==197) | .raw.value' <<< "${json}")
            reallocated=$(jq -r '.ata_smart_attributes.table[] | select(.id==5) | .raw.value' <<< "${json}")
            if [[ "${pending}" -gt 0 ]] || [[ "${reallocated}" -gt 0 ]]; then
                health_color=${yellow}
                health="${pending} pending / ${reallocated} reallocated"
            fi
            [[ "${temp}" -ge "0" ]] && temp_color=${green}
            [[ "${temp}" -ge "${WARN_TEMP_HDD}" ]] && temp_color=${yellow}
            [[ "${temp}" -ge "${MAX_TEMP_HDD}" ]] && temp_color=${red}
        fi
        if [[ ${tran} == "nvme" ]]; then
            used=$(jq -r '.nvme_smart_health_information_log.percentage_used' <<< "${json}")
            if [[ "${used}" -ge "${SSD_LIFE_TRESHOLD}" ]]; then
                health_color=${yellow}
                health="$((100-used))% life remaining"
            fi
            [[ "${temp}" -ge "0" ]] && temp_color=${green}
            [[ "${temp}" -ge "${WARN_TEMP_SSD}" ]] && temp_color=${yellow}
            [[ "${temp}" -ge "${MAX_TEMP_SSD}" ]] && temp_color=${red}
        fi
        [[ "${temp}" =~ ^[0-9]+$ ]] && temp="$(printf '%02dC' "$temp")"
    fi

    serial="|${serial}"; [[ ${DISK_STATUS_HIDE_SERIAL} == true ]] && serial=""
    out+="|${device_label}|${tran}|${model}${serial}|${temp_color}${temp}${undim}|${health_color}${health}${undim}|$(displaytime "${power_on_hours}")|${state}|\n"
done < <(lsblk --list --nodeps --bytes --output NAME,LABEL,VENDOR,MODEL,SERIAL,REV,SIZE,TYPE,TRAN --json | jq -r '.blockdevices' | jq -c '.[]|select(.tran=="usb" or .tran=="sata" or .tran=="sas" or .tran=="nvme")')

printf "\ndisk status:\n"
[[ -n ${out} ]] && printf '%b' " ${out}\n" | column -t -o ' | ' -s '|' -N " ,Device,Tran,Model${serial_header},Temp,Health,Power On,State" | grep -v -E "${filter_disks}"
[[ -z ${out} ]] && printf '%b'  "  no physical disks\n"

printf "\n"
