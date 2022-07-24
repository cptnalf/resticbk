#!/bin/bash

set -eEuo pipefail

UNIT='restic-backup.service' # needs to include .service.
METRICS_FILE='/var/lib/node_exporter/restic-backup.prom'
TMP_FILE="$(mktemp ${METRICS_FILE}.XXXXXXX)"
# list of labels attached to all series, comma separated, without trailing comma.
COMMON_LABELS="unit=\"${UNIT}\""
LOGS=

function error_finalizer() {
  write_metrics "restic_backup_failure{${COMMON_LABELS},timestamp=\"$(date '+%s')\"} 1"
  rotate_metric_file
}

trap "error_finalizer" ERR

function write_metrics() {
  local text="$1"
  # $text can be multiple lines, so we need to use -e for echo to interpret them.
  echo -e "$text" >> "$TMP_FILE"
}

function rotate_metric_file() {
  mv "$TMP_FILE" "$METRICS_FILE"
  # make sure node_exporter can read the file (ran as node_exporter?)
  chmod a+r "$METRICS_FILE"
}

function convert_to_bytes() {
  local value=$1
  local unit=$2
  local factor

  case $unit in
    'KiB')
        factor=1024
        ;;
    'KB')
        factor=1000
        ;;
    'MiB')
        factor=1048576
        ;;
    'MB')
        factor=1000000
        ;;
    'GiB')
        factor=1073741824
        ;;
    'GB')
        factor=1000000000
        ;;
    'TiB')
        factor=1099511627776
        ;;
    'TB')
        factor=1000000000000
        ;;
    'B')
        factor=1
        ;;
    *)
        echo "Unsupported unit $unit"
        return 1
        ;;
  esac

  echo $(awk 'BEGIN {printf "%.0f", '"${value}*${factor}"'}')
}

function analyze_files_line() {
    # example line:
    # Files:          68 new,    38 changed, 109657 unmodified
    local files_line=$(echo "$LOGS" | grep 'Files:' | cut -d':' -f4-)
    local new_files=$(echo $files_line | awk '{ print $2 }')
    local changed_files=$(echo $files_line | awk '{ print $4 }')
    local unmodified_files=$(echo $files_line | awk '{ print $6 }')
    if [ -z "$new_files" ] || [ -z "$changed_files" ] || [ -z "$unmodified_files" ]; then
        # this line should be present, fail if its not
        return 1
    fi
    echo "restic_repo_files{${COMMON_LABELS},state=\"new\"} $new_files"
    echo "restic_repo_files{${COMMON_LABELS},state=\"changed\"} $changed_files"
    echo "restic_repo_files{${COMMON_LABELS},state=\"unmodified\"} $unmodified_files"
}

function analyze_dirs_line() {
    # Dirs:            0 new,     1 changed,     1 unmodified
    local files_line=$(echo "$LOGS" | grep 'Dirs:' | cut -d':' -f4-)
    local new_dirs=$(echo $files_line | awk '{ print $2 }')
    local changed_dirs=$(echo $files_line | awk '{ print $4 }')
    local unmodified_dirs=$(echo $files_line | awk '{ print $6 }')
    if [ -z "$new_dirs" ] || [ -z "$changed_dirs" ] || [ -z "$unmodified_dirs" ]; then
        # this line should be present, fail if its not
        return 1
    fi
    echo "restic_repo_dirs{${COMMON_LABELS},state=\"new\"} $new_dirs"
    echo "restic_repo_dirs{${COMMON_LABELS},state=\"changed\"} $changed_dirs"
    echo "restic_repo_dirs{${COMMON_LABELS},state=\"unmodified\"} $unmodified_dirs"
}

function analyze_added_line() {
    # Added to the repo: 223.291 MiB
    local added_line=$(echo "$LOGS" | grep 'Added to the repo:' | cut -d':' -f4-)
    local added_value=$(echo $added_line | awk '{ print $5 }')
    local added_unit=$(echo $added_line | awk '{ print $6 }')
    local added_bytes=$(convert_to_bytes $added_value $added_unit)
    if [ -z "$added_bytes" ]; then
        return 1
    fi
    echo "restic_repo_size_bytes{${COMMON_LABELS},state=\"new\"} $added_bytes"
}

function analyze_repository_line() {
    # repository contains 23329 packs (291507 blobs) with 109.102 GiB
    # Note: the "|| true" parts prevent bash from exiting due to PIPEFAIL
    repo_line=$(echo "$LOGS" | (grep 'repository contains' || true) | (cut -d':' -f4- || true) )
    # this line only exists when also a prune was run
    if [ -n "$repo_line" ]; then
        repo_value=$(echo $repo_line | awk '{print $8 }')
        repo_unit=$(echo $repo_line | awk '{print $9 }')
        repo_bytes=$(convert_to_bytes $repo_value $repo_unit)
        if [ -n "$repo_bytes" ]; then
            echo "restic_repo_size_bytes{${COMMON_LABELS},state=\"total\"} $repo_bytes"
        fi
    fi
}

function get_script_seconds() {
    local script_name="$1"
    local script_logs=$(echo "$LOGS" | (grep -s -F "$script_name" || true))
    if [ -z "$script_logs" ]; then
        return
    fi

    # example time format: 2019-03-03T01:39:22+0100
    start_time_seconds=$(date '+%s' -d $(echo "$script_logs" | head -1 | awk '{ print $1 }'))
    stop_time_seconds=$(date '+%s' -d $(echo "$script_logs" | tail -1 | awk '{ print $1 }'))
    duration_seconds=$(( $stop_time_seconds - $start_time_seconds ))
    echo "$duration_seconds"
}


function main() {
    local log_file="${1:-}"
    if [ -n "${log_file}" ]; then
        # get logs from file (useful for debugging / testing)
        LOGS="$(cat {$log_file})"
    else
        # get last invocation id
        # from: https://unix.stackexchange.com/a/506887/214474
        local id=$(systemctl show -p InvocationID --value "$UNIT")

        # get logs from last invocation
        LOGS="$(journalctl -o short-iso INVOCATION_ID=${id} + _SYSTEMD_INVOCATION_ID=${id})"
    fi

    # check if unit failed
    if echo "$LOGS" | grep -F "systemd[1]: ${UNIT}: Failed with result"; then
        # jumps to error_finalizer
        return 1
    fi

    write_metrics "$(analyze_files_line)"
    write_metrics "$(analyze_added_line)"
    write_metrics "$(analyze_repository_line)"
    write_metrics "$(analyze_dirs_line)"

    # script durations:
    # backup
    local backup_duration_seconds=$(get_script_seconds 'restic_backup.sh')
    if [ -n "$backup_duration_seconds" ]; then
        write_metrics "restic_backup_duration_seconds{${COMMON_LABELS},action=\"backup\"} $backup_duration_seconds"
    fi

    # cleanup
    local cleanup_duration_seconds=$(get_script_seconds 'cleanup_backups.sh')
    if [ -n "$cleanup_duration_seconds" ]; then
        write_metrics "restic_backup_duration_seconds{${COMMON_LABELS},action=\"cleanup\"} $cleanup_duration_seconds"
    fi

    # prune
    local prune_duration_seconds=$(get_script_seconds 'restic_prune.sh')
    if [ -n "$prune_duration_seconds" ]; then
        write_metrics "restic_backup_duration_seconds{${COMMON_LABELS},action=\"prune\"} $prune_duration_seconds"
    fi

    # everything ok
    write_metrics "restic_backup_failure{${COMMON_LABELS},timestamp=\"$(date '+%s')\"} 0"

    rotate_metric_file

    return 0
}

main "$@"
