#!/bin/sh

HOST=$(hostname)
CMD="sudo ipmi-sensors -t Temperature,Fan,Current,Voltage --comma-separated-output --no-header-output --ignore-not-available-sensors --no-sensor-type-output  --entity-sensor-names"

$CMD | tr -d "'" | awk -v host="$HOST" -v user="$USER_TAG" '
BEGIN {
    FS=","
}
{
    # Expected CSV: ID,Name,Type,Reading,Units,Event,State
    name=$2
    gsub(/ /, "_", name)              # Replace spaces with underscores
    value=$3
    unit=$4
    state=$5
    gsub(/ /, "_", state)              # Replace spaces with underscores
    if (unit != "N/A" && value != "N/A") printf("ipmi_sensor,host=%s,name=%s,unit=%s value=%s\n", host, name,unit, value)
    # else  printf("ipmi_sensor,host=%s,name=%s,state=%s value=0.0\n", host, name, state)
}'
