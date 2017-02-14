#!/bin/bash

#    Copyright 2013 Mirantis, Inc.
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.

[ "$(basename ${0})" = "prep-cygwin-hostonlyifs.sh" ] && exit 1

#source ./functions/network.sh

# add VirtualBox directory to PATH
case "$(uname)" in
    CYGWIN*)
        vbox_path_registry=`cat /proc/registry/HKEY_LOCAL_MACHINE/SOFTWARE/Oracle/VirtualBox/InstallDir`
        vbox_path=`cygpath "$vbox_path_registry"| sed -e 's%/$%%'`
        export PATH=$PATH:$vbox_path
      ;;
    *)
      ;;
esac


# Prepare the host system
./actions/prepare-environment.sh || exit 1

# For cygwin, I want to use predefined host-only interfaces to avoid all the problems,
# creating and deleting them.
host_nic_name[0]='VirtualBox Host-Only Ethernet Adapter #20'
host_nic_name[1]='VirtualBox Host-Only Ethernet Adapter #21'
host_nic_name[2]='VirtualBox Host-Only Ethernet Adapter #22'
host_nic_name[3]='VirtualBox Host-Only Ethernet Adapter #23'
host_nic_name[4]='VirtualBox Host-Only Ethernet Adapter #24'
#host_nic_name[5]='VirtualBox Host-Only Ethernet Adapter #25'
#host_nic_name[0]='VirtualBox Host-Only Ethernet Adapter #6'
#host_nic_name[1]='VirtualBox Host-Only Ethernet Adapter #7'
#host_nic_name[2]='VirtualBox Host-Only Ethernet Adapter #8'
#host_nic_name[3]='VirtualBox Host-Only Ethernet Adapter #9'
#host_nic_name[4]='VirtualBox Host-Only Ethernet Adapter #10'

# Host interfaces to bridge VMs interfaces with
# VirtualBox has different virtual NIC naming convention and index base
# between Windows and Linux/MacOS
idx=0
# Please add the IPs accordingly if you going to create non-default NICs number
# 10.20.0.1/24   - Mirantis OpenStack Admin network
# 172.16.0.1/24  - OpenStack Public/External/Floating network
# 172.16.1.1/24  - OpenStack Fixed/Internal/Private network
# 192.168.0.1/24 - OpenStack Management network
# 192.168.1.1/24 - OpenStack Storage network (for Ceph, Swift etc)

# remove this file, and regenerate it for config.sh to source
rm -f fuel-net-config.txt

for ip in 10.20.0.1 172.16.0.1 172.16.1.1 192.168.0.1 192.168.1.1; do
#for ip in 10.20.0.1 172.16.0.1 172.16.1.1 ; do
# VirtualBox for Windows has different virtual NICs naming and indexing
  case "$(uname)" in
    Linux)
      host_nic_name[$idx]=vboxnet$idx
      os_type="linux"
    ;;
    Darwin)
      host_nic_name[$idx]=vboxnet$idx
      os_type="darwin"
    ;;
    CYGWIN*)
#      if [ $idx -eq 0 ]; then
#        host_nic_name[$idx]='VirtualBox Host-Only Ethernet Adapter'
#      else
#        host_nic_name[$idx]='VirtualBox Host-Only Ethernet Adapter #'$((idx+1))
#      fi
      os_type="cygwin"
    ;;
    *)
      echo "$(uname) is not supported operating system."
      exit 1
    ;;
  esac
  host_nic_ip[$idx]=$ip
  host_nic_mask[$idx]=255.255.255.0
  echo 'host_nic_name['$idx']="'"${host_nic_name[$idx]}"'"' >> fuel-net-config.txt
  echo 'host_nic_ip['$idx']='"${host_nic_ip[$idx]}" >> fuel-net-config.txt
  echo 'host_nic_mask['$idx']='"${host_nic_mask[$idx]}" >> fuel-net-config.txt
  idx=$((idx+1))
done

# create host-only interfaces
#./actions/create-interfaces.sh || exit 1
# Create the required host-only interfaces
# Change {0..2} to {0..4} below if you are going to create 5 interfaces instead of 3


cygwin_get_hostonly_interfaces() {
  echo -e `VBoxManage list hostonlyifs | grep '^Name' | sed 's/^Name\:[ \t]*//' | uniq | tr "\\n" ","`
}

is_hostonly_interface_present() {
  name=$1
  result=1
# String comparison with IF works different in Cygwin, probably due to encoding.
# So, reduced Case is used. since it works the same way.
# Default divider character change is mandatory for Cygwin.
  case "$(uname)" in
    CYGWIN*)
      OIFS=$IFS
      IFS=","
      ;;
    *)
      ;;
  esac
  # Call VBoxManage directly instead of function, due to changed IFS
  list=`VBoxManage list hostonlyifs | grep '^Name' | sed 's/^Name\:[ \t]*//' | uniq | tr "\\n" ","`
  # Check that the list of interfaces contains the given interface
  for h in $list[]; do
    if [[ $h == $name ]]; then result=0; fi
  done
  # Change default divider back
  case "$(uname)" in
    CYGWIN*)
      IFS=$OIFS
      ;;
    *)
      ;;
  esac
  return $result
}

cygwin_create_hostonlyif() {
  name=$1
  # Skip if the interface already exists, never delete
  if is_hostonly_interface_present "$name"; then
    echo "Interface $name already exists. Skipping $name ..."
  else
    VBoxManage hostonlyif create
  fi

}

cygwin_check_hostonlyif() {
  name=$1
  if !(is_hostonly_interface_present "$name"); then
    echo "Fatal error. Interface $name does not exist after creation. Exiting"
    exit 1
  fi
}

# Created for cygwin hostonlyifs, because they are so different.
cygwin_config_hostonlyif() {
  name=$1
  ip=$2
  mask=$3

  # Disable DHCP
  echo "Disabling DHCP server on interface: $name..."
  # These magic 1 second sleeps around DHCP config are required under Windows/Cygwin
  # due to VBoxSvc COM server accepts next request before previous one is actually finished.
  sleep 1s
  VBoxManage dhcpserver remove --ifname "$name" 2>/dev/null
  sleep 1s
  set -x
  # Set up IP address and network mask
  echo "Configuring IP address $ip and network mask $mask on interface: $name..."
  VBoxManage hostonlyif ipconfig "$name" --ip $ip --netmask $mask
  set +x
}

# Created for cygwin hostonlyifs, because they are so different.
cygwin_check_config_hostonlyif() {
  name=$1
  ip=$2
  mask=$3

  # Check what we have created actually.
  # Sometimes VBox occasionally fails to apply settings to the last IFace under Windows
  if !(check_if_iface_settings_applied "$name" $ip $mask); then
    echo "Looks like VirtualBox failed to apply settings for interface $name"
    echo "Sometimes such error happens under Windows."
    echo "Please run launch.sh one more time."
    echo "If this error remains after several attempts, then something really went wrong."
    echo "Aborting."
    exit 1
  fi
}

for cnt in $(eval echo {0..$((idx-1))}); do
  echo "Create hostonly interfaces ..."
  cygwin_create_hostonlyif "${host_nic_name[$cnt]}"
  sleep 2s
done

for cnt in $(eval echo {0..$((idx-1))}); do
  echo "Check hostonly interfaces ..."
  cygwin_check_hostonlyif "${host_nic_name[$cnt]}"
  sleep 2s
done

for cnt in $(eval echo {0..$((idx-1))}); do
  cygwin_config_hostonlyif "${host_nic_name[$cnt]}" ${host_nic_ip[$cnt]} ${host_nic_mask[$cnt]}
  sleep 2s
done

# Should be done in cygwin_launch.sh before master node create
#for cnt in $(eval echo {0..$((idx-1))}); do
  #cygwin_check_config_hostonlyif "${host_nic_name[$cnt]}" ${host_nic_ip[$cnt]} ${host_nic_mask[$cnt]}
  #sleep 2s
#done

