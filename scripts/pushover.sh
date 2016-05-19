#!/bin/bash

echo $MONIT_DATE >> /tmp/test1.log
echo $MONIT_EVENT >> /tmp/test1.log
echo $MONIT_PROCESS_PID >> /tmp/test1.log
echo $MONIT_PROCESS_MEMORY >> /tmp/test1.log
echo $MONIT_PROCESS_CHILDREN >> /tmp/test1.log
echo $MONIT_PROCESS_CPU_PERCENT >> /tmp/test1.log
echo $MONIT_PROGRAM_STATUS >> /tmp/test1.log
echo $MONIT_DESCRIPTION >> /tmp/test1.log
echo $MONIT_EVENT >> /tmp/test1.log
echo $MONIT_HOST >> /tmp/test1.log
echo $MONIT_SERVICE >> /tmp/test1.log

# Variables and example available in this script.
#
#     HOME=/root
#     HOSTNAME=58f0036eb993
#     HTTPS_PORT=http://192.168.99.1:3128
#     HTTP_PORT=http://192.168.99.1:3128
#     MONIT_DATE=Wed, 18 May 2016 15:03:28
#     MONIT_EVENT=
#     MONIT_PROCESS_PID
#     MONIT_PROCESS_MEMORY
#     MONIT_PROCESS_CHILDREN
#     MONIT_PROCESS_CPU_PERCENT
#     MONIT_PROGRAM_STATUS
#     MONIT_DESCRIPTION=mem usage of 70.8% matches resource limit [mem usage<20.0%]
#     MONIT_EVENT=Resource limit matched
#     MONIT_HOST=ss.easypi.info
#     MONIT_SERVICE=ss.easypi.info
#     PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
#     PWD=/
#     SHLVL=1
#     _=/usr/bin/env
#     affinity:container==f17e7f606c715f2d9126b4c9fb556d074afbfb02aa35f930cf719c8b4be4e009
#     http_proxy=http://192.168.99.1:3128
#     https_proxy=http://192.168.99.1:3128

# Default config vars
CURL="$(which curl)"
PUSHOVER_URL="https://api.pushover.net/1/messages.json"
PUSHOVER_TOKEN="" # May be set in pushover.conf or given on command line
PUSHOVER_USER="" # May be set in pushover.conf or given on command line
CURL_OPTS=""
BASH_MAJOR="$(echo $BASH_VERSION | cut -d'.' -f1)"
if [ "${BASH_MAJOR}" -lt 4 ]; then
    device_aliases=""
else
    declare -A device_aliases=()
fi

# Load user config
if [ ! -z "${PUSHOVER_CONFIG}" ]; then
    CONFIG_FILE="${PUSHOVER_CONFIG}"
else
    CONFIG_FILE="${XDG_CONFIG_HOME-${HOME}/.config}/pushover.conf"
fi

if [ -e "${CONFIG_FILE}" ]; then
    . "${CONFIG_FILE}"
fi

# Functions used elsewhere in this script
usage() {
    echo "${0} <options> <message>"
    echo " -c <callback>"
    echo " -d <device>"
    echo " -D <timestamp>"
    echo " -e <expire>"
    echo " -p <priority>"
    echo " -r <retry>"
    echo " -t <title>"
    echo " -T <PUSHOVER_TOKEN> (required if not in config file)"
    echo " -s <sound>"
    echo " -u <url>"
    echo " -U <PUSHOVER_USER> (required if not in config file)"
    echo " -a <url_title>"
    exit 1
}
opt_field() {
    field=$1
    shift
    value="${*}"
    if [ ! -z "${value}" ]; then
        echo "-F \"${field}=${value}\""
    fi
}
validate_token() {
	field="${1}"
	value="${2}"
	opt="${3}"
	ret=1
	if [ -z "${value}" ]; then
		echo "${field} is unset or empty: Did you create ${CONFIG_FILE} or specify ${opt} on the command line?" >&2
	elif ! echo "${value}" | egrep -q '[A-Za-z0-9]{30}'; then
		echo "Value of ${field}, \"${value}\", does not match expected format. Should be 30 characters of A-Z, a-z and 0-9." >&2;
	else
		ret=0
	fi
	return ${ret}
}
expand_aliases() {
    if [ "${BASH_MAJOR}" -lt 4 ]; then
        if [ ! -z "${device_aliases}" ]; then
            echo "Warning: device_aliases are only support by bash 4+" >&2
        fi
        echo "${*}"
    else
        for device in ${*}; do
            expanded="${device_aliases["${device}"]}"
            if [ -z "${expanded}" ]; then
                echo "${device}"
            else
                echo "${expanded}"
            fi
        done
    fi
}
remove_duplicates() {
    echo ${*} | xargs -n1 | sort -u | uniq
}
send_message() {
    local device="${1:-}"

    curl_cmd="\"${CURL}\" -s -S \
        ${CURL_OPTS} \
        -F \"token=${PUSHOVER_TOKEN}\" \
        -F \"user=${PUSHOVER_USER}\" \
        -F \"message=${message}\" \
        $(opt_field device "${device}") \
        $(opt_field callback "${callback}") \
        $(opt_field timestamp "${timestamp}") \
        $(opt_field priority "${priority}") \
        $(opt_field retry "${retry}") \
        $(opt_field expire "${expire}") \
        $(opt_field title "${title}") \
        $(opt_field sound "${sound}") \
        $(opt_field url "${url}") \
        $(opt_field url_title "${url_title}") \
        \"${PUSHOVER_URL}\""

    # execute and return exit code from curl command
    response="$(eval "${curl_cmd}")"

    # TODO: Parse response for value of status to give better error to user
    r="${?}"
    if [ "${r}" -ne 0 ]; then
        echo "${0}: Failed to send message" >&2
    fi

    return "${r}"
}

# Initialize devices
devices="${devices} ${device}"

# Option parsing
optstring="c:d:D:e:p:r:t:T:s:u:U:a:h"
while getopts ${optstring} c; do
    case ${c} in
        c) callback="${OPTARG}" ;;
        d) devices="${devices} ${OPTARG}" ;;
        D) timestamp="${OPTARG}" ;;
        e) expire="${OPTARG}" ;;
        p) priority="${OPTARG}" ;;
        r) retry="${OPTARG}" ;;
        t) title="${OPTARG}" ;;
        T) PUSHOVER_TOKEN="${OPTARG}" ;;
        s) sound="${OPTARG}" ;;
        u) url="${OPTARG}" ;;
        U) PUSHOVER_USER="${OPTARG}" ;;
        a) url_title="${OPTARG}" ;;

        [h\?]) usage ;;
    esac
done
shift $((OPTIND-1))

# Is there anything left?
if [ "$#" -lt 1 ]; then
    usage
fi
message="$*"

# Check for required config variables
if [ ! -x "${CURL}" ]; then
    echo "CURL is unset, empty, or does not point to curl executable. This script requires curl!" >&2
    exit 1
fi
validate_token "PUSHOVER_TOKEN" "${PUSHOVER_TOKEN}" "-T" || exit $?
validate_token "PUSHOVER_USER" "${PUSHOVER_USER}" "-U" || exit $?

devices="$(expand_aliases ${devices})"
devices="$(remove_duplicates ${devices})"

if [ -z "${devices}" ]; then
    send_message
    r=${?}
else
    for device in ${devices}; do
        send_message "${device}"
        r=${?}
        if [ "${r}" -ne 0 ]; then
            break;
        fi
    done
fi
exit "${r}"
