#!/bin/bash
# shellcheck disable=SC1091
# shellcheck disable=SC2034

#######################################################
## CONFIGURATION                                     ##
#######################################################
LOGINS_NUMBER_OF_ROWS=4
DOCKER_NUMBER_OF_COLUMNS=4
VIRTUAL_MACHINES_NUMBER_OF_COLUMNS=3
SYSTEMD_SERVICES_NUMBER_OF_COLUMNS=5
SYSTEMD_SERVICES_MONITOR="ssh,docker"
SMB_SHARES_TABLE_WIDTH=120
IP_ADDRESSES_INTERFACE_FILTER="DONOTFILTER"
#IP_ADDRESSES_INTERFACE_FILTER="eth0|enp1s0"
DISK_SPACE_USAGE_FILTER="DONOTFILTER"
#DISK_SPACE_USAGE_FILTER="user|user0|libvirt|disk"
PHYSICAL_DRIVES_ROW_FILTER="DONOTFILTER"
#PHYSICAL_DRIVES_ROW_FILTER="sda|sas"
PHYSICAL_DRIVES_COLUMN_FILTER="DONOTFILTER"
#PHYSICAL_DRIVES_COLUMN_FILTER="Partitions|Serial|Power On"
#######################################################

#######################################################
## LOAD CONFIGURATION FROM FILE                      ##
#######################################################
[[ -f /etc/default/hotio-sysinfo ]] && source /etc/default/hotio-sysinfo

#######################################################
## COLOR DEFINITIONS                                 ##
#######################################################
Reset='\e[0m'
Bold='\e[1m'
Faint='\e[2m'
Italic='\e[3m'
Underline='\e[4m'

Black='\e[30m'
BBlack='\e[40m'
Red='\e[31m'
BRed='\e[41m'
Green='\e[32m'
BGreen='\e[42m'
Yellow='\e[33m'
BYellow='\e[43m'
Blue='\e[34m'
BBlue='\e[44m'
Magenta='\e[35m'
BMagenta='\e[45m'
Cyan='\e[36m'
BCyan='\e[46m'
LightGray='\e[37m'
BLightGray='\e[47m'
Gray='\e[90m'
BGray='\e[100m'
LightRed='\e[91m'
BLightRed='\e[101m'
LightGreen='\e[92m'
BLightGreen='\e[102m'
LightYellow='\e[93m'
BLightYellow='\e[103m'
LightBlue='\e[94m'
BLightBlue='\e[104m'
LightMagenta='\e[95m'
BLightMagenta='\e[105m'
LightCyan='\e[96m'
BLightCyan='\e[106m'
White='\e[97m'
BWhite='\e[107m'

#######################################################
## FUNCTIONS                                         ##
#######################################################
sec2min() { printf "%d:%02d" "$((10#$1 / 60))" "$((10#$1 % 60))"; }

function displaytime {
    if [[ "${1}" != "" ]]; then
        local T=$1
        local Y=$((T/24/365))
        local D=$((T/24%365))
        local H=$((T%24))
        printf '%02dy ' "${Y}"
        printf '%03dd ' "${D}"
        printf '%02dh' "${H}"
    else
        printf '%s' "${1}"
    fi
}


#######################################################
## SHOW HELP                                         ##
#######################################################
grep -q -e '--' <<< "${*}" && cli_options="${*} "
if grep -q -e '--help' <<< "${cli_options}"; then
    printf '%b' "Available options:\n  --system\n  --ip\n  --thermals\n  --ups\n  --docker\n  --vm\n  --systemd\n  --smb\n  --network\n  --memory\n  --diskspace\n  --drives\n"
    exit 0
fi

#######################################################
## SYSTEM INFO                                       ##
#######################################################
if [[ -z "${cli_options}" ]] || grep -q -e '--system ' <<< "${cli_options}"; then
DISTRO=$(source /etc/os-release && echo "${PRETTY_NAME}")
KERNEL=$(uname -sr)
UPTIME=$(uptime -p)

# get load averages
read -r LOAD1 LOAD5 LOAD15 <<< "$(awk '{print $1,$2,$3}' < /proc/loadavg)"

# get processes
PROCESS=$(ps -eo user= | sort | uniq -c | awk '{print $2,$1}')
PROCESS_ALL=$(awk '{print $2}' <<< "${PROCESS}" | awk '{SUM += $1} END {print SUM}')
PROCESS_USER=$(grep -v root <<< "${PROCESS}" | awk '{print $2}' | awk '{SUM += $1} END {print SUM}')
PROCESS_ROOT=$((PROCESS_ALL - PROCESS_USER))

# get processors
PROCESSOR=$(grep "model name" /proc/cpuinfo | awk -F ':' '{print $2}')
PROCESSOR_NAME=$(head -1 <<< "${PROCESSOR}" | xargs)
PROCESSOR_COUNT=$(wc -l <<< "${PROCESSOR}")

# updates check
if type -p apt > /dev/null; then
    UPDATES="$(apt list --upgradable 2> /dev/null | tail -n+2 | wc -l)"
    [[ "${UPDATES}" -gt 0 ]] && UPDATES_TEXT="\n  Updates    : ${LightYellow}${UPDATES} available${Reset}"
    [[ "${UPDATES}" -eq 0 ]] && UPDATES_TEXT="\n  Updates    : ${UPDATES} available"
else
    UPDATES_TEXT=""
fi

# print results
out="
${BWhite}${Black} system info ${Reset}

  Distro     : ${DISTRO}
  Kernel     : ${KERNEL}
  Uptime     : ${UPTIME}
  CPU        : ${PROCESSOR_NAME} (${Cyan}${PROCESSOR_COUNT}${Reset} vCPU)
  Load       : ${Cyan}${LOAD1}${Reset} (1m), ${Cyan}${LOAD5}${Reset} (5m), ${Cyan}${LOAD15}${Reset} (15m)
  Processes  : ${Cyan}${PROCESS_ROOT}${Reset} (root), ${Cyan}${PROCESS_USER}${Reset} (user), ${Cyan}${PROCESS_ALL}${Reset} (total)${UPDATES_TEXT}
"

printf "%b" "${out}"
fi

#######################################################
## IP ADDRESSES                                      ##
#######################################################
if [[ -z "${cli_options}" ]] || grep -q -e '--ip ' <<< "${cli_options}"; then
out=""
json=$(ip --json addr 2> /dev/null)

while read -r interface; do
    addr=$(jq -r '.[] | select(.ifname == "'"${interface}"'") | .addr_info[] | select(.scope == "global") | .local' <<< "${json}" | sed 's/^/,: /')
    [[ -n ${addr} ]] && out+="  ${interface}" && out+="${addr}\n"
done < <(jq -r '.[].ifname' <<< "${json}" | grep -v -E "${IP_ADDRESSES_INTERFACE_FILTER}")

printf '%b' "\n${BWhite}${Black} ip addresses ${Reset}\n\n"
[[ -n ${out} ]] && printf '%b\n' "${out}" | sed 's/^,:/, /' | column -t -o ' ' -s ','
[[ -z ${out} ]] && printf '%b'  "  none found\n"
fi

#######################################################
## THERMALS                                          ##
#######################################################
if [[ -z "${cli_options}" ]] || grep -q -e '--thermals ' <<< "${cli_options}"; then
out=""
while IFS=',' read -r line; do
    type=$(awk '{print $1}' <<< "${line}")
    temp=$(awk '{print $2}' <<< "${line}")
    out+="  ${type},:,${temp}\n"
done < <(paste <(cat /sys/class/thermal/thermal_zone*/type 2> /dev/null) <(cat /sys/class/thermal/thermal_zone*/temp 2> /dev/null) | column -s ',' -t | sed 's/\(.\)..$/.\1°C/')

printf '%b' "\n${BWhite}${Black} thermals ${Reset}\n\n"
[[ -n ${out} ]] && printf '%b' "${out}" | column -ts ',' -o ' '
[[ -z ${out} ]] && printf '%b'  "  no thermals found\n"
fi

#######################################################
## UPS INFO                                          ##
#######################################################
if [[ -z "${cli_options}" ]] || grep -q -e '--ups ' <<< "${cli_options}"; then
out=""
while read -r line; do
    ups_stats=$(upsc "${line}" 2> /dev/null)
    unset ups_model ups_battery ups_runtime ups_load ups_status
    grep -q ups.model: <<< "${ups_stats}" && ups_model="\n  [$(grep ups.model: <<< "${ups_stats}" | awk -F': ' '{print $2}' | xargs)]\n"
    grep -q battery.charge: <<< "${ups_stats}" && ups_battery="    Battery : $(grep battery.charge: <<< "${ups_stats}" | awk -F': ' '{print $2}')%\n"
    grep -q battery.runtime: <<< "${ups_stats}" && ups_runtime="    Runtime : $(sec2min "$(grep battery.runtime: <<< "${ups_stats}" | awk '{print $2}')") minutes\n"
    grep -q ups.load: <<< "${ups_stats}" && grep -q ups.realpower.nominal: <<< "${ups_stats}" && ups_load="    Load    : $(grep ups.load: <<< "${ups_stats}" | awk '{print $2}')% / $(( $(grep ups.realpower.nominal: <<< "${ups_stats}" | awk '{print $2}')*$(grep ups.load: <<< "${ups_stats}" | awk '{print $2}')/100 ))W\n"
    grep -q ups.status: <<< "${ups_stats}" && ups_status=$(grep ups.status: <<< "${ups_stats}" | awk '{print $2}')
    if [[ "${ups_status}" == "OL" ]]; then
        ups_status="    Status  : ${LightGreen}${ups_status}${Reset}\n"
    elif [[ "${ups_status}" == "CHRG" ]]; then
        ups_status="    Status  : ${LightYellow}${ups_status}${Reset}\n"
    elif [[ -n "${ups_status}" ]]; then
        ups_status="    Status  : ${LightRed}${ups_status}${Reset}\n"
    fi
    out+="${ups_model}${ups_status}${ups_battery}${ups_runtime}${ups_load}"
done < <(sudo grep ^MONITOR /etc/nut/upsmon.conf | awk '{print $2}')

printf '%b' "\n${BWhite}${Black} ups info ${Reset}\n"
[[ -n ${out} ]] && printf '%b' "${out}"
[[ -z ${out} ]] && printf '%b'  "\n  no ups found\n"
fi

#######################################################
## DOCKER                                            ##
#######################################################
if [[ -z "${cli_options}" ]] || grep -q -e '--docker ' <<< "${cli_options}"; then
out=""
while IFS=',' read -r name status; do
    image=$(docker inspect --format='{{.Config.Image}}' "${name}" 2> /dev/null)
    image_digest=$(docker image inspect --format='{{.Id}}' "${image}" 2> /dev/null)
    container_digest=$(docker inspect --format='{{.Image}}' "${name}" 2> /dev/null)
    update_status=""
    [[ "${image_digest}" != "${container_digest}" ]] && update_status=" ${Bold}*${Reset}"
    [[ "${status}" == *"Created"* ]] && status_text="${Bold}x${Reset}"
    [[ "${status}" == *"Exited"* ]]  && status_text="${Bold}${LightRed}x${Reset}"
    [[ "${status}" == *"Up"* ]]      && status_text="${Bold}${LightGreen}>${Reset}"
    [[ "${status}" == *"Paused"* ]]  && status_text="${Bold}${LightYellow}x${Reset}"
    out+="${name}${update_status},${status_text},| "
    if [ $(((i+1) % DOCKER_NUMBER_OF_COLUMNS)) -eq 0 ]; then
        out+="\n"
    fi
    i=$((i+1))
done < <(docker ps --all --format '{{.Names}},{{.Status}}' | sort -k1)

containers_all=$(docker ps --all --format '{{.Names}}' | wc -l)
containers_running=$(docker ps --all --format '{{.Names}}' --filter "status=running" | wc -l)
containers_exited=$(docker ps --all --format '{{.Names}}' --filter "status=exited" | wc -l)
containers_created=$(docker ps --all --format '{{.Names}}' --filter "status=created" | wc -l)
images_all=$(docker images --format '{{.ID}}' | wc -l)
images_dangling=$(docker images --format '{{.ID}}' --filter "dangling=true" | wc -l)

printf '%b' "\n${BWhite}${Black} docker ${Reset}\n\n"
printf "  Containers : %s (%s running, %s exited, %s created)\n" "${containers_all}" "${containers_running}" "${containers_exited}" "${containers_created}"
printf "  Images     : %s (%s dangling)\n\n" "${images_all}" "${images_dangling}"
[[ -n ${out} ]] && printf '%b' "${out}\n" | column -ts ',' -o ' ' | sed -e 's/^/  | /'
[[ -z ${out} ]] && printf '%b'  "  no containers found\n"
fi

#######################################################
## VIRTUAL MACHINES                                  ##
#######################################################
if [[ -z "${cli_options}" ]] || grep -q -e '--vm ' <<< "${cli_options}"; then
virsh_output=$(virsh list --all 2> /dev/null)
column2=$(grep -ob "Name" <<< "${virsh_output}" | grep -oE "[0-9]+")
column3=$(grep -ob "State" <<< "${virsh_output}" | grep -oE "[0-9]+")
column2_length=$((column3-column2))

out=""
while IFS= read -r vm; do
    name=$(xargs <<< "${vm:${column2}:${column2_length}}")
    status=$(xargs <<< "${vm:${column3}}")
    status_text=""
    [[ "${status}" == "running" ]]     && status_text="${Bold}${LightGreen}>${Reset}"
    [[ "${status}" == "paused" ]]      && status_text="${Bold}${LightYellow}x${Reset}"
    [[ "${status}" == "shut off" ]]    && status_text="${Bold}${LightRed}x${Reset}"
    [[ "${status}" == "crashed" ]]     && status_text="${Bold}${LightRed}X${Reset}"
    [[ "${status}" == "pmsuspended" ]] && status_text="${Bold}${LightBlue}zZ${Reset}"
    [[ "${status}" == "idle" ]]        && status_text="${Bold}${LightYellow}o${Reset}"
    [[ "${status}" == "in shutdown" ]] && status_text="${Bold}${LightRed}o${Reset}"
    out+="${name}¥${status_text}¥| "
    if [ $(((i+1) % VIRTUAL_MACHINES_NUMBER_OF_COLUMNS)) -eq 0 ]; then
        out+="\n"
    fi
    i=$((i+1))
done < <(sed -e '1,2d' -e '/^$/d' <<< "${virsh_output}")

printf '%b' "\n${BWhite}${Black} virtual machines ${Reset}\n\n"
[[ -n ${out} ]] && printf '%b' "${out}\n" | column -ts '¥' -o ' ' | sed -e 's/^/  | /'
[[ -z ${out} ]] && printf '%b'  "  no virtual machines found\n"
fi

#######################################################
## SYSTEMD SERVICES                                  ##
#######################################################
if [[ -z "${cli_options}" ]] || grep -q -e '--systemd ' <<< "${cli_options}"; then
type -p systemctl > /dev/null && services="${SYSTEMD_SERVICES_MONITOR}"
out=""
while read -r service; do
    status=$(systemctl is-active "${service}" 2> /dev/null)
    status_text=""
    [[ "${status}" == "active" ]]   && status_text="${Bold}${LightGreen}>${Reset}"
    [[ "${status}" == "inactive" ]] && status_text="${Bold}${LightRed}x${Reset}"
    out+="${service},${status_text},| "
    if [ $(((i+1) % SYSTEMD_SERVICES_NUMBER_OF_COLUMNS)) -eq 0 ]; then
        out+="\n"
    fi
    i=$((i+1))
done < <(tr , '\n' <<< "${services}" | sort | sed -e '/^$/d')

[[ -n ${out} ]] && printf '%b' "\n${BWhite}${Black} systemd services ${Reset}\n\n"
[[ -n ${out} ]] && printf '%b' "${out}\n" | column -ts ',' -o ' ' | sed -e 's/^/  | /'
fi

#######################################################
## SMB SHARES                                        ##
#######################################################
if [[ -z "${cli_options}" ]] || grep -q -e '--smb ' <<< "${cli_options}"; then
out="|${Bold}Share${Reset}|${Bold}Path${Reset}|${Bold}Public${Reset}|${Bold}Writeable${Reset}|${Bold}Valid Users${Reset}|${Bold}Read List${Reset}|${Bold}Write List${Reset}|\n"
while read -r share; do
    share_path=$(testparm -s -v --section-name "${share}" --parameter-name "path" 2> /dev/null)
    public=$(testparm -s -v --section-name "${share}" --parameter-name "public" 2> /dev/null)
    if [[ "${public,,}" == "no" ]]; then public="x"; else public="v"; fi
    writeable=$(testparm -s -v --section-name "${share}" --parameter-name "writeable" 2> /dev/null)
    if [[ "${writeable,,}" == "no" ]]; then writeable="x"; else writeable="v"; fi
    valid_users=$(testparm -s -v --section-name "${share}" --parameter-name "valid users" 2> /dev/null)
    read_list=$(testparm -s -v --section-name "${share}" --parameter-name "read list" 2> /dev/null)
    write_list=$(testparm -s -v --section-name "${share}" --parameter-name "write list" 2> /dev/null)
    out+="|${share}|${share_path}|${public}|${writeable}|${valid_users}|${read_list}|${write_list}|\n"
done < <(testparm -s 2> /dev/null | grep '\[.*\]' | grep -v -E "global|homes|printers" | sed -e 's/\[//' -e 's/\]//')

printf '%b' "\n${BWhite}${Black} smb shares ${Reset}\n\n"
[[ $(echo -e "${out}" | wc -l) -gt 2 ]] && printf '%b' " ${out}" | column -t -o ' | ' -s '|' --table-wrap 6,7,8 --output-width "${SMB_SHARES_TABLE_WIDTH}"
[[ $(echo -e "${out}" | wc -l) -eq 2 ]] && printf '%b'  "  no shares exported\n"
fi

#######################################################
## NETWORK TRAFFIC                                   ##
#######################################################
if [[ -z "${cli_options}" ]] || grep -q -e '--network ' <<< "${cli_options}"; then
out="|||${Bold}Rx${Reset}|${Bold}Tx${Reset}|${Bold}Total${Reset}|\n"
while read -r interface; do
    out+="|${Bold}${interface}${Reset}|||||\n"
    results=$(vnstat --oneline "${interface}" 2> /dev/null)
    # today
    rx=$(awk -F ";" '{print $4}' <<< "${results}")
    tx=$(awk -F ";" '{print $5}' <<< "${results}")
    total=$(awk -F ";" '{print $6}' <<< "${results}")
    out+="||Today|${rx}|${tx}|${total}|\n"

    # this month
    rx=$(awk -F ";" '{print $9}' <<< "${results}")
    tx=$(awk -F ";" '{print $10}' <<< "${results}")
    total=$(awk -F ";" '{print $11}' <<< "${results}")
    out+="||This Month|${rx}|${tx}|${total}|\n"

    # total
    rx=$(awk -F ";" '{print $13}' <<< "${results}")
    tx=$(awk -F ";" '{print $14}' <<< "${results}")
    total=$(awk -F ";" '{print $15}' <<< "${results}")
    out+="||Total|${rx}|${tx}|${total}|\n"
done < <(vnstat --json 2> /dev/null | jq -r '.interfaces | .[].name')

[[ $(echo -e "${out}" | wc -l) -gt 2 ]] && printf '%b' "\n${BWhite}${Black} network traffic ${Reset}\n\n"
[[ $(echo -e "${out}" | wc -l) -gt 2 ]] && printf '%b' " ${out}" | column -t -R '4,5,6' -o ' | ' -s '|'
fi

#######################################################
## MEMORY USAGE                                      ##
#######################################################
if [[ -z "${cli_options}" ]] || grep -q -e '--memory ' <<< "${cli_options}"; then
max_usage=95
warn_usage=80
bar_width=52

printf '%b' "\n${BWhite}${Black} memory usage ${Reset}\n\n"
while read -r line; do
    title=$(awk -F ':' '{print $1}' <<< "${line}")
    total=$(awk '{print $2}' <<< "${line}")
    usage=$(awk '{print $3}' <<< "${line}")
    usage_perc=$(((usage*100)/total))
    used_width=$(((usage_perc*bar_width)/100))

    [[ "${usage_perc}" -ge "0" ]]             && color="${Cyan}"
    [[ "${usage_perc}" -ge "${warn_usage}" ]] && color="${LightYellow}"
    [[ "${usage_perc}" -ge "${max_usage}" ]]  && color="${LightRed}"

    bar="${color}"
    for ((i=0; i<used_width; i++)); do
        bar+="="
    done
    bar+="${Reset}${Faint}"
    for ((i=used_width; i<bar_width; i++)); do
        bar+="="
    done
    bar+="${Reset}"

    total=$(numfmt --to iec-i --format "%f" "${total}")
    printf "  %-31s%+3s used out of %+5s\n" "${title,,}" "${usage_perc}%" "${total}"
    printf "  %b\n" "${bar}"
done < <(free --bytes | awk '$2 != 0' | tail -n+2)
fi

#######################################################
## DISK SPACE USAGE                                  ##
#######################################################
if [[ -z "${cli_options}" ]] || grep -q -e '--diskspace ' <<< "${cli_options}"; then
max_usage=95
warn_usage=80
bar_width=52

printf '%b' "\n${BWhite}${Black} disk space usage ${Reset}\n\n"
while read -r line; do
    usage_perc=$(awk '{print $2}' <<< "${line}"| sed 's/%//')
    used_width=$(((usage_perc*bar_width)/100))

    [[ "${usage_perc}" -ge "0" ]]             && color="${Cyan}"
    [[ "${usage_perc}" -ge "${warn_usage}" ]] && color="${LightYellow}"
    [[ "${usage_perc}" -ge "${max_usage}" ]]  && color="${LightRed}"

    bar="${color}"
    for ((i=0; i<used_width; i++)); do
        bar+="="
    done
    bar+="${Reset}${Faint}"
    for ((i=used_width; i<bar_width; i++)); do
        bar+="="
    done
    bar+="${Reset}"

    awk '{ printf("  %-32s%+3s used out of %+4s\n", $1, $2, $3); }' <<< "${line}"
    printf "  %b\n" "${bar}"
done < <(df -H -x squashfs -x tmpfs -x devtmpfs -x overlay --output=target,pcent,size | grep -v -E "${DISK_SPACE_USAGE_FILTER}" | tail -n+2)
fi

#######################################################
## PHYSICAL DRIVES                                   ##
#######################################################
if [[ -z "${cli_options}" ]] || grep -q -e '--drives ' <<< "${cli_options}"; then
WARN_TEMP_HDD=35
MAX_TEMP_HDD=40
WARN_TEMP_NVME=40
MAX_TEMP_NVME=60
LIFE_TRESHOLD_NVME=90

headers="Dev\nPartitions\nTran\nModel\nSize\nSerial\nRev\nTemp\nHealth\nPower On"
while read -r header; do
    echo -n "$header" | grep -q -E "${PHYSICAL_DRIVES_COLUMN_FILTER}" || table_headers+="|${Bold}${header}${Reset}"
done < <(echo -e "${headers}")
out="|${table_headers}|\n"

while read -r disk; do
    unset path state device part tran model size serial revision temp health poweron pending reallocatd used_life

    path=$(jq -r '.path // empty' <<< "${disk}")
    device=$(jq -r '.name // empty' <<< "${disk}")
    part=$(jq -re 'try .children[] | select(.type == "part") | "\(.name)[\(.fstype // ""):\(.label // "")]"' <<< "${disk}" | awk 'NR > 1 { printf(", ") } {printf "%s",$0}' | sed -e 's/\[:/\[/g' -e 's/:]/]/g' -e 's/\[]//g')
    tran=$(jq -r '.tran // empty' <<< "${disk}")
    model=$(jq -r '.model // empty' <<< "${disk}")
    size=$(printf "%4s" "$(jq -r '.size // empty' <<< "${disk}" | numfmt --to si --round nearest)")
    serial=$(jq -r '.serial // empty' <<< "${disk}")
    revision=$(jq -r '.rev // empty' <<< "${disk}")

    if sudo smartctl --info "${path}" | grep -q 'SMART support is: Enabled'; then
        state=$(sudo hdparm -C "${path}" 2> /dev/null | grep 'drive state is:' | awk -F ':' '{print $2}' | xargs)
    fi

    if [[ "${state}" == "active/idle" ]]; then
        json=$(sudo smartctl -n standby -xj "${path}")
        temp=$(jq -r '.temperature.current' <<< "${json}")
        health="${LightGreen}ok${Reset}"
        poweron="$(displaytime "$(jq -r '.power_on_time.hours' <<< "${json}")")"
        if [[ "${tran}" == "sata" ]] || [[ "${tran}" == "sas" ]]; then
            pending=$(jq -r '.ata_smart_attributes.table[] | select(.id==197) | .raw.value' <<< "${json}")
            reallocated=$(jq -r '.ata_smart_attributes.table[] | select(.id==5) | .raw.value' <<< "${json}")
            if [[ "${pending}" -gt 0 ]] || [[ "${reallocated}" -gt 0 ]]; then
                health="${LightYellow}${pending} pending / ${reallocated} reallocated${Reset}"
            fi
            if [[ "${temp}" -ge "${MAX_TEMP_HDD}" ]]; then
                temp="${LightRed}$(printf '%02d°C' "${temp}")${Reset}"
            elif [[ "${temp}" -ge "${WARN_TEMP_HDD}" ]]; then
                temp="${LightYellow}$(printf '%02d°C' "${temp}")${Reset}"
            else
                temp="${LightGreen}$(printf '%02d°C' "${temp}")${Reset}"
            fi
        fi
        if [[ "${tran}" == "nvme" ]]; then
            used_life=$(jq -r '.nvme_smart_health_information_log.percentage_used' <<< "${json}")
            if [[ "${used_life}" -ge "${LIFE_TRESHOLD_NVME}" ]]; then
                health="${LightYellow}$((100-used_life))% life remaining${Reset}"
            fi
            if [[ "${temp}" -ge "${MAX_TEMP_NVME}" ]]; then
                temp="${LightRed}$(printf '%02d°C' "${temp}")${Reset}"
            elif [[ "${temp}" -ge "${WARN_TEMP_NVME}" ]]; then
                temp="${LightYellow}$(printf '%02d°C' "${temp}")${Reset}"
            else
                temp="${LightGreen}$(printf '%02d°C' "${temp}")${Reset}"
            fi
        fi
    fi

    if [[ "${state}" == "active/idle" ]]; then
        state="${Bold}${LightGreen}o${Reset}"
    elif [[ "${state}" == "standby" ]]; then
        state="${Faint}o${Reset}"
    else
        state="${Faint}-${Reset}"
    fi

    unset table_data
    while read -r header; do
        echo -n "$header" | grep -q -E "${PHYSICAL_DRIVES_COLUMN_FILTER}" && continue
        [[ "${header}" == "Dev"* ]]        && table_data+="|${device}"
        [[ "${header}" == "Partitions"* ]] && table_data+="|${part}"
        [[ "${header}" == "Tran"* ]]       && table_data+="|${tran}"
        [[ "${header}" == "Model"* ]]      && table_data+="|${model}"
        [[ "${header}" == "Size"* ]]       && table_data+="|${size}"
        [[ "${header}" == "Serial"* ]]     && table_data+="|${serial}"
        [[ "${header}" == "Rev"* ]]        && table_data+="|${revision}"
        [[ "${header}" == "Temp"* ]]       && table_data+="|${temp}"
        [[ "${header}" == "Health"* ]]     && table_data+="|${health}"
        [[ "${header}" == "Power On"* ]]   && table_data+="|${poweron}"
    done < <(echo -e "${headers}")
    out+="|${state}${table_data}|\n"
done < <(lsblk --json --bytes --output PATH,NAME,MODEL,SERIAL,REV,SIZE,TYPE,TRAN,LABEL,FSTYPE | jq -r '.blockdevices[]' | jq -c 'select(.type=="disk")')

printf '%b' "\n${BWhite}${Black} physical drives ${Reset}\n\n"
[[ $(echo -e "${out}" | wc -l) -gt 2 ]] && printf '%b' " ${out}\n" | column -t -o ' | ' -s '|' | grep -v -E "${PHYSICAL_DRIVES_ROW_FILTER}"
[[ $(echo -e "${out}" | wc -l) -eq 2 ]] && printf '%b'  "  no physical drives found\n"
fi

#######################################################
## THE END                                           ##
#######################################################
printf "\n"
