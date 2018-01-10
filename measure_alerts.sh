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
    # eek! global variable
    PREVIOUS_SECONDS=${CURRENT_SECONDS}
    CURRENT_SECONDS=$(date +%s)
    message "$((CURRENT_SECONDS-START_SECONDS)) Seconds Since Start, $((CURRENT_SECONDS-PREVIOUS_SECONDS)) Since Previous"
}

#
# Ignore errors, sleep $SLEEP_INTERVAL_SECONDS once after each evaluation
#
# expression - expression to evaluate
# evaluate_expression(expression)
#
function evaluate_expression() {
    local expression="${1}"
    local value
    while true; do
        value=$(eval "${expression}")
        RC=$?;
        printf "." >&2
        sleep ${SLEEP_INTERVAL_SECONDS}
        if [[ "${RC}" != 0 ]]; then
            echo "Evaluation error RC=${RC}, retrying" >&2
            continue;
        else
            break;
        fi
    done
    echo "${value}";
}

#
# topic - name for topic being evaluated
# expression - expression to evaluate for change
# initial_value - optional, watch for changes for this value
#                 defaults to eval "${expression}"
# detect_changes(topic, expression, initial_value)
#
function detect_changes() {
    local topic="${1}"
    local expression="${2}"
    local initial_value="${3}"
    local log_pref="Waiting For change:"
    local current_value
    message "${log_pref} TOPIC=${topic}"
    message "${log_pref} EXPRESSION=${expression}"
    message "${log_pref} INITIAL_VALUE=${initial_value}"
    while true; do
        local value
        value=$(evaluate_expression "${expression}")
        if [[ -z "${initial_value}" ]]; then
            initial_value=${value};
            message "${log_pref} INITIAL_VALUE=${initial_value}"
            continue
        else
            current_value=${value}
        fi

        if [[ "${current_value}" != "${initial_value}" ]]; then
            break;
        fi
    done
    echo;
    message "${log_pref} Changed!"
    message "${log_pref} NEW_VALUE=${current_value}"
}

#
# Main
#
START_SECONDS=$(date +%s)
PREVIOUS_SECONDS=${START_SECONDS}
message "Clock started"

#
# Since alert manager usually gets the alert message before we get to measuring it, calculate initial value beforehand.
#
ALERT_MANAGER_ALERT_COUNT=$(evaluate_expression "curl -k -s \"http://${OPENSHIFT_ALERTMANAGER_ROUTE}/api/v1/alerts\" | jq \".data | length\"")
message "[ALERT_MANAGER_ALERT_COUNT=${ALERT_MANAGER_ALERT_COUNT}]"

detect_changes "PROMETHEUS ALERT COUNT" \
               "curl -k -s -H \"Authorization: Bearer ${OPENSHIFT_MANAGEMENT_ADMIN_TOKEN}\" \"https://${OPENSHIFT_PROMETHEUS_METRICS_ROUTE}/api/v1/query?query=ALERTS\" | jq \".data.result | length\""
output_time

detect_changes "ALERTMANAGER ALERT COUNT" \
               "curl -k -s \"http://${OPENSHIFT_ALERTMANAGER_ROUTE}/api/v1/alerts\" | jq \".data | length\"" \
               "${ALERT_MANAGER_ALERT_COUNT}"
output_time

detect_changes "ALERT BUFFER INDEX (!= ALERT COUNT)" \
               "curl -k -s -H \"Authorization: Bearer ${OPENSHIFT_MANAGEMENT_ADMIN_TOKEN}\" \"https://${OPENSHIFT_PROMETHEUS_ALERTS_ROUTE}/topics/alerts\" | jq \".messages | length\""
output_time

detect_changes "LAST GENERATION IN MANAGEIQ LOGS" \
               "oc rsh -n openshift-management manageiq-0  grep 'Fetching alerts' log/container_monitoring.log | tail -1 | sed -r \"s/^.*Generation: (.*)$/\1/\""
output_time

