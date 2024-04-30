#!/usr/bin/env bash
#
# Dependencies: nvme-cli, jq (packages)
# Based on code from
# - https://github.com/prometheus/node_exporter/blob/master/text_collector_examples/smartmon.sh
# - https://github.com/prometheus/node_exporter/blob/master/text_collector_examples/mellanox_hca_temp
# - https://github.com/vorlon/check_nvme/blob/master/check_nvme.sh
#
# Author: Henk <henk@wearespindle.com>

set -eu

# Ensure predictable numeric / date formats, etc.
export LC_ALL=C

PREFIX=smartmon_

# Check if we are root
if [ "$EUID" -ne 0 ]; then
  echo "${0##*/}: Please run as root!" >&2
  exit 1
fi

# Check if programs are installed
if ! command -v nvme >/dev/null 2>&1; then
  echo "${0##*/}: nvme is not installed. Aborting." >&2
  exit 1
fi

output_format_awk="$(
  cat <<'OUTPUTAWK'
BEGIN { v = "" }
v != $1 {
  print "# HELP " PREFIX $1 " SMART metric " $1;
  if ($1 ~ /_total$/)
    print "# TYPE " PREFIX $1 " counter";
  else
    print "# TYPE " PREFIX $1 " gauge";
  v = $1
}
{print PREFIX $1 "{type=\"nvme\"," $2}
OUTPUTAWK
)"

format_output() {
  sort | awk -v PREFIX="$PREFIX" -F'{' "${output_format_awk}"
}

# Get the nvme-cli version
nvme_version="$(nvme version | awk '$1 == "nvme" {print $3}')"
echo "nvmecli{version=\"${nvme_version}\"} 1" | format_output

# Get devices
device_list=()

while read -r device_info; do
  disk="$(echo "$device_info" | jq -r '.DevicePath')"
  device_list+=("$disk")
  device_model="$(echo "$device_info" | jq -r '.ModelNumber')"
  firmware_version="$(echo "$device_info" | jq -r '.Firmware')"
  serial_number="$(echo "$device_info" | jq -r '.SerialNumber')"
  echo "device_info{disk=\"${disk}\",device_model=\"$device_model\",serial_number=\"$serial_number\",firmware_version=\"$firmware_version\"} 1"
  # use process subsitution to break out of subshell http://mywiki.wooledge.org/BashFAQ/024
done <<<"$(nvme list -o json | jq -r -c '.Devices[]?')" > >(format_output)

# Loop through the NVMe devices
for device in "${device_list[@]}"; do
  json_info="$(nvme list -o json )"
  json_check="$(nvme smart-log -o json "${device}")"
  disk="${device}"

  echo "device_active{disk=\"${disk}\"} 1"

  # The temperature value in JSON is in Kelvin, we want Celsius
  value_temperature="$(echo "$json_check" | jq '.temperature - 273')"
  echo "temperature_celsius_raw_value{disk=\"${disk}\"} ${value_temperature}"

  value_available_spare="$(echo "$json_check" | jq '.avail_spare')"
  echo "available_spare_ratio{disk=\"${disk}\"} ${value_available_spare}"

  value_available_spare_threshold="$(echo "$json_check" | jq '.spare_thresh')"
  echo "available_spare_ratio_threshold{disk=\"${disk}\"} ${value_available_spare_threshold}"

  value_percentage_used="$(echo "$json_check" | jq '.percent_used')"
  echo "percentage_used_ratio{disk=\"${disk}\"} ${value_percentage_used}"

  value_critical_warning="$(echo "$json_check" | jq '.critical_warning')"
  echo "critical_warning_total{disk=\"${disk}\"} ${value_critical_warning}"

  value_media_errors="$(echo "$json_check" | jq -r '.media_errors')"
  echo "media_errors_total{disk=\"${disk}\"} ${value_media_errors}"

  value_num_err_log_entries="$(echo "$json_check" | jq -r '.num_err_log_entries')"
  echo "num_err_log_entries_total{disk=\"${disk}\"} ${value_num_err_log_entries}"

  value_power_cycles="$(echo "$json_check" | jq -r '.power_cycles')"
  echo "power_cycle_count_raw_value{disk=\"${disk}\"} ${value_power_cycles}"

  value_power_on_hours="$(echo "$json_check" | jq -r '.power_on_hours')"
  echo "power_on_hours_raw_value{disk=\"${disk}\"} ${value_power_on_hours}"

  value_controller_busy_time="$(echo "$json_check" | jq -r '.controller_busy_time')"
  echo "controller_busy_time_seconds{disk=\"${disk}\"} ${value_controller_busy_time}"

  value_data_units_written="$(echo "$json_check" | jq -r '.data_units_written')"
  echo "data_units_written_total{disk=\"${disk}\"} ${value_data_units_written}"

  value_data_units_read="$(echo "$json_check" | jq -r '.data_units_read')"
  echo "data_units_read_total{disk=\"${disk}\"} ${value_data_units_read}"

  value_host_read_commands="$(echo "$json_check" | jq -r '.host_read_commands')"
  echo "host_read_commands_total{disk=\"${disk}\"} ${value_host_read_commands}"

  value_host_write_commands="$(echo "$json_check" | jq -r '.host_write_commands')"
  echo "host_write_commands_total{disk=\"${disk}\"} ${value_host_write_commands}"
done | format_output
