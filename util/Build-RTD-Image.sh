#/bin/bash
printf "RTD Image FOR THE CNV36JXNX\n\n"

returned=0

export LOCALVERSION=-tegra
export TEGRA_KERNEL_OUT=$PWD/kernel/kernel_out
export CROSS_COMPILE_AARCH64_PATH=$PWD/l4t-gcc
export CROSS_COMPILE=$PWD/l4t-gcc/bin/aarch64-buildroot-linux-gnu-
export CROSS_COMPILE_AARCH64=$PWD/l4t-gcc/bin/aarch64-buildroot-linux-gnu-
export MOD_PATH=$PWD/Linux_for_Tegra/rootfs
DEVICE_TREE_ONLY=0



apply_rtd_changes(){
	
	#Apply RTD Changes
	
	printf "Copying RTD defined *.dtsi files......\n"
	# Copy RTD PinMux and GPIO Files
	cp rtd_files/pinmux/Orin-jetson_orin-pinmux.dtsi Linux_for_Tegra/bootloader/generic/BCT/
	cp rtd_files/pinmux/Orin-jetson_orin-padvoltage-default.dtsi Linux_for_Tegra/bootloader/
	cp rtd_files/pinmux/Orin-jetson_orin-gpio-default.dtsi Linux_for_Tegra/bootloader/

	eeprom_file=Linux_for_Tegra/bootloader/generic/BCT/tegra234-mb2-bct-misc-p3767-0000.dts

	# modify the EEPROM Search -- Double check these
	sed -i "s/cvb_eeprom_read_size.*/cvb_eeprom_read_size = <0x0>;/g" $eeprom_file 

	printf "Adding RTD Device-Tree Files......\n"
	rsync -va rtd_files/nv-public/ "Linux_for_Tegra/source/hardware/nvidia/t23x/nv-public/"
	
	# Patch to fix Pericom Switch Incompatibilities -- fixed in kernel version 5.16+ required patch by rtd for NVIDIA 
	sudo cp -v rtd_files/perifix.sh Linux_for_Tegra/rootfs/etc/init.d
	pushd Linux_for_Tegra/rootfs/etc/rc3.d
	        sudo ln -s ../init.d/perifix.sh S01perifix
	popd

	# Add Camera Overlays to the boot directory so jetson IO program can be used

        pushd Linux_for_Tegra/
                sudo cp -v kernel/dtb/tegra234-orin-nx*.dtbo rootfs/boot/
        popd

	# kernel configuration... make sure to move a custom kernel configuration here if needed
	#cp rtd_files/rtd-defconfig "Linux_for_Tegra/source/kernel/kernel-jammy-src/arch/arm64/configs/defconfig"

	cp rtd_files/CNV36JRN201*.conf Linux_for_Tegra/


	# Apply RTD defconfig changes

	 RTD_CONFIG=$PWD/rtd_files/rtd.fragment

        pushd "Linux_for_Tegra/source/kernel/kernel-jammy-src/"
                DEFCONFIG=$PWD/arch/arm64/configs/defconfig
                ./scripts/kconfig/merge_config.sh -m ${DEFCONFIG} ${RTD_CONFIG}
                mv .config $DEFCONFIG
        popd


	
}

#
# Verify the packages listed in required_packages.txt are
# installed with apt-get 
#
verify_packages(){
	# Local Variables for apt package handling logic 
	local req_pkg_list=required_packages.txt
	local current_pkg_list=installed_pkglist.txt
	local missing_packages=0

	# Verify that the package list file exists
	if [ ! -e $req_pkg_list ]; then
		printf "$req_pkg_list not found. Exiting.\n"
		return 255
	fi
	
	
	# create full list of packages and save as file for querying
	dpkg -l > $current_pkg_list 
	
	
	for pkg_name in `cat $req_pkg_list`; do
	
		if grep -iqe $pkg_name $current_pkg_list; then
			printf "$pkg_name ?: YES\n"
		else
			printf "$pkg_name ?: NO\n"
			missing_packages=1
		fi
	done

	# remove package list temp file
	rm -f $current_pkg_list 
	
	# Echo results to user
	if [[ $missing_packages !=  0 ]]; then
		printf "\nThis script requires certain packages to be installed and cannot verify they exist with dkpg\n"
		printf "If you are not using ubuntu please verify the package equivalents manually\n"
		printf "Otherwise please install them with $ sudo apt-get install <package name>\n"
		printf "Would you like to install them now? (y/n): "
		local kbinput=n
		read kbinput
		if [[ "$kbinput" == "y" ]]; then
			for pkg_name in `cat $req_pkg_list`; do
				sudo apt-get install -y $pkg_name
			done
			# signal to control flow to try checking again
			return 1	
		else
			# signal to control flow to terminate bash
			return 255
		fi 
	fi
	
	printf "==============\nPackages Okay\n==============\n"
	return 0
}

verify_internet_connection()
{
	wget -q --spider http://google.com
	if [ $? -eq 0 ]; then
		return 0;
	else
		return 1;
	fi
}

old_build_kernel()
{

	if [[ -d $TEGRA_KERNEL_OUT && $DEVICE_TREE_ONLY -eq 0 ]]; then
		printf "\n\n\nPath ./kernel/kernel_out already exists would you like to rebuild the linux Kernel? (y/n):" 
		local kbinput=n
		read kbinput
		if [[ "$kbinput" == "n" ]]; then
			DEVICE_TREE_ONLY=1		
		fi 		
	fi	

	mkdir -p $TEGRA_KERNEL_OUT
	
	# Alternative Build Strategy
	CROSS_COMPILE=$PWD/l4t-gcc/aarch64--glibc--stable-2022.08-1/bin/aarch64-buildroot-linux-gnu-
 

        pushd kernel/kernel_src
                if [ $DEVICE_TREE_ONLY -eq 1 ];then
                        # Skip building the kernel and  
                        # build modules and Device Tree
                        # this requires a previous build
                        export KERNEL_HEADERS="../kernel_out/kernel/kernel-jammy-src"
                        echo "MOD BUILD" 
                        #./nvbuild.sh -o ../kernel_out/ -m      
                        #make -C "../kernel_out" modules
                        make -C "../kernel_out" dtbs
                else
                        # Build it all
                        echo "FULL BUILD" 
                        ./nvbuild.sh -o ../kernel_out/
                fi
        popd




        # Copy Kernel Image to the Linux_for_Tegra      
        cp -vr $TEGRA_KERNEL_OUT/kernel/kernel-jammy-src/arch/arm64/boot/Image Linux_for_Tegra/kernel/

	# move dtb to the proper directory.
	sudo cp -v $TEGRA_KERNEL_OUT/nvidia-oot/device-tree/platform/generic-dts/dtbs/* Linux_for_Tegra/kernel/dtb/
	
	#Apply Nvidia Changes
	printf "applying binaries......\n"
	pushd Linux_for_Tegra > /dev/null
		sudo ./apply_binaries.sh
	popd > /dev/null

}


build_kernel()
{
	CROSS_COMPILE=$PWD/l4t-gcc/aarch64--glibc--stable-2022.08-1/bin/aarch64-buildroot-linux-gnu-
	export INSTALL_MOD_PATH="$(pwd)/Linux_for_Tegra/rootfs/"
	export KERNEL_HEADERS="$(pwd)/Linux_for_Tegra/source/kernel/kernel-jammy-src"
	sudo ./Linux_for_Tegra/apply_binaries.sh

	pushd "Linux_for_Tegra/source"
		make -C kernel
		sudo -E make install -C kernel
		cp kernel/kernel-jammy-src/arch/arm64/boot/Image \
			../kernel/Image
		make modules
		sudo -E make modules_install
	popd

	pushd "Linux_for_Tegra"
		sudo ./tools/l4t_update_initrd.sh
	popd
	
	pushd "Linux_for_Tegra/source"
		make dtbs
		#Path Changed in 36.4.3
		#cp nvidia-oot/device-tree/platform/generic-dts/dtbs/* \
		cp kernel-devicetree/generic-dts/dtbs/* \
			../kernel/dtb/
	popd

        # Add Camera Overlays to the boot directory so jetson IO program can be used
        pushd Linux_for_Tegra/
                sudo cp -v kernel/dtb/tegra234-orin-nx*.dtbo rootfs/boot/
        popd

}

post_build()
{
	# Fix the Symbolic Link so that it Targets the new directory
	sudo ln -sfn "/usr/src/linux-headers-5.15.148-tegra-ubuntu22.04_aarch64/3rdparty/canonical/linux-jammy/kernel-source" "Linux_for_Tegra/rootfs/lib/modules/5.15.148-tegra/build"
	sudo ln -sfn "/usr/src/linux-headers-5.15.148-tegra-ubuntu22.04_aarch64/3rdparty/canonical/linux-jammy/kernel-source" "Linux_for_Tegra/rootfs/lib/modules/5.15.148-tegra/source"



}


# Parse Input parameters
while getopts "m" opt; do
        case "${opt}" in
                m) # Build device Tree only skipping the kernel build process for testing purposes.

        		printf "Skipping Full Kernel Build.\n\n"
                        DEVICE_TREE_ONLY=1
                        ;;
                *)
                        ;;
        esac
done



#
# Start Program
#
printf "checking for internet connectivity......\n"
verify_internet_connection
if [ $? -eq 1 ]; then
	printf "No internet connection detected, please connect before running this script.\n\n"
	exit 1
fi


printf "Checking apt package dependencies......\n"
while : ; do
	verify_packages
	returned=$? #get the return value of previous function call 
	
	# Hard break process
	if [[ $returned = 255 ]]; then
		exit 1	
	fi
	# returned 1: try again to verify packages
	# returned 0: Leave loop and continue operation  
	if [ $returned -eq 0 ]; then
		break
	fi
done;

printf "Fetch NVIDIA Source......\n\n"

mkdir -p nvidia_files

#Execute relative to nvidia_files
pushd nvidia_files > /dev/null
	# Check to see if theres already tbz2 files indicating a non-clean start
	find *.tbz2 &> /dev/null	
	if [ $? -eq 0 ]; then
		printf "nvidia source *.tbz2 presumed to already exist... skipping wget\n"						
	else
                wget -q "https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v4.3/release/tegra_linux_sample-root-filesystem_r36.4.3_aarch64.tbz2"
                wget -q "https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v4.3/release/jetson_linux_r36.4.3_aarch64.tbz2"
                wget -q "https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v3.0/toolchain/aarch64--glibc--stable-2022.08-1.tar.bz2"
		wget -q "https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v4.3/sources/public_sources.tbz2"

	fi
popd > /dev/null



printf "Attempting to Extract NVIDIA Source......\n\n"

if [ -d "Linux_for_Tegra" ]; then
	printf "Linux_For_Tegra Directory exists: assuming extraction already done previously\n\n"	
else
	printf "AARCH64...\n"
	# hardware makes a Linux_for_Tegra Directory
	tar -xjf "nvidia_files/jetson_linux_r36.4.3_aarch64.tbz2"
		
	printf "rootfs...\n"
	# extract this archive preserving its permission structure
	sudo tar -C Linux_for_Tegra/rootfs/ -xjpf "nvidia_files/tegra_linux_sample-root-filesystem_r36.4.3_aarch64.tbz2"
	# extract nvidias approved gcc compiler
	printf "cross compiler...\n"
	mkdir -p l4t-gcc
	tar -C l4t-gcc/ -xf "nvidia_files/aarch64--glibc--stable-2022.08-1.tar.bz2"


	printf "Nvidia Public Sources...\n"
	tar -xjf nvidia_files/public_sources.tbz2
	pushd "Linux_for_Tegra/source/"
		printf "Kernel Sources...\n"
		tar -xjf kernel_src.tbz2
		printf "OOT Modules...\n"
		tar -xjf kernel_oot_modules_src.tbz2
		printf "Display Drivers Modules...\n"
		tar -xjf nvidia_kernel_display_driver_source.tbz2
	popd

	printf "Extaction Complete!\n\n"
fi

# do everything here before makeing the kernel
apply_rtd_changes


# Build Kernel
build_kernel

# Do post Build Steps
post_build


printf "Complete\n"
