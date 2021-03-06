#!/bin/bash

CUDA_VERSION=9.0

# Shares
SHARE_HOME=/share/home
NFS_ON_MASTER=/mnt/resource
NFS_MOUNT=/mnt/resource

# User
HPC_USER=hpcuser
HPC_UID=7007
HPC_GROUP=hpc
HPC_GID=7007

#############################################################################
log()
{
	echo "$0,$1,$2,$3"
}
usage() { echo "Usage: $0 [-s <masterName>] " 1>&2; exit 1; }

while getopts :s: optname; do
	log "Option $optname set with value ${OPTARG}"

	case $optname in
		s)  # master name
			export MASTER_NAME=${OPTARG}
			;;
		*)
			usage
			;;
	esac
done

setup_user()
{
	sudo apt-get update
	sudo apt-get -y install nfs-common
	
	# Automatically mount the user's home
    mkdir -p $SHARE_HOME
	echo "$MASTER_NAME:$SHARE_HOME $SHARE_HOME    nfs rsize=8192,wsize=8192,timeo=14,intr" >> /etc/fstab
	showmount -e ${MASTER_NAME}
	mount -a
    groupadd -g $HPC_GID $HPC_GROUP

    # Don't require password for HPC user sudo
    echo "$HPC_USER ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
    
    # Disable tty requirement for sudo
    sed -i 's/^Defaults[ ]*requiretty/# Defaults requiretty/g' /etc/sudoers

	useradd -c "HPC User" -g $HPC_GROUP -d $SHARE_HOME/$HPC_USER -s /bin/bash -u $HPC_UID $HPC_USER
}

mount_nfs()
{
	sudo apt-get -y install nfs-common

	log "install NFS"
	mkdir -p ${NFS_MOUNT}
	log "mounting NFS on " ${MASTER_NAME}
	showmount -e ${MASTER_NAME}
	mount -t nfs ${MASTER_NAME}:${NFS_ON_MASTER} ${NFS_MOUNT}
	sudo echo "${MASTER_NAME}:${NFS_ON_MASTER} ${NFS_MOUNT} nfs defaults,nofail 0 0" >> /etc/fstab
}

base_pkgs()
{
	#Install Kernel 
	cd /etc/apt/
	sudo echo "deb http://archive.ubuntu.com/ubuntu/ xenial-proposed restricted main multiverse universe" >> sources.list
	sudo apt-get update
	sudo apt-get -y upgrade
	
	# Install dapl, rdmacm, ibverbs, and mlx4
	sudo apt-get -y install libdapl2 libmlx4-1 ibverbs-utils
	
	# Set memlock unlimited
	cd /etc/security/
	sudo echo " *               hard    memlock          unlimited" >> limits.conf
	sudo echo " *               soft    memlock          unlimited" >> limits.conf

	# enable rdma
	sudo sed -i  "s/# OS.EnableRDMA=y/OS.EnableRDMA=y/g" /etc/waagent.conf
	sudo sed -i  "s/# OS.UpdateRdmaDriver=y/OS.UpdateRdmaDriver=y/g" /etc/waagent.conf
}

setup_cuda()
{
	log "setup_cuda-$CUDA_VERSION"
	CUDA_REPO_PKG=cuda-repo-ubuntu1604_9.1.85-1_amd64.deb
	wget -O /tmp/${CUDA_REPO_PKG} http://developer.download.nvidia.com/compute/cuda/repos/ubuntu1604/x86_64/${CUDA_REPO_PKG} 
	sudo dpkg -i /tmp/${CUDA_REPO_PKG}
	sudo apt-key adv --fetch-keys http://developer.download.nvidia.com/compute/cuda/repos/ubuntu1604/x86_64/7fa2af80.pub 
	rm -f /tmp/${CUDA_REPO_PKG}
	sudo apt-get update
	sudo apt-get install -y cuda-drivers
	sudo apt-get install -y cuda

	# if [ $CUDA_VERSION = 8.0 ]; then
	# 	sudo apt-get install -y cuda-8-0
	# fi
	# if [ $CUDA_VERSION = 9.0 ]; then
	# 	sudo apt-get install -y cuda-9-0
	# fi

	if [ -d /usr/local/cuda ]; then
		sudo rm -rf /usr/local/cuda
	fi
	sudo ln -s /usr/local/cuda-$CUDA_VERSION /usr/local/cuda
}

install_nccl()
{
	if [ -d /usr/local/cuda-8.0 ]; then
		if [ ! -f /usr/lib/x86_64-linux-gnu/libnccl.so.1 ]; then
			cd /opt
			sudo curl -L -O https://www.dropbox.com/s/9qrk97of646rgr6/nccl-repo-ubuntu1604-2.1.2-ga-cuda8.0_1-1_amd64.deb?dl=0
			sudo mv nccl-repo-ubuntu1604-2.1.2-ga-cuda8.0_1-1_amd64.deb?dl=0 nccl-repo-ubuntu1604-2.1.2-ga-cuda8.0_1-1_amd64.deb
			sudo dpkg -i nccl-repo-ubuntu1604-2.1.2-ga-cuda8.0_1-1_amd64.deb
			sudo rm -rf nccl-repo-ubuntu1604-2.1.2-ga-cuda8.0_1-1_amd64.deb
		fi
	fi
	if [ -d /usr/local/cuda-9.0 ]; then
		if [ ! -f /usr/lib/x86_64-linux-gnu/libnccl.so.2 ]; then
			cd /opt
			sudo curl -L -O https://www.dropbox.com/s/ke3278hcotn57cb/nccl-repo-ubuntu1604-2.1.2-ga-cuda9.0_1-1_amd64.deb?dl=0
			sudo mv nccl-repo-ubuntu1604-2.1.2-ga-cuda9.0_1-1_amd64.deb?dl=0 nccl-repo-ubuntu1604-2.1.2-ga-cuda9.0_1-1_amd64.deb
			sudo dpkg -i nccl-repo-ubuntu1604-2.1.2-ga-cuda9.0_1-1_amd64.deb
			sudo rm -rf nccl-repo-ubuntu1604-2.1.2-ga-cuda9.0_1-1_amd64.deb
		fi
	fi
}

install_cudnn7()
{
	if [ ! -f /usr/lib/x86_64-linux-gnu/libcudnn.so.7 ]; then
		cd /opt
		if [ -d /usr/local/cuda-8.0 ]; then
			cd /usr/local
			sudo curl -L -O https://www.dropbox.com/s/dufmxvrzj6ougce/cudnn-8.0-linux-x64-v7.tgz?dl=0
			sudo mv cudnn-8.0-linux-x64-v7.tgz?dl=0 cudnn-8.0-linux-x64-v7.tgz
			sudo tar zxvf cudnn-8.0-linux-x64-v7.tgz
			sudo rm -rf cudnn-8.0-linux-x64-v7.tgz
		fi
		if [ -d /usr/local/cuda-9.0 ]; then
			cd /usr/local
			sudo curl -L -O https://www.dropbox.com/s/i4ak03wn8vsxvs9/cudnn-9.0-linux-x64-v7.tgz?dl=0
			sudo mv cudnn-9.0-linux-x64-v7.tgz?dl=0 cudnn-9.0-linux-x64-v7.tgz
			sudo tar zxvf cudnn-9.0-linux-x64-v7.tgz
			sudo rm -rf cudnn-9.0-linux-x64-v7.tgz
		fi
	fi
}

sudo su $HPC_USER
sudo mkdir -p /var/local
SETUP_MARKER=/var/local/chainer-setup.marker
if [ -e "$SETUP_MARKER" ]; then
    echo "We're already configured, exiting..."
    exit 0
fi

setup_user

mount_nfs

base_pkgs

setup_cuda

install_nccl

install_cudnn7

if [ ! -f $SHARE_HOME/$HPC_USER/.bashrc ]; then
	touch $SHARE_HOME/$HPC_USER/.bashrc
fi
if grep -q "anaconda" $SHARE_HOME/$HPC_USER/.bashrc; then :; else
	sudo su -c "echo 'source /opt/anaconda3/bin/activate' >> $SHARE_HOME/$HPC_USER/.bashrc" $HPC_USER
	sudo su -c "echo 'export CUDA_PATH=/usr/local/cuda' >> $SHARE_HOME/$HPC_USER/.bashrc" $HPC_USER
	sudo su -c "echo 'export CPATH=/usr/local/cuda/include:\$CPATH' >> $SHARE_HOME/$HPC_USER/.bashrc" $HPC_USER
	sudo su -c "echo 'export LIBRARY_PATH=/usr/local/cuda/lib64:\$LIBRARY_PATH' >> $SHARE_HOME/$HPC_USER/.bashrc" $HPC_USER
	sudo su -c "echo 'export LD_LIBRARY_PATH=/usr/local/cuda/lib64:\$LD_LIBRARY_PATH' >> $SHARE_HOME/$HPC_USER/.bashrc" $HPC_USER
	sudo su -c "echo 'export PATH=/usr/local/cuda/bin:\$PATH' >> $SHARE_HOME/$HPC_USER/.bashrc" $HPC_USER
fi

# Create marker file so we know we're configured
sudo touch $SETUP_MARKER

exit 0