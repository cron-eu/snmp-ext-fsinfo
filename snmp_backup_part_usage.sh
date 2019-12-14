#!/bin/bash

##
# SNMP helper script to extract the free and block count for a specific backup partition
#
# see https://stackoverflow.com/questions/16365940/snmp-extend-as-an-integer-and-not-a-string
#

OID_ROOT=".1.3.6.1.3.1" # SNMPv2-SMI::experimental.1

# SNMPv2-SMI::experimental.1.1 => count
# SNMPv2-SMI::experimental.1.1 => INTEGER count

# SNMPv2-SMI::experimental.1.2.x.1 => STRING hostname
# SNMPv2-SMI::experimental.1.2.x.2 => STRING uuid
# SNMPv2-SMI::experimental.1.2.x.3 => Counter64 total size
# SNMPv2-SMI::experimental.1.2.x.4 => Counter64 free size

#

cd /backup/RSYNC-BACKUP || exit 1

# backup_dirs is an array like ( www.backup1.tld www.backup2.tld .. )
readarray -t backup_dirs <<<"$(ls .)"

OPTIND=1 # Reset in case getopts has been used previously in the shell.

OID=""
ACTION=""

function show_help() {
  echo "Usage: $0 [ -g OID ] [ -n OID ]"
  exit 1
}

function snmp_out() {
  echo "${OID_ROOT}.$1"
  echo "$2"
  echo "$3"
}

function resolve_device() {
  dirname=$1
  link=$(basename "$(readlink "$dirname")")
  echo "/dev/disk/by-uuid/$link"
}

function nagios_string() {
  device=$1
  tune2fs -l "$device" | awk -F: '/^Free blocks/ { free=$2 } /^Block count/ { total=$2 } /^Last write time/ { gsub(/^[^:]*: +/,""); timestamp=$0 } END { print total ";" (total-free) ";" 1-free/total ";" timestamp }'
}

function process_snmp_get() {

  oid="$1"
  IFS="." read -ra oid_a <<<"$oid"

  # SNMPv2-SMI::experimental.1.1
  case "${oid_a[0]}" in
  1)
    snmp_out "$oid" "INTEGER" "${#backup_dirs[@]}"
    ;;

  # SNMPv2-SMI::experimental.1.2.<device_no>.<param>
  2)
    device_no="${oid_a[1]}"
    param="${oid_a[2]}"
    backup_dir="${backup_dirs[$device_no]}"

    case "${param}" in
    1)
      snmp_out "$oid" "STRING" "$backup_dir"
      ;;

    2)
      device=$(resolve_device "$backup_dir")
      snmp_out "$oid" "STRING" "$device"
      ;;

    [3-4])
      device=$(resolve_device "$backup_dir")
      index="$(( param - 3 ))"

      if [ -e "$device" ]; then
        nagios_string="$(nagios_string "$device")"
        IFS=";" read -ra nagios_a <<<"$nagios_string"
        snmp_out "$oid" "INTEGER" "${nagios_a[$index]}"
      else
        snmp_out "$oid" "INTEGER" "0"
      fi
      ;;

    esac

    ;;
  esac
}

function process_snmp_next() {
  oid="$1"
  IFS="." read -ra oid_a <<<"$oid"
  # SNMPv2-SMI::experimental.1.1

  if [ -z "${oid_a[0]}" ]; then
    process_snmp_get "1"
  else
    case "${oid_a[0]}" in
    1)
      process_snmp_get "2.0.1"
      ;;

    2)
      device_no="${oid_a[1]}"
      param="${oid_a[2]}"

      if [ "${param}" -lt 4 ]; then
        next_param="$(( param + 1 ))"
        process_snmp_get "2.${device_no}.${next_param}"
      else
        if [ "$device_no" -lt "$(( ${#backup_dirs[@]} - 1 ))" ]; then
          process_snmp_get "2.$(( device_no + 1 )).1"
        fi
      fi
      ;;
    esac
  fi

}

while getopts "h?g:n:" opt; do
  case "$opt" in
  h | \?)
    show_help
    exit 0
    ;;

  g)
    OID="$OPTARG"
    ACTION="GET"
    ;;

  n)
    OID="$OPTARG"
    ACTION="NEXT"
    ;;
  esac
done

shift $((OPTIND - 1))

[ "${1:-}" = "--" ] && shift

# relative OID (rooted on $OID_ROOT)
oid="${OID#"${OID_ROOT}."}"

case "$ACTION" in
GET)
  process_snmp_get "$oid"
  ;;
NEXT)
  process_snmp_next "$oid"
  ;;
esac

exit 0
