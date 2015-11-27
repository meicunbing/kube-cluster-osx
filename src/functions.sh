#!/bin/bash

# shared functions library

DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )


function pause(){
    read -p "$*"
}

function check_vm_status() {
# check VM status
status=$(ps aux | grep "[k]ube-solo/bin/xhyve" | awk '{print $2}')
if [ "$status" = "" ]; then
    echo " "
    echo "CoreOS VM is not running, please start VM !!!"
    pause "Press any key to continue ..."
    exit 1
fi
}


function release_channel(){
# Set release channel
LOOP=1
while [ $LOOP -gt 0 ]
do
    VALID_MAIN=0
    echo " "
    echo "Set CoreOS Release Channel:"
    echo " 1)  Alpha "
    echo " 2)  Beta "
    echo " 3)  Stable "
    echo " "
    echo -n "Select an option: "

    read RESPONSE
    XX=${RESPONSE:=Y}

    if [ $RESPONSE = 1 ]
    then
        VALID_MAIN=1
        sed -i "" "s/CHANNEL=stable/CHANNEL=alpha/" ~/kube-cluster/custom.conf
        sed -i "" "s/CHANNEL=beta/CHANNEL=alpha/" ~/kube-cluster/custom.conf
        channel="Alpha"
        LOOP=0
    fi

    if [ $RESPONSE = 2 ]
    then
        VALID_MAIN=1
        sed -i "" "s/CHANNEL=alpha/CHANNEL=beta/" ~/kube-cluster/custom.conf
        sed -i "" "s/CHANNEL=stable/CHANNEL=beta/" ~/kube-cluster/custom.conf
        channel="Beta"
        LOOP=0
    fi

    if [ $RESPONSE = 3 ]
    then
        VALID_MAIN=1
        sed -i "" "s/CHANNEL=alpha/CHANNEL=stable/" ~/kube-cluster/custom.conf
        sed -i "" "s/CHANNEL=beta/CHANNEL=stable/" ~/kube-cluster/custom.confs
        channel="Stable"
        LOOP=0
    fi

    if [ $VALID_MAIN != 1 ]
    then
        continue
    fi
done
}


create_root_disk() {

# Get password
my_password=$(security find-generic-password -wa kube-cluster-app)
echo -e "$my_password\n" | sudo -Sv > /dev/null 2>&1

# create persistent disk
cd ~/kube-cluster/
echo "  "
echo "Please type ROOT disk size in GBs followed by [ENTER]:"
echo -n [default is 5]:
read disk_size
if [ -z "$disk_size" ]
then
    echo "Creating 5GB disk ..."
    dd if=/dev/zero of=root.img bs=1024 count=0 seek=$[1024*5120]
else
    echo "Creating "$disk_size"GB disk ..."
    dd if=/dev/zero of=root.img bs=1024 count=0 seek=$[1024*$disk_size*1024]
fi
echo " "
#

### format ROOT disk
# Start webserver
cd ~/kube-cluster/cloud-init
"${res_folder}"/bin/webserver start

# Start VM
echo "Waiting for VM to boot up for ROOT disk to be formated ... "
echo " "
cd ~/kube-cluster
export XHYVE=~/kube-cluster/bin/xhyve

# enable format mode
sed -i "" "s/user-data/user-data-format-root/" ~/kube-cluster/custom.conf
sed -i "" "s/ROOT_HDD=/#ROOT_HDD=/" ~/kube-cluster/custom.conf
sed -i "" "s/#IMG_HDD=/IMG_HDD=/" ~/kube-cluster/custom.conf
#
"${res_folder}"/bin/coreos-xhyve-run -f custom.conf kube-cluster
#
# disable format mode
sed -i "" "s/user-data-format-root/user-data/" ~/kube-cluster/custom.conf
sed -i "" "s/IMG_HDD=/#IMG_HDD=/" ~/kube-cluster/custom.conf
sed -i "" "s/#ROOT_HDD=/ROOT_HDD=/" ~/kube-cluster/custom.conf
#
echo " "
echo "ROOT disk got created and formated... "
echo "---"
###

# Stop webserver
"${res_folder}"/bin/webserver stop

}

function download_osx_clients() {
# download fleetctl file
LATEST_RELEASE=$(ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no core@$vm_ip 'fleetctl version' | cut -d " " -f 3- | tr -d '\r')
cd ~/kube-cluster/bin
echo "Downloading fleetctl v$LATEST_RELEASE for OS X"
curl -L -o fleet.zip "https://github.com/coreos/fleet/releases/download/v$LATEST_RELEASE/fleet-v$LATEST_RELEASE-darwin-amd64.zip"
unzip -j -o "fleet.zip" "fleet-v$LATEST_RELEASE-darwin-amd64/fleetctl"
rm -f fleet.zip
echo "fleetctl was copied to ~/kube-cluster/bin "

# get lastest OS X helm version from bintray
bin_version=$(curl -I https://bintray.com/deis/helm-ci/helm/_latestVersion | grep "Location:" | sed -n 's%.*helm/%%;s%/view.*%%p')
echo "Downloading latest version of helm for OS X"
curl -L "https://dl.bintray.com/deis/helm-ci/helm-$bin_version-darwin-amd64.zip" -o helm.zip
unzip -o helm.zip
rm -f helm.zip
echo "helm was copied to ~/kube-cluster/bin "
#

}


function download_k8s_files() {
#
cd ~/kube-cluster/tmp

# get latest k8s version
function get_latest_version_number {
    local -r latest_url="https://storage.googleapis.com/kubernetes-release/release/latest.txt"
    curl -Ss ${latest_url}
}

K8S_VERSION=$(get_latest_version_number)

# download latest version of kubectl for OS X
cd ~/kube-cluster/tmp
echo "Downloading kubectl $K8S_VERSION for OS X"
curl -k -L https://storage.googleapis.com/kubernetes-release/release/$K8S_VERSION/bin/darwin/amd64/kubectl >  ~/kube-cluster/kube/kubectl
chmod 755 ~/kube-cluster/kube/kubectl
echo "kubectl was copied to ~/kube-cluster/kube"
echo " "

# clean up tmp folder
rm -rf ~/kube-cluster/tmp/*

# download setup-network-environment binary
echo "Downloading setup-network-environment"
curl -L https://github.com/kelseyhightower/setup-network-environment/releases/download/1.0.1/setup-network-environment > ~/kube-cluster/tmp/setup-network-environment
#
# download latest version of k8s for CoreOS
echo "Downloading latest version of Kubernetes"
bins=( kubectl kubelet kube-proxy kube-apiserver kube-scheduler kube-controller-manager )
for b in "${bins[@]}"; do
    curl -k -L https://storage.googleapis.com/kubernetes-release/release/$K8S_VERSION/bin/linux/amd64/$b > ~/kube-cluster/tmp/$b
done
#
tar czvf kube.tgz *
cp -f kube.tgz ~/kube-cluster/kube/
# clean up tmp folder
rm -rf ~/kube-cluster/tmp/*
echo " "

# get VM IP
vm_ip=$(cat ~/kube-cluster/.env/ip_address)

# install k8s files
install_k8s_files

}


function download_k8s_files_version() {
#
cd ~/kube-cluster/tmp

# ask for k8s version
echo "You can install a particular version of Kubernetes you migh want to test..."
echo "Bear in mind if the version you want is lower than the currently installed, "
echo "Kubernetes cluster migth not work, so you will need to destroy the cluster first "
echo " and boot VM again !!! "
echo " "
echo "Please type Kubernetes version you want to be installed e.g. v1.1.1"
echo "followed by [ENTER] or CMD + W to exit:"
read K8S_VERSION

url=https://github.com/kubernetes/kubernetes/releases/download/$K8S_VERSION/kubernetes.tar.gz

if curl --output /dev/null --silent --head --fail "$url"; then
    echo "URL exists: $url" > /dev/null
else
    echo " "
    echo "There is no such Kubernetes version to download !!!"
    pause 'Press [Enter] key to continue...'
    exit 1
fi

# download required version of Kubernetes
cd ~/kube-cluster/tmp
echo " "
echo "Downloading Kubernetes $K8S_VERSION tar.gz from github ..."
curl -k -L https://github.com/kubernetes/kubernetes/releases/download/$K8S_VERSION/kubernetes.tar.gz >  ~/kube-cluster/tmp/kubernetes.tar.gz
mkdir kube

# download setup-network-environment binary
echo "Downloading setup-network-environment from github ..."
curl -L https://github.com/kelseyhightower/setup-network-environment/releases/download/1.0.1/setup-network-environment > ~/kube-cluster/tmp/kube/setup-network-environment
#
# extracting Kubernetes files
echo "Extracting Kubernetes $K8S_VERSION files ..."
tar xvf  kubernetes.tar.gz --strip=4 kubernetes/platforms/darwin/amd64/kubectl
mv -f kubectl ~/kube-cluster/kube
#
tar xvf kubernetes.tar.gz --strip=2 kubernetes/server/kubernetes-server-linux-amd64.tar.gz
bins=( kubectl kubelet kube-proxy kube-apiserver kube-scheduler kube-controller-manager )
for b in "${bins[@]}"; do
    tar xvf kubernetes-server-linux-amd64.tar.gz -C ~/kube-cluster/tmp/kube --strip=3 kubernetes/server/bin/$b
done
#
chmod a+x kube/*
tar czvf kube.tgz -C kube .
cp -f kube.tgz ~/kube-cluster/kube/
# clean up tmp folder
rm -rf ~/kube-cluster/tmp/*
echo " "

# get VM IP
vm_ip=$(cat ~/kube-cluster/.env/ip_address)

# install k8s files
install_k8s_files

}


function check_for_images() {
# Check if set channel's images are present
CHANNEL=$(cat ~/kube-cluster/custom.conf | grep CHANNEL= | head -1 | cut -f2 -d"=")
LATEST=$(ls -r ~/kube-cluster/imgs/${CHANNEL}.*.vmlinuz | head -n 1 | sed -e "s,.*${CHANNEL}.,," -e "s,.coreos_.*,," )
if [[ -z ${LATEST} ]]; then
    echo "Couldn't find anything to load locally (${CHANNEL} channel)."
    echo "Fetching lastest $CHANNEL channel ISO ..."
    echo " "
    cd ~/kube-cluster/
    "${res_folder}"/bin/coreos-xhyve-fetch -f custom.conf
fi
}


function deploy_fleet_units() {
# deploy fleet units from ~/kube-cluster/fleet
cd ~/kube-cluster/fleet
echo "Starting all fleet units in ~/kube-cluster/fleet:"
fleetctl start fleet-ui.service
fleetctl start kube-apiserver.service
fleetctl start kube-controller-manager.service
fleetctl start kube-scheduler.service
fleetctl start kube-kubelet.service
fleetctl start kube-proxy.service
echo " "
echo "fleetctl list-units:"
fleetctl list-units
echo " "

}


function install_k8s_files {
# install k8s files on to VM
echo " "
echo "Installing Kubernetes files on to VM..."
cd ~/kube-cluster/kube
scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o LogLevel=quiet kube.tgz core@$vm_ip:/home/core
ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o LogLevel=quiet core@$vm_ip 'sudo /usr/bin/mkdir -p /opt/bin && sudo tar xzf /home/core/kube.tgz -C /opt/bin && sudo chmod 755 /opt/bin/*'
echo "Done with k8solo-01 "
echo " "
}


function install_k8s_add_ons {
echo " "
echo "Creating kube-system namespace ..."
~/kube-cluster/bin/kubectl create -f ~/kube-cluster/kubernetes/kube-system-ns.yaml
#
sed -i "" "s/_MASTER_IP_/$1/" ~/kube-cluster/kubernetes/skydns-rc.yaml
echo " "
echo "Installing SkyDNS ..."
~/kube-cluster/bin/kubectl create -f ~/kube-cluster/kubernetes/skydns-rc.yaml
~/kube-cluster/bin/kubectl create -f ~/kube-cluster/kubernetes/skydns-svc.yaml
#
echo " "
echo "Installing Kubernetes UI ..."
~/kube-cluster/bin/kubectl create -f ~/kube-cluster/kubernetes/kube-ui-rc.yaml
~/kube-cluster/bin/kubectl create -f ~/kube-cluster/kubernetes/kube-ui-svc.yaml
sleep 1
# clean up kubernetes folder
rm -f ~/kube-cluster/kubernetes/kube-system-ns.yaml
rm -f ~/kube-cluster/kubernetes/skydns-rc.yaml
rm -f ~/kube-cluster/kubernetes/skydns-svc.yaml
rm -f ~/kube-cluster/kubernetes/kube-ui-rc.yaml
rm -f ~/kube-cluster/kubernetes/kube-ui-svc.yaml
echo " "
}


function save_password {
# save user's password to Keychain
echo "  "
echo "Your Mac user's password will be saved in to 'Keychain' "
echo "and later one used for 'sudo' command to start VM !!!"
echo " "
echo "This is not the password to access VM via ssh or console !!!"
echo " "
echo "Please type your Mac user's password followed by [ENTER]:"
read -s my_password
passwd_ok=0

# check if sudo password is correct
while [ ! $passwd_ok = 1 ]
do
    # reset sudo
    sudo -k
    # check sudo
    echo -e "$my_password\n" | sudo -Sv > /dev/null 2>&1
    CAN_I_RUN_SUDO=$(sudo -n uptime 2>&1|grep "load"|wc -l)
    if [ ${CAN_I_RUN_SUDO} -gt 0 ]
    then
        echo "The sudo password is fine !!!"
        echo " "
        passwd_ok=1
    else
        echo " "
        echo "The password you entered does not match your Mac user password !!!"
        echo "Please type your Mac user's password followed by [ENTER]:"
        read -s my_password
    fi
done

security add-generic-password -a kube-cluster-app -s kube-cluster-app -w $password -U
}


function clean_up_after_vm {
sleep 3

# get App's Resources folder
res_folder=$(cat ~/kube-cluster/.env/resouces_path)

# Get password
my_password=$(security find-generic-password -wa kube-cluster-app)

# Stop webserver
kill $(ps aux | grep "[k]ube-solo-web" | awk {'print $2'})

# kill all kube-cluster/bin/xhyve instances
# ps aux | grep "[k]ube-solo/bin/xhyve" | awk '{print $2}' | sudo -S xargs kill | echo -e "$my_password\n"
echo -e "$my_password\n" | sudo -S pkill -f [k]ube-solo/bin/xhyve
#
echo -e "$my_password\n" | sudo -S pkill -f "${res_folder}"/bin/uuid2mac

# kill all other scripts
pkill -f [K]ube-Solo.app/Contents/Resources/start_VM.command
pkill -f [K]ube-Solo.app/Contents/Resources/bin/get_ip
pkill -f [K]ube-Solo.app/Contents/Resources/bin/get_mac
pkill -f [K]ube-Solo.app/Contents/Resources/bin/mac2ip
pkill -f [K]ube-Solo.app/Contents/Resources/fetch_latest_iso.command
pkill -f [K]ube-Solo.app/Contents/Resources/update_k8s.command
pkill -f [K]ube-Solo.app/Contents/Resources/update_osx_clients_files.command
pkill -f [K]ube-Solo.app/Contents/Resources/change_release_channel.command

}


function kill_xhyve {
sleep 3

# get App's Resources folder
res_folder=$(cat ~/kube-cluster/.env/resouces_path)

# Get password
my_password=$(security find-generic-password -wa kube-cluster-app)

# kill all kube-cluster/bin/xhyve instances
echo -e "$my_password\n" | sudo -S pkill -f [k]ube-solo/bin/xhyve

}

