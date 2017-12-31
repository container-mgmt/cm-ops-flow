#!/bin/bash


SLEEP_INTERVAL_SECONDS=1

function die() {
	local m="${1}"
	echo "[$(date)] FATAL: ${m}" >&2
	exit 1
}

function message {
    local m="${1}"
    echo "[$(date)] INFO: ${m}"
}

function output_time() {
    local seconds_start="${1}"
    local seconds_now
    seconds_now=$(date +%s)
    message "$((seconds_now-seconds_start)) Seconds Since Start"
}

#
# detect_changes(topic, sampling expression)
#
function detect_changes() {
    local topic="${1}"
    local expression="${2}"
    message "Waiting For change: TOPIC=${topic}"
    message "Waiting For change: EXPRESSION=${expression}"
    local initial_value
    initial_value=$(eval "${expression}")
    local current_value="${initial_value}"
    message "Initial Value is ${initial_value}"
    message "Waiting..."
    while true; do
        current_value=$(eval "${expression}")
        if [[ "${current_value}" != "${initial_value}" ]]; then
            break;
        fi
        sleep ${SLEEP_INTERVAL_SECONDS}
    done
    message "Changed!"
    message "New value is ${current_value}"
}


#
# Main
#
START_SECONDS=$(date +%s)
message "Clock started"

detect_changes "PROMETHEUS ALERT COUNT" "curl -k -s -H \"Authorization: Bearer ${OPENSHIFT_MANAGEMENT_ADMIN_TOKEN}\" \"https://${OPENSHIFT_PROMETHEUS_METRICS_ROUTE}/api/v1/query?query=ALERTS\" | jq \".data.result | length\""
output_time "${START_SECONDS}"

detect_changes "ALERTMANAGER ALERT COUNT" "curl -k -s \"http://${OPENSHIFT_ALERTMANAGER_ROUTE}/api/v1/alerts\" | jq \".data | length\""
output_time "${START_SECONDS}"

# Messages always get instantly to alertmanager, so we miss the change below
# detect_changes "ALERT BUFFER INDEX (!= ALERT COUNT)" "curl -k -s -H \"Authorization: Bearer ${OPENSHIFT_MANAGEMENT_ADMIN_TOKEN}\" \"https://${OPENSHIFT_PROMETHEUS_ALERTS_ROUTE}/topics/alerts\" | jq \".messages | length\""

detect_changes "LAST GENERATION IN MANAGEIQ LOGS" "oc rsh -n openshift-management manageiq-0  grep 'Fetching alerts' log/container_monitoring.log | tail -1 | sed -r \"s/^.*Generation: (.*)$/\1/\""
output_time "${START_SECONDS}"

