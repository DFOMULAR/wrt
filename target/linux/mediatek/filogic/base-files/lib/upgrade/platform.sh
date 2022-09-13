REQUIRE_IMAGE_METADATA=1

redmi_ax6000_nand_upgrade_cleanup()
{
	local mtdnum="$( find_mtd_index ubi )"
	if [ ! "$mtdnum" ]; then
		echo "cannot find ubi mtd partition ubi"
		return 1
	fi

	local kern_mtdnum="$( find_mtd_index ubi_kernel )"
	if [ ! "$kern_mtdnum" ]; then
		echo "cannot find ubi_kernel mtd partition ubi_kernel"
		return 1
	fi

	#XXX: for first time sysupgrade from initramfs, the ubi may contain old 'data' volume
	local ubidev="$( nand_find_ubi ubi )"
	if [ "$ubidev" ] && [ "$( nand_find_volume $ubidev data )" ]; then
		ubidetach -m "$mtdnum"
		ubiformat /dev/mtd$mtdnum -y
		ubiattach -m "$mtdnum"
	fi

	#XXX: for first time sysupgrade from initramfs, the ubi_kernel may contain old 'rootfs' volume
	local kern_ubidev="$( nand_find_ubi ubi_kernel )"
	if [ "$kern_ubidev" ] && [ "$( nand_find_volume $kern_ubidev rootfs )" ]; then
		ubidetach -m "$kern_mtdnum"
		ubiformat /dev/mtd$kern_mtdnum -y
		ubiattach -m "$kern_mtdnum"
	fi

	#setup uboot env to make sure it always boot, sometimes user may forget to setup this env before sysupgrade from initramfs
	if ! fw_printenv -n flag_try_sys2_failed &>/dev/null; then
		echo "uboot env cannot read/write, skip"
		return 0
	fi
	flag_try_sys2_failed=$(fw_printenv -n flag_try_sys2_failed)
	if test $flag_try_sys2_failed -lt 8; then
		fw_setenv boot_wait on
		fw_setenv uart_en 1
		fw_setenv flag_boot_rootfs 0
		fw_setenv flag_last_success 1
		fw_setenv flag_boot_success 1
		fw_setenv flag_try_sys1_failed 8
		fw_setenv flag_try_sys2_failed 8
		fw_setenv mtdparts "nmbm0:1024k(bl2),256k(Nvram),256k(Bdata),2048k(factory),2048k(fip),256k(crash),256k(crash_log),30720k(ubi),30720k(ubi1),51200k(overlay)"
	fi
}

platform_do_upgrade() {
	local board=$(board_name)

	case "$board" in
	bananapi,bpi-r3)
		case "$(cmdline_get_var root)" in
		/dev/mmc*)
			CI_ROOTDEV="$rootdev"
			CI_KERNPART="production"
			emmc_do_upgrade "$1"
			;;
		/dev/mtdblock*)
			PART_NAME="fit"
			default_do_upgrade "$1"
			;;
		/dev/ubiblock*)
			CI_KERNPART="fit"
			nand_do_upgrade "$1"
			;;
		esac
		;;
	xiaomi,redmi-router-ax6000-stock)
		CI_KERN_UBIPART=ubi_kernel
		CI_ROOT_UBIPART=ubi
		nand_do_upgrade "$1"
		;;
	*)
		nand_do_upgrade "$1"
		;;
	esac
}

PART_NAME=firmware

platform_check_image() {
	local board=$(board_name)
	local magic="$(get_magic_long "$1")"

	[ "$#" -gt 1 ] && return 1

	case "$board" in
	bananapi,bpi-r3)
		[ "$magic" != "d00dfeed" ] && {
			echo "Invalid image type."
			return 1
		}
		return 0
		;;
	*)
		nand_do_platform_check "$board" "$1"
		return 0
		;;
	esac

	return 0
}

platform_copy_config() {
	case "$(board_name)" in
	bananapi,bpi-r3)
		case "$(cmdline_get_var root)" in
		/dev/mmc*)
			emmc_copy_config
			;;
		esac
		;;
	esac
}

platform_pre_upgrade() {
	local board=$(board_name)

	case "$board" in
	xiaomi,redmi-router-ax6000-stock)
		redmi_ax6000_nand_upgrade_cleanup
		;;
	esac
}
