# How to set up an ops cluster

## Prerequesties

* An openshift 3.7 cluster with Prometheus
* Podified ManageIQ installed on the cluster (preferably from docker.io/containermgmt/manageiq-pods)
* A control host (to run the ansible playbooks from, can be the cluster master or your laptop)

You'll need ansible 2.4 or newer for the manageiq modules and the python manageiq api client installed on the "control host".

The "jq" command is also useful to have.

Use the following command to install them (assuming your control host has EPEL enabled):

``sudo yum install -y python-pip ansible jq; sudo pip install manageiq-client``

## Needed Environment Variables

* Route to CFME/ManageIQ
* Username and password to CFME/ManageIQ (default: admin:smartvm)
* Route to Prometheus
* Master Hostname
* CA certificate for the master

Assuming your control host is your cluster master, you can run this snippet to get all the variables:

```
export OCP_CFME_ROUTE="$(oc get route --namespace='openshift-management' -o go-template --template='{{.spec.host}}' httpd 2> /dev/null)"
export OCP_HAWKULAR_ROUTE="$(oc get route --namespace='openshift-infra' -o go-template --template='{{.spec.host}}' hawkular-metrics 2> /dev/null)"
export OCP_PROMETHEUS_ALERTS_ROUTE="$(oc get route --namespace='openshift-metrics' -o go-template --template='{{.spec.host}}' alerts 2> /dev/null)"
export OCP_PROMETHEUS_METRICS_ROUTE="$(oc get route --namespace='openshift-metrics' -o go-template --template='{{.spec.host}}' prometheus 2> /dev/null)"
export OCP_MASTER_HOST="$(oc get nodes -o name |grep master |sed -e 's/nodes\///g')"
export OCP_MANAGEMENT_ADMIN_TOKEN="$(oc sa get-token -n management-infra management-admin)"
export OCP_CA_CRT="$(cat /etc/origin/master/ca.crt)"
export OCP_PROVIDER_NAEME="OCP37"
```
## Add A Cluster Admin rule to your user
``oadm policy add-cluster-role-to-user cluster-admin $USER`` (replace $USER with your LDAP username)

## Assign Alert Profiles to the Enterprise

This step "enables" the two built-in alert profiles (**note:** there's no ansible module for this step yet).

1. Find the hrefs for the two built-in profiles:

```bash
export PROMETHEUS_PROVIDER_PROFILE="$(curl -k -u admin:smartvm "https://${OCP_CFME_ROUTE}/api/alert_definition_profiles?filter\[\]=guid=a16fcf51-e2ae-492d-af37-19de881476ad" | jq -r ".resources[0].href")"``
export PROMETHEUS_NODE_PROFILE="$(curl -k -u admin:smartvm "https://${OCP_CFME_ROUTE}/api/alert_definition_profiles?filter\[\]=guid=ff0fb114-be03-4685-bebb-b6ae8f13d7ad" | jq -r ".resources[0].href")"``
```
2. Assign them to the enterprise (This requires [ManageIQ/manageiq-api PR #177](https://github.com/ManageIQ/manageiq-api/pull/177)):

```bash
curl -k -u admin:smartvm -d "{\"action\": \"assign\", \"objects\": [\"https://${OCP_CFME_ROUTE}/api/enterprises/1\"]}" ${PROMETHEUS_PROVIDER_PROFILE}
curl -k -u admin:smartvm -d "{\"action\": \"assign\", \"objects\": [\"https://${OCP_CFME_ROUTE}/api/enterprises/1\"]}" ${PROMETHEUS_NODE_PROFILE}
```

## Add the provider to ManageIQ

Download the playbook from this github repository:

``curl https://raw.githubusercontent.com/container-mgmt/cm-ops-flow/master/miq_add_provider.yml > miq_add_provider.yml``

Run ansible:

```bash
ansible-playbook --extra-vars \
                    "provider_name=${OCP_PROVIDER_NAEME}\
                    management_admin_token=${OCP_MANAGEMENT_ADMIN_TOKEN} \
                    ca_crt=\"${OCP_CA_CRT}\" \
                    ocp_master_host=${OCP_MASTER_HOST} \
                    cfme_route=${OCP_CFME_ROUTE} \
                    prometheus_metrics_route=${OCP_PROMETHEUS_METRICS_ROUTE} \
                    prometheus_alerts_route=${OCP_PROMETHEUS_ALERTS_ROUTE}" \
miq_add_provider.yml
```

If this step fails, you might have ansible older than 2.4 or don't have the manageiq-api python package installed.

## Enable "Capacity & Utilization"
There's no API for this stage (yet).

Using the UI, click the top-right menu, then click Configuration.

Under the *Server Control*->*Server Roles* heading, toggle all "Capacity & Utilization" switches to "on".

Click "Save" on the buttom-right corner.

## Configure Prometheus

(See [ManageIQ/manageiq issue #14238](https://github.com/ManageIQ/manageiq/issues/14238) for the original documentation)

Run `oc edit configmap -n openshift-metrics prometheus` to edit the configmap,

Add the alert rules under prometheus.rules:

```yaml
# Supported annotations:
# severity: ERROR|WARNING|INFO. defaults to ERROR.
# miqTarget: ContainerNode|ExtManagementSystem, defaults to ContainerNode.
# miqIgnore: "true|false", should ManageIQ pick up this alert, defaults to true.
  prometheus.rules: |
    groups:
    - name: example-rules
      interval: 30s # defaults to global interval
      rules:
      # 
      # ------------- Copy below this line -------------
      #
      - alert: "Node Down"
        expr: up{job="kubernetes-nodes"} == 0
        annotations:
          miqTarget: "ContainerNode"
          severity: "ERROR"
          url: "https://www.example.com/fixing_instructions"
          message: "Node {{$labels.instance}} is down"
      - alert: "Too Many Requests"
        expr: rate(authenticated_user_requests[2m]) > 12
        annotations:
          miqTarget: "ExtManagementSystem"
          severity: "ERROR"
          url: "https://www.example.com/fixing_instructions"
          message: "Too many authenticated requests"
```
To reload the configuration, delete the pod OR send a HUP signal to the Prometheus process.

```bash
oc rsh -n openshift-metrics -c prometheus prometheus-0
kill -HUP 1
```
