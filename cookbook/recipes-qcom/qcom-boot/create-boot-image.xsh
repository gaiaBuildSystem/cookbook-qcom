#!/usr/bin/env xonsh

# Copyright (c) 2025 MicroHobby
# SPDX-License-Identifier: MIT

# use the xonsh environment to update the OS environment
$UPDATE_OS_ENVIRON = True
# always return if a cmd fails
$RAISE_SUBPROC_ERROR = True


import os
import json
import os.path
from torizon_templates_utils.colors import print,BgColor,Color
from torizon_templates_utils.errors import Error_Out,Error


print("Creating qcom boot.img ...", color=Color.WHITE, bg_color=BgColor.GREEN)

# get the common variables
_ARCH = os.environ.get('ARCH')
_MACHINE = os.environ.get('MACHINE')
_MAX_IMG_SIZE = os.environ.get('MAX_IMG_SIZE')
_BUILD_PATH = os.environ.get('BUILD_PATH')
_DISTRO_MAJOR = os.environ.get('DISTRO_MAJOR')
_DISTRO_MINOR = os.environ.get('DISTRO_MINOR')
_DISTRO_PATCH = os.environ.get('DISTRO_PATCH')
_USER_PASSWD = os.environ.get('USER_PASSWD')
_IMAGE_NAME = os.environ.get('IMAGE_NAME')

# read the meta data
meta = json.loads(os.environ.get('META', '{}'))

# get the actual script path, not the process.cwd
_path = os.path.dirname(os.path.abspath(__file__))

_IMAGE_MNT_BOOT = f"{_BUILD_PATH}/tmp/{_MACHINE}/mnt/boot"
_IMAGE_MNT_ROOT = f"{_BUILD_PATH}/tmp/{_MACHINE}/mnt/root"
os.environ['IMAGE_MNT_BOOT'] = _IMAGE_MNT_BOOT
os.environ['IMAGE_MNT_ROOT'] = _IMAGE_MNT_ROOT
_DEPLOY_DIR = f"{_BUILD_PATH}/tmp/{_MACHINE}/deploy"
os.environ['DEPLOY_DIR'] = _DEPLOY_DIR


if os.environ["MACHINE"] == "arduino-uno-q":
    # .1 create the boot.img
    # zip the u-boot binary
    cd @(_BUILD_PATH)/tmp/@(_MACHINE)/u-boot/
    rm -rf u-boot-nodtb.bin.gz
    rm -rf u-boot-dtb.bin.gz
    gzip -k u-boot-nodtb.bin
    cat u-boot-nodtb.bin.gz ../linux/arch/arm64/boot/dts/qcom/qrb2210-arduino-imola.dtb > u-boot-dtb.bin.gz

    mkbootimg \
        --base 0x80000000 \
        --pagesize 4096 \
        --kernel u-boot-dtb.bin.gz \
        --cmdline "root=/dev/notreal" \
        --ramdisk /dev/null \
        --output @(_DEPLOY_DIR)/boot.img

    cd -

    # .2 detatch the /boot and /root partitions
    # this is needed because the flasher XML expects them to be separate
    # we have /boot mount on _IMAGE_MNT_BOOT and /root mount on _IMAGE_MNT_ROOT
    # the source file from the mount is _DEPLOY_DIR/_IMAGE_NAME
    # let's dd the /boot partition to _DEPLOY_DIR/boot.img and the /root partition to _DEPLOY_DIR/root.img
    # we know from common that boot partition is
    # parted $IMAGE_PATH -s mkpart primary fat32 8 158 \
    #     set 1 lba on align-check optimal 1 \
    #     mkpart primary ext4 159 $(($MAX_IMG_SIZE - 151))
    # therefore, we can calculate the offset and size for dd
    _BOOT_OFFSET = 8 * 1024 * 1024
    _BOOT_SIZE = (158 - 8) * 1024 * 1024
    _ROOT_OFFSET = 159 * 1024 * 1024
    _ROOT_SIZE = (int(_MAX_IMG_SIZE) - 151 - 159) * 1024 * 1024

    _BOOT_SKIP = _BOOT_OFFSET // 512
    _BOOT_COUNT = _BOOT_SIZE // 512
    _ROOT_SKIP = _ROOT_OFFSET // 512
    _ROOT_COUNT = _ROOT_SIZE // 512

    sync

    # dd the boot partition
    dd if=@(_DEPLOY_DIR)/@(_IMAGE_NAME) of=@(_DEPLOY_DIR)/disk-sdcard.img.esp bs=512 skip=@(_BOOT_SKIP) count=@(_BOOT_COUNT) status=none
    # dd the root partition
    dd if=@(_DEPLOY_DIR)/@(_IMAGE_NAME) of=@(_DEPLOY_DIR)/disk-sdcard.img.root bs=512 skip=@(_ROOT_SKIP) count=@(_ROOT_COUNT) status=none

    # .3 update the rawprogram0.xml.template for the flasher XML to flash
    _UBOOT_IMG_SIZE_KB = "4096.0"
    _ESP_IMG_SIZE_KB = str(_BOOT_SIZE // 1024)
    _ESP_IMG_SECTORS = str(_BOOT_SIZE // 512)
    _ROOT_IMG_SIZE_KB = str(_ROOT_SIZE // 1024)
    _ROOT_IMG_SECTORS = str(_ROOT_SIZE // 512)
    _ROOT_IMG_START_SECTOR = str(985408 + int(_ESP_IMG_SECTORS))

    with open(f"{_path}/{_MACHINE}/rawprogram0.xml.template", 'r') as file:
        _filedata = file.read()
        _filedata = _filedata.replace(
            '{{UBOOT_IMG_SIZE_KB}}',
            _UBOOT_IMG_SIZE_KB
        ).replace(
            '{{ESP_IMG_SIZE_KB}}',
            _ESP_IMG_SIZE_KB
        ).replace(
            '{{ESP_IMG_SECTORS}}',
            _ESP_IMG_SECTORS
        ).replace(
            '{{ROOT_IMG_SIZE_KB}}',
            _ROOT_IMG_SIZE_KB
        ).replace(
            '{{ROOT_IMG_SECTORS}}',
            _ROOT_IMG_SECTORS
        ).replace(
            '{{ROOT_IMG_START_SECTOR}}',
            _ROOT_IMG_START_SECTOR
        )

    with open(f"{_DEPLOY_DIR}/rawprogram0.xml", 'w') as file:
        file.write(_filedata)

else:
    Error_Out(
        f"Machine [{os.environ['MACHINE']}] is not supported",
        Error.EINVAL
    )


print("Creating qcom boot.img, OK", color=Color.WHITE, bg_color=BgColor.GREEN)
