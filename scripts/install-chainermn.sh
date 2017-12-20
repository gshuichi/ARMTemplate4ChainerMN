#!/bin/bash

CUPY_VERSION=2.2.0
CHAINER_VERSION=3.2.0
CHAINERMN_VERSION=1.0.0
USER_HOME=/share/home/hpcuser
USER_NAME=hpcuser

check_gpu()
{
	lspci | grep NVIDIA
	return $?
}

enable_rdma()
{
	apt install ibverbs-utils	

	# enable rdma      
	sed -i  "s/# OS.EnableRDMA=y/OS.EnableRDMA=y/g" /etc/waagent.conf
	sed -i  "s/# OS.UpdateRdmaDriver=y/OS.UpdateRdmaDriver=y/g" /etc/waagent.conf
}

setup_chainermn()
{
	sudo apt-get update
	sudo apt-get install git
	
	# Install Intel MPI
	if [ ! -d /opt/l_mpi_2018.1.163 ]; then
		cd /opt
		sudo curl -L -O http://registrationcenter-download.intel.com/akdlm/irc_nas/tec/12414/l_mpi_2018.1.163.tgz
		sudo tar zxvf l_mpi_2018.1.163.tgz
		sudo rm -rf l_mpi_2018.1.163.tgz
		cd l_mpi_2018.1.163
		sudo sed -i -e "s/decline/accept/g" silent.cfg
		sudo ./install.sh --silent silent.cfg
		source /opt/intel/compilers_and_libraries/linux/mpi/intel64/bin/mpivars.sh
	fi
	if [ ! -f /etc/profile.d/intel_mpi.sh ]; then
		echo 'export I_MPI_FABRICS=shm:dapl' >> /etc/profile.d/intel_mpi.sh
		echo 'export I_MPI_DAPL_PROVIDER=ofa-v2-ib0' >> /etc/profile.d/intel_mpi.sh
		echo 'export I_MPI_DYNAMIC_CONNECTION=0' >> /etc/profile.d/intel_mpi.sh
		echo 'export I_MPI_FALLBACK_DEVICE=0' >> /etc/profile.d/intel_mpi.sh
		echo 'source /opt/intel/compilers_and_libraries/linux/mpi/intel64/bin/mpivars.sh' >> /etc/profile.d/intel_mpi.sh
	fi

	# Install Anaconda3
	if [ ! -d /opt/anaconda3 ]; then
		cd /opt
		sudo curl -L -O https://repo.continuum.io/archive/Anaconda3-5.0.1-Linux-x86_64.sh
		sudo bash Anaconda3-5.0.1-Linux-x86_64.sh -b -p /opt/anaconda3
		sudo rm -rf Anaconda3-5.0.1-Linux-x86_64.sh
		sudo chown -R hpcuser:hpc /opt/anaconda3
		source /opt/anaconda3/bin/activate
	fi
	if grep -q "anaconda" $USER_HOME/.bashrc; then :; else
		sudo su -c "echo 'source /opt/anaconda3/bin/activate' >> $USER_HOME/.bashrc" $USER_NAME
	fi

	# Install NCCL2
	if [ ! -f /usr/lib/x86_64-linux-gnu/libnccl.so.2 ]; then
		cd /opt
		sudo curl -L -O http://developer.download.nvidia.com/compute/machine-learning/repos/ubuntu1604/x86_64/libnccl2_2.1.2-1+cuda9.0_amd64.deb
		sudo curl -L -O http://developer.download.nvidia.com/compute/machine-learning/repos/ubuntu1604/x86_64/libnccl-dev_2.1.2-1+cuda9.0_amd64.deb
		sudo dpkg -i libnccl2_2.1.2-1+cuda9.0_amd64.deb
		sudo dpkg -i libnccl-dev_2.1.2-1+cuda9.0_amd64.deb
		sudo rm -rf libnccl2_2.1.2-1+cuda9.0_amd64.deb
		sudo rm -rf libnccl-dev_2.1.2-1+cuda9.0_amd64.deb
	fi

	# Install cuDNN7
	if [ ! -f /usr/lib/x86_64-linux-gnu/libcudnn.so.7 ]; then
		cd /opt
		sudo curl -L -O http://developer.download.nvidia.com/compute/machine-learning/repos/ubuntu1604/x86_64/libcudnn7-dev_7.0.5.15-1+cuda9.1_amd64.deb
		sudo curl -L -O http://developer.download.nvidia.com/compute/machine-learning/repos/ubuntu1604/x86_64/libcudnn7_7.0.5.15-1+cuda9.1_amd64.deb
		sudo dpkg -i libcudnn7_7.0.5.15-1+cuda9.1_amd64.deb
		sudo dpkg -i libcudnn7-dev_7.0.5.15-1+cuda9.1_amd64.deb
		sudo rm -rf libcudnn7_7.0.5.15-1+cuda9.1_amd64.deb
		sudo rm -rf libcudnn7-dev_7.0.5.15-1+cuda9.1_amd64.deb
	fi

	sudo su - hpcuser
	pip install cupy==${CUPY_VERSION}
	pip install chainer==${CHAINER_VERSION}
	pip install mpi4py --no-cache-dir
	CFLAGS="-I/usr/local/cuda/include" pip install git+https://github.com/chainer/chainermn
	sudo chown -R hpcuser:hpc /opt/anaconda3
}

create_cron_job()
{
	# Register cron tab so when machine restart it downloads the secret from azure downloadsecret
	crontab -l > downloadsecretcron
	echo '@reboot /root/rdma-autoload.sh >> /root/execution.log' >> downloadsecretcron
	crontab downloadsecretcron
	rm downloadsecretcron
}

sudo su hpcuser
if check_gpu; then
	#Code to setup ChainerMN on GPU based machine
	enable_rdma
	setup_chainermn	
	mv /var/lib/waagent/custom-script/download/1/rdma-autoload.sh ~
	echo 0 | sudo tee /proc/sys/kernel/yama/ptrace_scope
	create_cron_job
fi

shutdown -r +1
exit 0