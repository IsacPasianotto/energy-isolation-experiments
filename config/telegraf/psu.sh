#!/bin/bash
set -e

HOST=$(hostname)

# Loop through IDs: 0 (Cumulative), 1 (PSU 1), 2 (PSU 2), ...
for ((ID=0; ID<=N_PSU_DEVICES; ID++)); do
    # Capture output for this specific PSU ID
    # We use quotes "$(...)" to preserve newlines in the variable
    OUTPUT=$(sudo ipmi-oem dell get-instantaneous-power-consumption-data $ID)

    # Echo the output into awk.
    echo "$OUTPUT" | awk -v host="$HOST" -v psu_id="$ID" -F":" '
    {
        # --- 1. Clean the Key (Name) ---
        key = $1
        gsub(/^[ \t]+|[ \t]+$/, "", key)  # Trim whitespace
        gsub(/ /, "_", key)               # Replace spaces with underscores
        # --- 2. Clean the Value and Unit ---
        raw_val = $2
        gsub(/^[ \t]+|[ \t]+$/, "", raw_val) # Trim whitespace
        # Split "5 W" into value="5" and unit="W"
        split(raw_val, v, " ")
        value = v[1]
        unit = v[2]

        # --- 3. Output Generation ---
        # We only print if we found a valid numeric value
        if (value ~ /^[0-9.]+$/) {
            # Map the specific reading names to cleaner field names if desired
            # e.g., Instantaneous_Power -> power_watts
            # Construct InfluxDB Line Protocol:
            # Measurement: ipmi_power
            # Tags: host, psu_id, unit, sensor_type
            # Field: value
            printf("ipmi_power,host=%s,psu_id=%s,unit=%s,type=%s value=%s\n", host, psu_id, unit, key, value)
        }
    }'
done
