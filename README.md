# How to set up an ops cluster

## Prerequesties

* An openshift 3.7 cluster with Prometheus
* Podified ManageIQ installed on the cluster (preferably from docker.io/containermgmt/manageiq-pods)
* A control host (to run the ansible playbooks from, can be the cluster master or your laptop)

You'll need ansible 2.4 or newer for the manageiq modules and the python manageiq api client installed on the "control host".

The "jq" command is also useful to have.

Use the following command to install them (assuming your control host has EPEL enabled):

``sudo yum install -y python-pip ansible jq wget; sudo pip install manageiq-client``

## Needed Environment Variables

* Route to CFME/ManageIQ
* Username and password to CFME/ManageIQ (default: admin:smartvm)
* Route to Prometheus
* Master Hostname
* CA certificate for the master

```bash
$ wget https://raw.githubusercontent.com/container-mgmt/cm-ops-flow/master/make_env.sh
$ bash make_env.sh | tee cm_ops_vars.sh
$ source cm_ops_vars.sh
```
## Add A Cluster Admin rule to your user
``oadm policy add-cluster-role-to-user cluster-admin $USER`` (replace $USER with your LDAP username)

## Assign Alert Profiles to the Enterprise

This step "enables" the two built-in alert profiles (**note:** there's no ansible module for this step yet).

1. Find the href of the MiqEnterprise object (usually 1, sometimes not)

```bash
 export ENTERPRISE_HREF="$(curl -u ${OPENSHIFT_CFME_AUTH} https://${OPENSHIFT_CFME_ROUTE}/api/enterprises/ | jq -r ".resources[0].href")"
```

2. Find the hrefs for the two built-in profiles:

```bash
export PROMETHEUS_PROVIDER_PROFILE="$(curl -k -u ${OPENSHIFT_CFME_AUTH} "https://${OPENSHIFT_CFME_ROUTE}/api/alert_definition_profiles?filter\[\]=guid=a16fcf51-e2ae-492d-af37-19de881476ad" | jq -r ".resources[0].href")"
export PROMETHEUS_NODE_PROFILE="$(curl -k -u ${OPENSHIFT_CFME_AUTH} "https://${OPENSHIFT_CFME_ROUTE}/api/alert_definition_profiles?filter\[\]=guid=ff0fb114-be03-4685-bebb-b6ae8f13d7ad" | jq -r ".resources[0].href")"
```
3. Assign them to the enterprise (This requires [ManageIQ/manageiq-api PR #177](https://github.com/ManageIQ/manageiq-api/pull/177)):

```bash
curl -k -u ${OPENSHIFT_CFME_AUTH} -d "{\"action\": \"assign\", \"objects\": [\"${ENTERPRISE_HREF}\"]}" ${PROMETHEUS_PROVIDER_PROFILE}
curl -k -u ${OPENSHIFT_CFME_AUTH} -d "{\"action\": \"assign\", \"objects\": [\"${ENTERPRISE_HREF}\"]}" ${PROMETHEUS_NODE_PROFILE}
```

## Add the provider to ManageIQ

Download the playbook from this github repository:

``curl https://raw.githubusercontent.com/container-mgmt/cm-ops-flow/master/miq_add_provider.yml > miq_add_provider.yml``

Run ansible:

```bash
ansible-playbook --extra-vars \
                    "provider_name=${OPENSHIFT_PROVIDER_NAME}\
                    management_admin_token=${OPENSHIFT_MANAGEMENT_ADMIN_TOKEN} \
                    ca_crt=\"${OPENSHIFT_CA_CRT}\" \
                    openshift_master_host=${OPENSHIFT_MASTER_HOST} \
                    cfme_route=${OPENSHIFT_CFME_ROUTE} \
                    prometheus_metrics_route=${OPENSHIFT_PROMETHEUS_METRICS_ROUTE} \
                    prometheus_alerts_route=${OPENSHIFT_PROMETHEUS_ALERTS_ROUTE} \
                    cfme_user=${OPENSHIFT_CFME_USER} \
                    cfme_pass=${OPENSHIFT_CFME_PASS}" \
miq_add_provider.yml
```

If this step fails, you might have ansible older than 2.4 or don't have the manageiq-api python package installed.

## Enable "Capacity & Utilization"
There's no API for this stage (yet).

Using the UI, click the top-right menu, then click Configuration.

Under the *Server Control*->*Server Roles* heading, toggle all "Capacity & Utilization" switches to "on".

Click "Save" on the buttom-right corner.

## Configure Alerts on Prometheus

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
          url: "https://www.example.com/node_down_fixing_instructions"
          message: "Node {{$labels.instance}} is down"
      - alert: "Too Many Pods"
        expr: sum(kubelet_running_pod_count) > 30
        annotations:
          miqTarget: "ExtManagementSystem"
          severity: "ERROR"
          url: "https://www.example.com/too_many_pods_fixing_instructions"
          message: "Too many running pods"
```
To reload the configuration, delete the pod OR send a HUP signal to the Prometheus process.

```bash
oc rsh -n openshift-metrics -c prometheus prometheus-0
kill -HUP 1
```

## Expose the alerts manager for external access

```bash
wget https://raw.githubusercontent.com/container-mgmt/cm-ops-flow/master/expose_alertmanager.sh
bash expose_alertmanager.sh
# Add the new route to environment
bash make_env.sh | tee cm_ops_vars.sh
source cm_ops_vars.sh
```


## Trigger test scenarios

Triggering The "Too Many Pods" test scenario and measuring different intervals related to alerting:
 
```bash
# trigger "Too Many Pods" test scenario
export NS="alerts-test"
oc create namespace "${NS}"

# Create a replication controller and scale it 
cat <<EOF | oc create -n "${NS}" -f - 2>&1
apiVersion: v1
kind: ReplicationController
metadata:
  name: nginx
spec:
  replicas: 1
  selector:
    app: nginx
  template:
    metadata:
      name: nginx
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx
        ports:
        - containerPort: 80
EOF

oc scale rc -n ${NS} nginx --replicas=10

# Measure intervals
wget https://raw.githubusercontent.com/container-mgmt/cm-ops-flow/master/measure_alerts.sh
bash measure_alerts.sh

# Resolve & Measure
oc scale rc -n ${NS} nginx --replicas=0
bash measure_alerts.sh

# Clean Up
oc delete namespace ${NS} 
```
