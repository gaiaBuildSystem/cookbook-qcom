#!/usr/bin/env xonsh

# Copyright (c) 2025 MicroHobby
# SPDX-License-Identifier: MIT

# use the xonsh environment to update the OS environment
$UPDATE_OS_ENVIRON = True
# always return if a cmd fails
$XONSH_SUBPROC_CMD_RAISE_ERROR = True


import os
import json
import os.path
from torizon_templates_utils.colors import print,BgColor,Color
from torizon_templates_utils.errors import Error_Out,Error


print("Deploying initramfs modules ...", color=Color.WHITE, bg_color=BgColor.GREEN)

# get the common variables
_ARCH = os.environ.get('ARCH')
_MACHINE = os.environ.get('MACHINE')
_MAX_IMG_SIZE = os.environ.get('MAX_IMG_SIZE')
_BUILD_PATH = os.environ.get('BUILD_PATH')
_DISTRO_MAJOR = os.environ.get('DISTRO_MAJOR')
_DISTRO_MINOR = os.environ.get('DISTRO_MINOR')
_DISTRO_PATCH = os.environ.get('DISTRO_PATCH')
_USER_PASSWD = os.environ.get('USER_PASSWD')
_INITRAMFS_PATH = os.environ.get('INITRAMFS_PATH')

# read the meta data
meta = json.loads(os.environ.get('META', '{}'))

# get the actual script path, not the process.cwd
_path = os.path.dirname(os.path.abspath(__file__))

_IMAGE_MNT_BOOT = f"{_BUILD_PATH}/tmp/{_MACHINE}/mnt/boot"
_IMAGE_MNT_ROOT = f"{_BUILD_PATH}/tmp/{_MACHINE}/mnt/root"
os.environ['IMAGE_MNT_BOOT'] = _IMAGE_MNT_BOOT
os.environ['IMAGE_MNT_ROOT'] = _IMAGE_MNT_ROOT

if os.environ["MACHINE"] == "arduino-uno-q":
    # display and usb modules
    # The Arduino Uno Q is weird and if you want HDMI output
    # you will need to have an USB HUB connected to the board
    _mods_to_probe = [
        # thermal
        "lmh",
        # bwmon
        "icc-bwmon",
        # i2c/spi
        "socinfo",
        "pinctrl-lpass-lpi",
        "pinctrl-sm6115-lpass-lpi",
        "gpi",
        "spi-geni-qcom",
        "i2c-qcom-geni",
        # USB-related modules
        "cdc_ncm",
        "cdc_ether",
        "usbnet",
        "onboard_usb_dev",
        "qcom_usb_vbus-regulator",
        "phy-qcom-qmp-usbc",
        "phy-qcom-qusb2",
        "typec",

        # DRM/display-related modules
        "anx7625",
        "dispcc-qcm2290",
        "gpucc-qcm2290",
        "qrtr",
        "msm",
        "drm",
        "drm_kms_helper",
        "drm_display_helper",
        "gpu-sched",
        "ocmem",
        "llcc-qcom",
        "drm_dp_aux_bus",
        "drm_exec",
        "mdt_loader",
        "drm_client_lib",
        "drm_panel_orientation_quirks",
        "backlight",
        "cec",

        # Display-adjacent module for HDMI audio path
        "snd-soc-hdmi-codec",
    ]

    # make the /usr/lib/modules/<kernel_version> at initramfs
    # the kernel_version or the folder name will be the same as from the
    # target rootfs, so we can just copy the modules from there
    _target_modules_path = f"{_IMAGE_MNT_ROOT}/usr/lib/modules"
    # get the kernel version from the target rootfs
    _kernel_version = os.listdir(_target_modules_path)[0]

    # find and then create the path and copy the modules to the initramfs
    _initramfs_modules_path = f"{_INITRAMFS_PATH}/usr/lib/modules"
    for root, dirs, files in os.walk(_target_modules_path):
        for file in files:
            if file.endswith(".ko"):
                # get the module name without the .ko extension
                mod_name = file[:-3]
                if mod_name in _mods_to_probe:
                    # create the same directory structure in the initramfs
                    rel_dir = os.path.relpath(root, _target_modules_path)
                    dest_dir = os.path.join(_initramfs_modules_path, rel_dir)
                    sudo mkdir -p @(dest_dir)

                    # copy the module to the initramfs
                    src_file = os.path.join(root, file)
                    dest_file = os.path.join(dest_dir, file)
                    sudo -k cp -f @(src_file) @(dest_file)

    # also we need the modules.dep and modules.alias files for depmod to work
    # in the initramfs
    for dep_file in ["modules.dep", "modules.alias"]:
        src_file = f"{_target_modules_path}/{_kernel_version}/{dep_file}"
        dest_file = f"{_initramfs_modules_path}/{_kernel_version}/{dep_file}"
        sudo -k cp -f @(src_file) @(dest_file)

    # at the initramfs we have /lib but is not the symlink for /usr/lib,
    # so we need to create the symlink for the modules too
    sudo rm -rf @(_INITRAMFS_PATH)/lib
    sudo ln -sfn /usr/lib @(_INITRAMFS_PATH)/lib

    # finaly we copy the busybox script that will modprobe the modules
    sudo -k cp -f @(_path)/busybox/@(_MACHINE)/02-mods.sh \
        @(_INITRAMFS_PATH)/scripts/02-mods.sh

elif os.environ["MACHINE"] == "arduino-ventuno-q":
    # the display stack (msm dpu/dsi, adv7535 bridge, i2c-geni, clocks) is
    # built-in, but the HDMI path still needs firmware at probe time:
    # the ADV7535 sits on i2c12 and, when the bootloader did not program
    # that QUP serial engine, i2c-qcom-geni loads qupv3fw.elf through
    # request_firmware(). Without it in the initramfs the i2c bus defers,
    # the bridge never probes and DSI never brings up the HDMI output.
    # The Adreno 623 sqe/gmu blobs are also needed to bring up the GPU.
    # These are deployed to the rootfs by the linux-firmware recipe
    # (customData.firmwares), keep the same paths here
    _fws_to_copy = [
        # QUP serial engine (i2c12 -> ADV7535 DSI to HDMI bridge)
        "qcom/qcs8300/qupv3fw.elf",
        # Adreno 623 GPU
        "qcom/a650_sqe.fw",
        "qcom/a623_gmu.bin",
    ]

    _target_fw_path = f"{_IMAGE_MNT_ROOT}/lib/firmware"
    # the kernel firmware loader searches /lib/firmware
    _initramfs_fw_path = f"{_INITRAMFS_PATH}/lib/firmware"

    for fw in _fws_to_copy:
        _src_file = f"{_target_fw_path}/{fw}"

        if not os.path.exists(_src_file):
            Error_Out(
                f"Firmware [{fw}] not found at {_target_fw_path}, check the linux-firmware recipe",
                Error.ENOFOUND
            )

        _dest_dir = os.path.dirname(f"{_initramfs_fw_path}/{fw}")
        sudo mkdir -p @(_dest_dir)
        sudo -k cp -f @(_src_file) @(_dest_dir)/

else:
    Error_Out(
        f"Machine [{os.environ['MACHINE']}] is not supported",
        Error.EINVAL
    )

print("Deploying initramfs modules, OK", color=Color.WHITE, bg_color=BgColor.GREEN)
