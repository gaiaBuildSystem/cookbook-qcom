#!/usr/bin/env xonsh

# Copyright (c) 2025 MicroHobby
# SPDX-License-Identifier: MIT

# use the xonsh environment to update the OS environment
$UPDATE_OS_ENVIRON = True
# always return if a cmd fails
$XONSH_SUBPROC_CMD_RAISE_ERROR = True


import os
import sys
import json
import subprocess
import os.path
from torizon_templates_utils.colors import print,BgColor,Color
from torizon_templates_utils.errors import Error_Out,Error


print("Deploy qcom-boot UEFI ...", color=Color.WHITE, bg_color=BgColor.GREEN)

# get the common variables
_ARCH = os.environ.get('ARCH')
_CLEAN = os.environ.get('CLEAN_IMAGE')
_MACHINE = os.environ.get('MACHINE')
_MAX_IMG_SIZE = os.environ.get('MAX_IMG_SIZE')
_BUILD_PATH = os.environ.get('BUILD_PATH')
_DISTRO = os.environ.get('DISTRO')
_DISTRO_MAJOR = os.environ.get('DISTRO_MAJOR')
_DISTRO_MINOR = os.environ.get('DISTRO_MINOR')
_DISTRO_PATCH = os.environ.get('DISTRO_PATCH')
_USER_PASSWD = os.environ.get('USER_PASSWD')
_HOME = os.environ.get('HOME')

# make sure to accept install pip packages system-wide
$PIP_BREAK_SYSTEM_PACKAGES="1"
os.environ['PIP_BREAK_SYSTEM_PACKAGES'] = "1"

# read the meta data
meta = json.loads(os.environ.get('META', '{}'))

# get the actual script path, not the process.cwd
_path = os.path.dirname(os.path.abspath(__file__))

_IMAGE_MNT_BOOT = f"{_BUILD_PATH}/tmp/{_MACHINE}/mnt/boot"
_IMAGE_MNT_ROOT = f"{_BUILD_PATH}/tmp/{_MACHINE}/mnt/root"
os.environ['IMAGE_MNT_BOOT'] = _IMAGE_MNT_BOOT
os.environ['IMAGE_MNT_ROOT'] = _IMAGE_MNT_ROOT

# if is not the ventuno just error out
if _MACHINE != "arduino-ventuno-q":
    Error_Out(
       f"Machine [{_MACHINE}] not supported",
        Error.EINVAL
    )

# install the systemd-boot to the boot partition
sudo mkdir -p @(_IMAGE_MNT_ROOT)/boot
sudo mount --bind @(_IMAGE_MNT_BOOT) @(_IMAGE_MNT_ROOT)/boot
sudo chroot @(_IMAGE_MNT_ROOT) bash -c 'SYSTEMD_RELAX_ESP_CHECKS=1 bootctl --esp=/boot --no-variables install'

# replace the distro var
_entry_file = f"{_path}/{_MACHINE}/gaia.conf.template"
with open(_entry_file, 'r') as _f:
    _entry_content = _f.read()
_entry_content = _entry_content.replace('{{DISTRO}}', f"{_DISTRO}")
_entry_content = _entry_content.replace('{{DISTRO_MAJOR}}', str(_DISTRO_MAJOR))
_entry_content = _entry_content.replace('{{DISTRO_MINOR}}', str(_DISTRO_MINOR))
_entry_content = _entry_content.replace('{{DISTRO_PATCH}}', str(_DISTRO_PATCH))

# write the modified entry content to the systemd-boot directory
mkdir -p @(f"{_BUILD_PATH}/tmp/{_MACHINE}/systemd-boot")
_entry_result_file = f"{_BUILD_PATH}/tmp/{_MACHINE}/systemd-boot/gaia.conf"
with open(_entry_result_file, 'w') as _f:
    _f.write(_entry_content)

sudo mkdir -p @(_IMAGE_MNT_BOOT)/loader/entries
sudo -k cp -f @(_BUILD_PATH)/tmp/@(_MACHINE)/systemd-boot/gaia.conf @(_IMAGE_MNT_BOOT)/loader/entries/gaia.conf

# umount the boot partition
sudo umount @(_IMAGE_MNT_ROOT)/boot


print("Deploy qcom-boot UEFI, OK", color=Color.WHITE, bg_color=BgColor.GREEN)
