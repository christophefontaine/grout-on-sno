# SR-IOV Network Operator Configuration

## Overview
This configuration deploys the SR-IOV Network Operator and configures it to manage a subset of existing Virtual Functions (VFs) on the Intel X710 NIC (eno49), while reserving VF0 and VF1 for other uses.

## Hardware Configuration

### eno49 - Intel X710 10GbE SFP+ (0000:04:00.0)
- **Total VFs**: 4 (already created)
  - VF0 (0000:04:02.0 / eno49v0) - **RESERVED** - Not managed by SR-IOV operator
  - VF1 (0000:04:02.1) - **RESERVED** - Used by GROUT (vfio-pci driver)
  - VF2-3 (0000:04:02.2-3 / eno49v2-3) - **MANAGED** - Available for Kubernetes pods (2 VFs)
  - **Network**: eno49-network, VLAN 42
  - **IP Range**: 192.168.42.10 - 192.168.42.100
  - **Gateway**: 192.168.42.1

### eno50 - Intel X710 10GbE SFP+ (0000:04:00.1)
- **Total VFs**: 8 (already created)
  - VF0 (0000:04:10.0 / eno50v0) - **RESERVED** - Not managed by SR-IOV operator
  - VF1-7 (0000:04:10.1-7 / eno50v1-7) - **MANAGED** - Available for Kubernetes pods (7 VFs)
  - **Networks**:
    - eno50-network: VLAN 42, IP Range 192.168.42.101 - 192.168.42.200
    - public-vlan211: VLAN 211, IP Range 192.168.211.10 - 192.168.211.100

## Files

### Operator Deployment
- `60-sriov-operator.yaml` - Deploys SR-IOV Network Operator from Red Hat catalog
  - Creates namespace: `openshift-sriov-network-operator`
  - Creates OperatorGroup and Subscription

### Operator Configuration
- `61-sriov-operatorconfig.yaml` - SR-IOV Operator configuration
  - Enables network injector and webhooks
  - Sets drain mode to disabled (`disableDrain: true`)
  - Configures node selector for workers

### Network Policy
- `62-sriov-network-policy.yaml` - Defines which VFs to manage
  - **eno49 Policy**:
    - Uses `eno49#2-7` selector (manages VF2-3, 2 VFs available)
    - numVfs: 4 (total VFs on PF)
    - Resource name: `eno49netdevice`
    - Set `externallyManaged: true` since VFs are pre-created
    - Device type: `netdevice` (kernel driver)
    - Priority: 99
  - **eno50 Policy**:
    - Uses `eno50#1-7` to manage VF1-7 (7 VFs)
    - numVfs: 8 (total VFs on PF)
    - Resource name: `eno50netdevice`
    - Set `externallyManaged: true` since VFs are pre-created
    - Device type: `netdevice` (kernel driver)
    - Priority: 99

### Network Definition
- `63-sriov-network.yaml` - Creates NetworkAttachmentDefinitions
  - **eno49-network** (eno49netdevice):
    - Namespace: `default`
    - VLAN: 42
    - IPAM: Whereabouts (dynamic allocation)
    - IP Range: 192.168.42.10 - 192.168.42.100
    - Gateway: 192.168.42.1
  - **eno50-network** (eno50netdevice):
    - Namespace: `default`
    - VLAN: 42
    - IPAM: Whereabouts (dynamic allocation)
    - IP Range: 192.168.42.101 - 192.168.42.200
    - Gateway: 192.168.42.1
  - **public-vlan211** (eno50netdevice):
    - Namespace: `default`
    - VLAN: 211
    - IPAM: Whereabouts (dynamic allocation)
    - IP Range: 192.168.211.10 - 192.168.211.100
    - Gateway: 192.168.211.1
    - Default Route: via 192.168.211.3

### Sample Application
- `workload/sriov-test-pod.yaml` - Test pod using SR-IOV VF
  - Requests 1 VF from `openshift.io/eno49netdevice`
  - Automatically receives IP address from 192.168.42.0/24 range via IPAM
  - Displays network interface information and routing table
  - Demonstrates automatic IP allocation and gateway configuration

## Deployment Steps

### 1. Deploy the SR-IOV Network Operator
```bash
oc apply -f openshift/60-sriov-operator.yaml
```

Wait for the operator to be ready:
```bash
oc get csv -n openshift-sriov-network-operator
# Wait for PHASE: Succeeded
```

### 2. Configure the Operator
```bash
oc apply -f openshift/61-sriov-operatorconfig.yaml
```

Wait for config daemon to be deployed:
```bash
oc get pods -n openshift-sriov-network-operator
# Wait for sriov-network-config-daemon-* to be Running
```

### 3. Create the Network Policy
```bash
oc apply -f openshift/62-sriov-network-policy.yaml
```

Verify the node state:
```bash
oc get sriovnetworknodestate -n openshift-sriov-network-operator
# Wait for SYNC STATUS: Succeeded
```

Check allocatable resources:
```bash
oc describe node droplet05.foobar.space | grep -E "eno49netdevice|eno50netdevice"
# Should show:
# openshift.io/eno49netdevice: 2
# openshift.io/eno50netdevice: 7
```

### 4. Create the SR-IOV Network
```bash
oc apply -f openshift/63-sriov-network.yaml
```

Verify NetworkAttachmentDefinition:
```bash
oc get network-attachment-definitions -n default
# Should show: eno49-network, eno50-network, public-vlan211
```

### 5. Deploy Test Application
```bash
oc apply -f workload/sriov-test-pod.yaml
```

Verify the pod is running:
```bash
oc get pod sriov-test-pod -n default
```

Check the network interfaces:
```bash
oc logs sriov-test-pod -n default
```

Verify VF assignment:
```bash
oc get pod sriov-test-pod -n default -o jsonpath='{.metadata.annotations.k8s\.v1\.cni\.cncf\.io/network-status}' | jq .
```

## Using SR-IOV VFs in Your Applications

To use an SR-IOV VF in your pod, add the following to your pod spec:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-sriov-app
  annotations:
    k8s.v1.cni.cncf.io/networks: eno49-network
spec:
  containers:
  - name: my-app
    image: your-image:tag
    resources:
      requests:
        openshift.io/eno49netdevice: "1"
      limits:
        openshift.io/eno49netdevice: "1"
```

The VF will be available as `net1` (or `net2`, `net3`, etc. if multiple VFs are requested).

## Network Configuration

All three SR-IOV networks are configured with automatic IP address management using Whereabouts IPAM plugin.

### eno49-network (VLAN 42)
- **Resource**: eno49netdevice (2 VFs available)
- **VLAN**: 42
- **Type**: Whereabouts (dynamic IPAM)
- **IP Range**: 192.168.42.10 - 192.168.42.100
- **Subnet**: 192.168.42.0/24
- **Gateway**: 192.168.42.1
- **Default Route**: via 192.168.42.1

### eno50-network (VLAN 42)
- **Resource**: eno50netdevice (7 VFs available)
- **VLAN**: 42 (shared with eno49-network)
- **Type**: Whereabouts (dynamic IPAM)
- **IP Range**: 192.168.42.101 - 192.168.42.200
- **Subnet**: 192.168.42.0/24
- **Gateway**: 192.168.42.1
- **Default Route**: via 192.168.42.1

**Note**: eno49-network and eno50-network share VLAN 42 but use non-overlapping IP ranges from the same subnet.

### public-vlan211 (VLAN 211)
- **Resource**: eno50netdevice (7 VFs available)
- **VLAN**: 211
- **Type**: Whereabouts (dynamic IPAM)
- **IP Range**: 192.168.211.10 - 192.168.211.100
- **Subnet**: 192.168.211.0/24
- **Gateway**: 192.168.211.1
- **Default Route**: via 192.168.211.3

**IP Allocation**: Pods attached to these networks will automatically receive:
- An IP address from the configured range
- Appropriate gateway route
- Default route as configured

## Verification Commands

Check SR-IOV node state:
```bash
oc get sriovnetworknodestate droplet05.foobar.space -n openshift-sriov-network-operator -o yaml
```

List all SR-IOV resources:
```bash
oc get sriovnetworknodepolicies -n openshift-sriov-network-operator
oc get sriovnetworks -n openshift-sriov-network-operator
```

Check node allocatable resources:
```bash
oc get node droplet05.foobar.space -o json | jq '.status.allocatable'
```

## Troubleshooting

Check operator logs:
```bash
oc logs -n openshift-sriov-network-operator deployment/sriov-network-operator
```

Check config daemon logs:
```bash
oc logs -n openshift-sriov-network-operator daemonset/sriov-network-config-daemon
```

Check network injector logs:
```bash
oc logs -n openshift-sriov-network-operator daemonset/network-resources-injector
```

## Important Notes

1. **VF Reservation**:
   - eno49: VF0 and VF1 are reserved (VF1 used by GROUT)
   - eno50: VF0 is reserved
2. **External Management**: The `externallyManaged: true` flag tells the operator not to create VFs, only manage existing ones
3. **No Drain**: `disableDrain: true` prevents node draining during configuration changes
4. **Device Type**: Using `deviceType: netdevice` keeps VFs in kernel mode (iavf driver)
5. **Shared VLAN**: eno49-network and eno50-network both use VLAN 42 with non-overlapping IP ranges
6. **Multiple Networks**: eno50 VFs can be attached to either eno50-network (VLAN 42) or public-vlan211 (VLAN 211)

## Available Resources

With the current configuration:
- **eno49 Total VFs**: 4
  - Reserved: 2 (VF0, VF1)
  - Managed by operator: 2 (VF2-3)
  - Available to pods: 2 (shown as `openshift.io/eno49netdevice: 2`)
- **eno50 Total VFs**: 8
  - Reserved: 1 (VF0)
  - Managed by operator: 7 (VF1-7)
  - Available to pods: 7 (shown as `openshift.io/eno50netdevice: 7`)
- **Total Kubernetes VFs**: 9 (2 from eno49 + 7 from eno50)
