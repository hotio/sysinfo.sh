#!/bin/bash
# shellcheck disable=SC1091
# shellcheck disable=SC2034

#######################################################
## CONFIGURATION                                     ##
#######################################################
COLUMNS_DOCKER=4
COLUMNS_VM=3
COLUMNS_SYSTEMD=5
SMB_TABLE_WIDTH=120
SYSTEMD_SERVICES_MONITOR="ssh,docker"
IP_ADDRESSES_INTERFACE_FILTER="DONOTFILTER"
#IP_ADDRESSES_INTERFACE_FILTER="eth0|enp1s0"
DISK_SPACE_USAGE_FILTER="DONOTFILTER"
#DISK_SPACE_USAGE_FILTER="user|user0|libvirt|disk"
PHYSICAL_DRIVES_ROW_FILTER="DONOTFILTER"
#PHYSICAL_DRIVES_ROW_FILTER="sda|sas"
PHYSICAL_DRIVES_COLUMN_FILTER="DONOTFILTER"
#PHYSICAL_DRIVES_COLUMN_FILTER="Label|Serial|Power On"
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
## SYSTEM INFO                                       ##
#######################################################
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
    [[ "${UPDATES}" -gt 0 ]] && UPDATES_TEXT="\n  Updates   : ${LightYellow}${UPDATES} available${Reset}"
    [[ "${UPDATES}" -eq 0 ]] && UPDATES_TEXT="\n  Updates   : ${UPDATES} available"
else
    UPDATES_TEXT=""
fi

# print results
out="
${BWhite}${Black} system info ${Reset}

  Distro    : ${DISTRO}
  Kernel    : ${KERNEL}
  Uptime    : ${UPTIME}
  CPU       : ${PROCESSOR_NAME} (${Cyan}${PROCESSOR_COUNT}${Reset} vCPU)
  Load      : ${Cyan}${LOAD1}${Reset} (1m), ${Cyan}${LOAD5}${Reset} (5m), ${Cyan}${LOAD15}${Reset} (15m)
  Processes : ${Cyan}${PROCESS_ROOT}${Reset} (root), ${Cyan}${PROCESS_USER}${Reset} (user), ${Cyan}${PROCESS_ALL}${Reset} (total)${UPDATES_TEXT}
"

printf "%b" "${out}"

#######################################################
## IP ADDRESSES                                      ##
#######################################################
out=""
json=$(ip --json addr 2> /dev/null)

while read -r interface; do
    addr=$(jq -r '.[] | select(.ifname == "'"${interface}"'") | .addr_info[] | select(.scope == "global") | .local' <<< "${json}" | sed 's/^/,: /')
    [[ -n ${addr} ]] && out+="  ${interface}" && out+="${addr}\n"
done < <(jq -r '.[].ifname' <<< "${json}" | grep -v -E "${IP_ADDRESSES_INTERFACE_FILTER}")

printf '%b' "\n${BWhite}${Black} ip addresses ${Reset}\n\n"
[[ -n ${out} ]] && printf '%b\n' "${out}" | sed 's/^,:/, /' | column -t -o ' ' -s ','
[[ -z ${out} ]] && printf '%b'  "  none found\n"

#######################################################
## THERMALS                                          ##
#######################################################
out=""
while IFS=',' read -r line; do
    type=$(awk '{print $1}' <<< "${line}")
    temp=$(awk '{print $2}' <<< "${line}")
    out+="  ${type},:,${temp}\n"
done < <(paste <(cat /sys/class/thermal/thermal_zone*/type 2> /dev/null) <(cat /sys/class/thermal/thermal_zone*/temp 2> /dev/null) | column -s ',' -t | sed 's/\(.\)..$/.\1°C/')

printf '%b' "\n${BWhite}${Black} thermals ${Reset}\n\n"
[[ -n ${out} ]] && printf '%b' "${out}" | column -ts ',' -o ' '
[[ -z ${out} ]] && printf '%b'  "  no thermals found\n"

#######################################################
## UPS INFO                                          ##
#######################################################
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
done < <(grep ^MONITOR /etc/nut/upsmon.conf | awk '{print $2}')

printf '%b' "\n${BWhite}${Black} ups info ${Reset}\n"
[[ -n ${out} ]] && printf '%b' "${out}"
[[ -z ${out} ]] && printf '%b'  "\n  no ups found\n"

#######################################################
## DOCKER                                            ##
#######################################################
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
    if [ $(((i+1) % COLUMNS_DOCKER)) -eq 0 ]; then
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

#######################################################
## VIRTUAL MACHINES                                  ##
#######################################################
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
    if [ $(((i+1) % COLUMNS_VM)) -eq 0 ]; then
        out+="\n"
    fi
    i=$((i+1))
done < <(sed -e '1,2d' -e '/^$/d' <<< "${virsh_output}")

printf '%b' "\n${BWhite}${Black} virtual machines ${Reset}\n\n"
[[ -n ${out} ]] && printf '%b' "${out}\n" | column -ts '¥' -o ' ' | sed -e 's/^/  | /'
[[ -z ${out} ]] && printf '%b'  "  no virtual machines found\n"

#######################################################
## SYSTEMD SERVICES                                  ##
#######################################################
type -p systemctl > /dev/null && services="${SYSTEMD_SERVICES_MONITOR}"
out=""
while read -r service; do
    status=$(systemctl is-active "${service}" 2> /dev/null)
    status_text=""
    [[ "${status}" == "active" ]]   && status_text="${Bold}${LightGreen}>${Reset}"
    [[ "${status}" == "inactive" ]] && status_text="${Bold}${LightRed}x${Reset}"
    out+="${service},${status_text},| "
    if [ $(((i+1) % COLUMNS_SYSTEMD)) -eq 0 ]; then
        out+="\n"
    fi
    i=$((i+1))
done < <(tr , '\n' <<< "${services}" | sort | sed -e '/^$/d')

[[ -n ${out} ]] && printf '%b' "\n${BWhite}${Black} systemd services ${Reset}\n\n"
[[ -n ${out} ]] && printf '%b' "${out}\n" | column -ts ',' -o ' ' | sed -e 's/^/  | /'

#######################################################
## SMB SHARES                                        ##
#######################################################
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
[[ $(echo -e "${out}" | wc -l) -gt 2 ]] && printf '%b' " ${out}" | column -t -o ' | ' -s '|' --table-wrap 6,7,8 --output-width "${SMB_TABLE_WIDTH}"
[[ $(echo -e "${out}" | wc -l) -eq 2 ]] && printf '%b'  "  no shares exported\n"

#######################################################
## NETWORK TRAFFIC                                   ##
#######################################################
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

#######################################################
## MEMORY USAGE                                      ##
#######################################################
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

#######################################################
## DISK SPACE USAGE                                  ##
#######################################################
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

#######################################################
## PHYSICAL DRIVES                                   ##
#######################################################
WARN_TEMP_HDD=35
MAX_TEMP_HDD=40
WARN_TEMP_SSD=40
MAX_TEMP_SSD=60
SSD_LIFE_TRESHOLD=90

state_header="|"
device_header="|${Bold}Device${Reset}";    grep -q -E "${PHYSICAL_DRIVES_COLUMN_FILTER}" <<< "Device"   && device_header=""
label_header="|${Bold}Label${Reset}";      grep -q -E "${PHYSICAL_DRIVES_COLUMN_FILTER}" <<< "Label"    && label_header=""
tran_header="|${Bold}Tran${Reset}";        grep -q -E "${PHYSICAL_DRIVES_COLUMN_FILTER}" <<< "Tran"     && tran_header=""
model_header="|${Bold}Model${Reset}";      grep -q -E "${PHYSICAL_DRIVES_COLUMN_FILTER}" <<< "Model"    && model_header=""
serial_header="|${Bold}Serial${Reset}";    grep -q -E "${PHYSICAL_DRIVES_COLUMN_FILTER}" <<< "Serial"   && serial_header=""
temp_header="|${Bold}Temp${Reset}";        grep -q -E "${PHYSICAL_DRIVES_COLUMN_FILTER}" <<< "Temp"     && temp_header=""
health_header="|${Bold}Health${Reset}";    grep -q -E "${PHYSICAL_DRIVES_COLUMN_FILTER}" <<< "Health"   && health_header=""
poweron_header="|${Bold}Power On${Reset}"; grep -q -E "${PHYSICAL_DRIVES_COLUMN_FILTER}" <<< "Power On" && poweron_header=""

out="${state_header}${device_header}${label_header}${tran_header}${model_header}${serial_header}${temp_header}${health_header}${poweron_header}|\n"

while read -r disk; do
    device=$(jq -r '.name' <<< "${disk}")
    label=$(jq -r '.label' <<< "${disk}"); [[ "${label}" == null ]] && label=""
    capacity=$(jq -r '.size' <<< "${disk}" | numfmt --to si --round nearest)
    model="$(jq -r '.model' <<< "${disk}") (${capacity})"
    serial=$(jq -r '.serial' <<< "${disk}")
    tran=$(jq -r '.tran' <<< "${disk}")
    if smartctl --info "/dev/${device}" | grep -q 'SMART support is: Enabled'; then
        state=$(hdparm -C "/dev/${device}" 2> /dev/null | grep 'drive state is:' | awk -F ':' '{print $2}' | xargs)
        smart_available=true
    else
        state=""
        smart_available=false
    fi
    temp=""
    power_on_hours=""
    health=""
    temp_color=""
    health_color=""

    if [[ "${smart_available}" == true ]] && [[ "${state}" == "active/idle" ]]; then
        json=$(smartctl -n standby -xj "/dev/${device}")
        temp=$(jq -r '.temperature.current' <<< "${json}")
        power_on_hours=$(jq -r '.power_on_time.hours' <<< "${json}")
        health="ok"
        health_color="${LightGreen}"
        if [[ "${tran}" == "sata" ]] || [[ "${tran}" == "sas" ]]; then
            pending=$(jq -r '.ata_smart_attributes.table[] | select(.id==197) | .raw.value' <<< "${json}")
            reallocated=$(jq -r '.ata_smart_attributes.table[] | select(.id==5) | .raw.value' <<< "${json}")
            if [[ "${pending}" -gt 0 ]] || [[ "${reallocated}" -gt 0 ]]; then
                health_color="${LightYellow}"
                health="${pending} pending / ${reallocated} reallocated"
            fi
            [[ "${temp}" -ge "0" ]]                && temp_color="${LightGreen}"
            [[ "${temp}" -ge "${WARN_TEMP_HDD}" ]] && temp_color="${LightYellow}"
            [[ "${temp}" -ge "${MAX_TEMP_HDD}" ]]  && temp_color="${LightRed}"
        fi
        if [[ "${tran}" == "nvme" ]]; then
            used=$(jq -r '.nvme_smart_health_information_log.percentage_used' <<< "${json}")
            if [[ "${used}" -ge "${SSD_LIFE_TRESHOLD}" ]]; then
                health_color="${LightYellow}"
                health="$((100-used))% life remaining"
            fi
            [[ "${temp}" -ge "0" ]] && temp_color="${LightGreen}"
            [[ "${temp}" -ge "${WARN_TEMP_SSD}" ]] && temp_color="${LightYellow}"
            [[ "${temp}" -ge "${MAX_TEMP_SSD}" ]]  && temp_color="${LightRed}"
        fi
        [[ "${temp}" =~ ^[0-9]+$ ]] && temp="$(printf '%02d°C' "${temp}")"
    fi
    [[ "${state}" == "active/idle" ]] && state="${Bold}${LightGreen}o${Reset}"
    [[ "${state}" == "standby" ]]     && state="${Faint}o${Reset}"

    state="|${state}"
    device="|${device}";                           grep -q -E "${PHYSICAL_DRIVES_COLUMN_FILTER}" <<< "Device"   && device=""
    label="|${label}";                             grep -q -E "${PHYSICAL_DRIVES_COLUMN_FILTER}" <<< "Label"    && label=""
    tran="|${tran}";                               grep -q -E "${PHYSICAL_DRIVES_COLUMN_FILTER}" <<< "Tran"     && tran=""
    model="|${model}";                             grep -q -E "${PHYSICAL_DRIVES_COLUMN_FILTER}" <<< "Model"    && model=""
    serial="|${serial}";                           grep -q -E "${PHYSICAL_DRIVES_COLUMN_FILTER}" <<< "Serial"   && serial=""
    temp="|${temp_color}${temp}${Reset}";          grep -q -E "${PHYSICAL_DRIVES_COLUMN_FILTER}" <<< "Temp"     && temp=""
    health="|${health_color}${health}${Reset}";    grep -q -E "${PHYSICAL_DRIVES_COLUMN_FILTER}" <<< "Health"   && health=""
    poweron="|$(displaytime "${power_on_hours}")"; grep -q -E "${PHYSICAL_DRIVES_COLUMN_FILTER}" <<< "Power On" && poweron=""

    out+="${state}${device}${label}${tran}${model}${serial}${temp}${health}${poweron}|\n"

done < <(lsblk --list --nodeps --bytes --output NAME,LABEL,VENDOR,MODEL,SERIAL,REV,SIZE,TYPE,TRAN --json | jq -r '.blockdevices' | jq -c '.[]|select(.tran=="usb" or .tran=="sata" or .tran=="sas" or .tran=="nvme")')

printf '%b' "\n${BWhite}${Black} physical drives ${Reset}\n\n"
[[ $(echo -e "${out}" | wc -l) -gt 2 ]] && printf '%b' " ${out}\n" | column -t -o ' | ' -s '|' | grep -v -E "${PHYSICAL_DRIVES_ROW_FILTER}"
[[ $(echo -e "${out}" | wc -l) -eq 2 ]] && printf '%b'  "  no physical drives found\n"

#######################################################
## THE END                                           ##
#######################################################
printf "\n"
