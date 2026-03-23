#!/bin/busybox sh

# 0. clock base
modprobe lmh
modprobe icc_bwmon
modprobe socinfo
modprobe gpi
modprobe pinctrl_sm6115_lpass_lpi
modprobe spi_geni_qcom
modprobe i2c_qcom_geni

# 1. Core DRM primitives (no dependencies)
modprobe drm_panel_orientation_quirks
modprobe drm

# 2. GPU/display scheduling and execution helpers
modprobe gpu_sched
modprobe drm_exec

# 3. Memory/firmware loaders (needed by msm and others)
modprobe mdt_loader
modprobe ocmem
modprobe llcc_qcom

# 4. Clock & power domain controllers (many modules depend on these)
modprobe dispcc_qcm2290
modprobe gpucc_qcm2290

# 5. QRTR (IPC, needed before qcom subsystem drivers)
modprobe qrtr

# 6. DRM display stack (order matters: aux -> helpers -> kms)
modprobe drm_dp_aux_bus
modprobe drm_display_helper
modprobe drm_kms_helper
modprobe drm_client_lib
modprobe cec
modprobe backlight

# 7. USB physical layer (before typec and usb drivers)
modprobe phy_qcom_qusb2
modprobe phy_qcom_qmp_usbc
modprobe typec

# 8. USB network drivers
modprobe usbnet
modprobe cdc_ether
modprobe cdc_ncm
modprobe onboard_usb_dev
modprobe qcom_usb_vbus_regulator

# 9. ANX7625 bridge (depends on drm_dp_aux_bus, drm_display_helper, typec)
modprobe anx7625

# 10. MSM display/GPU driver (the main driver, must be last)
modprobe msm

# 11. HDMI audio codec (depends on msm being up)
modprobe snd_soc_hdmi_codec

# now make it take some time to then the hardware settle
sleep 2
