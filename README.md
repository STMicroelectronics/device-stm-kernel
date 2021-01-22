# stm32mp1-kernel #

This module is used to provide
* prebuilt images of the Linux kernel, modules and device tree for STM32MP1
* scripts to load and build Linux kernel source for STM32MP1

It is part of the STMicroelectronics delivery for Android (see the [delivery][] for more information).

[delivery]: https://wiki.st.com/stm32mpu/wiki/STM32MP15_distribution_for_Android_release_note_-_v2.0.0

## Description ##

This module version is the updated version for STM32MP15 distribution for Android V2.0
Please see the release notes for more details.

## Documentation ##

* The [release notes][] provide information on the release.
* The [distribution package][] provides detailed information on how to use this delivery.

[release notes]: https://wiki.st.com/stm32mpu/wiki/STM32MP15_distribution_for_Android_release_note_-_v2.0.0
[distribution package]: https://wiki.st.com/stm32mpu/wiki/STM32MP1_Distribution_Package_for_Android

## Dependencies ##

This module can't be used alone. It is part of the STMicroelectronics delivery for Android.

## Containing ##

This module contains several files and directories.

**prebuilt**
* `./prebuilt/kernel-stm32mp1`: prebuilt image of the Linux kernel
* `./prebuilt/dts/*`: prebuilt images of the device tree (.dtb)
* `./prebuilt/modules/*`: prebuilt images of the driver modules (.ko)

**source**
* `./source/load_kernel.sh`: script used to load Linux kernel source with required patches for STM32MP1
* `./source/build_kernel.sh`: script used to generate/update prebuilt images
* `./source/android_kernelbuild.config`: configuration file used by the build_kernel.sh script
* `./source/kconfig/*`: Linux kernel configuration fragments
* `./source/patch/*`: Linux kernel patches required (not yet up-streamed)

## License ##

This module is distributed under the Apache License, Version 2.0 found in the [Apache-2.0](./LICENSES/Apache-2.0) file.

There are exceptions which are distributed under GPL License, Version 2.0 found in the [GPL-2.0](./LICENSES/GPL-2.0) file:
* all binaries provided in `./prebuilt/` directory
* all .patch files provided in `./source/patch/` directory
