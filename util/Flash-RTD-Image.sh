#!/bin/bash
flash_log=Flash_log.log
rm $flash_log

RTD_FLASH(){
	# Local Variables for apt package handling logic 

	# Echo results to user
	printf "RTD CNV36RNX Flash Wrapper Program\n"
	printf "Choose an Image to Flash:\n"
	printf "    1) Orin NX/Nano \n"
	printf "    2) Orin NX/Nano Super \n"
	printf "> "
	local kbinput=n
	read kbinput
	if [[ "$kbinput" == "1" ]]; then
		printf "Flashing NX Image..."
		sudo ./tools/kernel_flash/l4t_initrd_flash.sh --external-device nvme0n1p1 -p "-c ./bootloader/generic/cfg/flash_t234_qspi.xml" -c ./tools/kernel_flash/flash_l4t_t234_nvme.xml --showlogs --network usb0 CNV36JRN201 internal

	elif [[ "$kbinput" == "2" ]]; then
		printf "Flashing NX Super Image..." 
		sudo ./tools/kernel_flash/l4t_initrd_flash.sh --external-device nvme0n1p1 -p "-c ./bootloader/generic/cfg/flash_t234_qspi.xml" -c ./tools/kernel_flash/flash_l4t_t234_nvme.xml --showlogs --network usb0 CNV36JRN201-super internal
	else
		printf "Unknown Target halting...\n"
	fi
}
	
# MAIN
pushd Linux_for_Tegra
	RTD_FLASH
popd
