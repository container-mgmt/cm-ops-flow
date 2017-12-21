# Installing Podified ManageIQ on an Existing Cluster
## Prerequesties

* a functional OpenShift 3.7 cluster
* ansible

## Clone openshift-ansible

```bash
git clone https://github.com/openshift/openshift-ansible.git
cd openshift-ansible
git checkout release-3.7
````

## Create Your Inventory File

Use this template. **Make sure to replace the variabls with the apropriate values**.

```ini
[OSv3:children]
masters
etcd

[OSv3:vars]
ansible_ssh_user=root

ansible_ssh_common_args="-o ControlMaster=auto -o ControlPersist=600s"
ansible_ssh_pipelining=true

deployment_type=openshift-enterprise
# ManageIQ
openshift_management_install_management=true
openshift_management_app_template=cfme-template
openshift_management_template_parameters={'APPLICATION_IMG_NAME': 'docker.io/containermgmt/manageiq-pods', 'FRONTEND_APPLICATION_IMG_TAG': 'latest'}
openshift_management_install_beta=true
openshift_management_storage_class=nfs_external
openshift_management_storage_nfs_external_hostname=$NFS_HOSTNAME
openshift_management_storage_nfs_base_dir=$NFS_PATH
[etcd]
$OCP_MASTER_HOSTNAME openshift_hostname=$OCP_MASTER_HOSTNAME

[masters]
$OCP_MASTER_HOSTNAME openshift_hostname=$OCP_MASTER_HOSTNAME

```

Make sure to replace `$OCP_MASTER_HOSTNAME` , `$NFS_PATH` and `$NFS_HOSTNAME` with the apropriate values.

Save this template as "inventory.ini"

## Run openshift-ansible

```bash
ansible-playbook -i inventory.ini --ask-pass playbooks/byo/openshift-management/config.yml
```
