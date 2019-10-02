#!/bin/bash
#
# Build Linux kernel

# Copyright (C)  2019. STMicroelectronics
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#######################################
# Constants
#######################################
SCRIPT_VERSION="1.1"

SOC_FAMILY="stm32mp1"
SOC_NAME="stm32mp15"
SOC_VERSION="stm32mp157c"

KERNEL_VERSION=4.19
KERNEL_ARCH=arm
KERNEL_TOOLCHAIN=gcc-arm-8.2-2019.01-x86_64-arm-eabi

if [ -n "${ANDROID_BUILD_TOP+1}" ]; then
  TOP_PATH=${ANDROID_BUILD_TOP}
elif [ -d "device/stm/${SOC_FAMILY}-kernel" ]; then
  TOP_PATH=$PWD
else
  echo "ERROR: ANDROID_BUILD_TOP env variable not defined, this script shall be executed on TOP directory"
  exit 1
fi

\pushd ${TOP_PATH} >/dev/null 2>&1

KERNEL_BUILDCONFIG=android_kernelbuild.config

KERNEL_SOURCE_PATH=${TOP_PATH}/device/stm/${SOC_FAMILY}-kernel/source
KERNEL_PREBUILT_PATH=${TOP_PATH}/device/stm/${SOC_FAMILY}-kernel/prebuilt

KERNEL_MERGE_CONFIG=mergeconfig.sh
KERNEL_ANDROID_BASE_CONFIG=android-base.config
KERNEL_ANDROID_RECOMMENDED_CONFIG=android-recommended.config
KERNEL_ANDROID_SOC_CONFIG=android-soc.config

KERNEL_CROSS_COMPILE_PATH=${TOP_PATH}/prebuilts/gcc/linux-x86/arm/${KERNEL_TOOLCHAIN}/bin
KERNEL_CROSS_COMPILE=arm-eabi-

KERNEL_OUT=${TOP_PATH}/out-bsp/${SOC_FAMILY}/KERNEL_OBJ

# Board name and flavour shall be listed in associated order
BOARD_NAME_LIST=( "eval" )
BOARD_FLAVOUR_LIST=( "ev1" )

#######################################
# Variables
#######################################
nb_states=0

cmd_cnt=0
cmd_req=

do_install=0
do_onlymenuconfig=0
do_onlydefaultconfig=0
do_onlymrproper=0
do_onlydtb=0
do_onlygpu=0
do_onlymodules=0
do_onlyvmlinux=0
do_full=0
do_strip=1

execute_more=1

kernel_src=

kernel_defconfig=
kernel_cleanup_fragment=
kernel_addon_fragment=

kernel_gpu_name=
kernel_gpu_path=

dtc_flags=

force=

verbose="--quiet"
verbose_level=0

# By default redirect stdout and stderr to /dev/null
redirect_out="/dev/null"

#######################################
# Functions
#######################################

#######################################
# Add empty line in stdout
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
empty_line()
{
  echo
}

#######################################
# Print script usage on stdout
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
usage()
{
  echo "Usage: `basename $0` [Options] [Command]"
  empty_line
  echo "  This script allows building the Linux kernel source"
  empty_line
  echo "Options:"
  echo "  -h/--help: print this message"
  echo "  -i/--install: update prebuilt images"
  echo "  -v/--version: get script version"
  echo "  -ns/--nostrip: do not strip generated modules (default: strip enabled = remove unneeded symbols)"
  echo "  --verbose <level>: enable verbosity (1 or 2 depending on level of verbosity required)"
  echo "Command: only one command at a time supported"
  echo "  dtb: build only device-tree binaries"
  echo "  gpu: build only gpu module (kernel is build if not already performed)"
  echo "  defaultconfig: build only .config based on default defconfig files and fragments"
  echo "  menuconfig: display standard Linux kernel menuconfig interface"
  echo "  modules: build only kernel modules binaries (kernel is build if not already performed)"
  echo "  mrproper: execute make mrproper on targeted kernel"
  echo "  vmlinux: build only kernel vmlinux binary"
  empty_line
}

#######################################
# Print error message in red on stderr
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
error()
{
  echo "$(tput setaf 1)ERROR: $1$(tput sgr0)" >&2
}

#######################################
# Print warning message in orange on stdout
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
warning()
{
  echo "$(tput setaf 3)WARNING: $1$(tput sgr0)"
}

#######################################
# Print message in blue on stdout
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
blue()
{
  echo "$(tput setaf 6)$1$(tput sgr0)"
}

#######################################
# Print message in green on stdout
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
green()
{
  echo "$(tput setaf 2)$1$(tput sgr0)"
}

#######################################
# Clear current line in stdout
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
clear_line()
{
  echo -ne "\033[2K"
}

#######################################
# Print state message on stdout
# Globals:
#   I nb_states
#   I/O action_state
# Arguments:
#   None
# Returns:
#   None
#######################################
action_state=1
state()
{
  clear_line
  blue "  [${action_state}/${nb_states}]: $1"
  action_state=$((action_state+1))
}

#######################################
# Check if item is available in list
# Globals:
#   None
# Arguments:
#   $1 = list of possible items
#   $2 = item which shall be tested
# Returns:
#   0 if item found in list
#   1 if item not found in list
#######################################
in_list()
{
  local list="$1"
  local checked_item="$2"

  for item in ${list}
  do
    if [[ "$item" == "$checked_item" ]]; then
      return 0
    fi
  done

  return 1
}

#######################################
# Return $execute value to check if next action must be done
# Globals:
#   I execute_more
# Arguments:
#   None
# Returns:
#   $execute_more
#######################################
do_execute()
{
  return ${execute_more}
}

#######################################
# Extract Kernel build config
# Globals:
#   I KERNEL_SOURCE_PATH
#   I KERNEL_BUILDCONFIG
#   O kernel_src
#   O kernel_defconfig
#   O kernel_cleanup_fragment
#   O kernel_addon_fragment
#   O kernel_gpu_name
#   O kernel_gpu_src
# Arguments:
#   None
# Returns:
#   None
#######################################
extract_buildconfig()
{
  local l_kernel_value
  local l_line
  local l_src

  while IFS='' read -r l_line || [[ -n $l_line ]]; do
    echo $l_line | grep '^KERNEL_'  >/dev/null 2>&1

    if [ $? -eq 0 ]; then
      l_line=$(echo "${l_line: 7}")
      l_kernel_value=($(echo $l_line | awk '{ print $1 }'))

      case ${l_kernel_value} in
      "SRC" )
        l_src=($(echo $l_line | awk '{ print $2 }'))
        kernel_src=($(realpath ${l_src}))
        ;;
      "DEFCONFIG" )
        kernel_defconfig=($(echo $l_line | awk '{ print $2 }'))
        ;;
      "CLEANUP_FRAGMENT" )
        kernel_cleanup_fragment=($(echo $l_line | awk '{ print $2 }'))
        ;;
      "ADDONS_FRAGMENT" )
        kernel_addon_fragment=($(echo $l_line | awk '{ print $2 }'))
        ;;
      "GPU_NAME" )
        kernel_gpu_name=($(echo $l_line | awk '{ print $2 }'))
        ;;
      "GPU_SRC" )
        l_src=($(echo $l_line | awk '{ print $2 }'))
        kernel_gpu_src=($(realpath ${l_src}))
        ;;
      esac
    fi
  done < ${KERNEL_SOURCE_PATH}/${KERNEL_BUILDCONFIG}
}

#######################################
# Generate config
# Globals:
#   I kernel_src
#   I kernel_defconfig
#   I kernel_cleanup_fragment
#   I kernel_addon_fragment
#   I KERNEL_VERSION
#   I KERNEL_OUT
#   I KERNEL_ARCH
#   I KERNEL_CROSS_COMPILE_PATH
#   I KERNEL_CROSS_COMPILE
#   I KERNEL_ANDROID_BASE_CONFIG
#   I KERNEL_ANDROID_RECOMMENDED_CONFIG
# Arguments:
#   None
# Returns:
#   None
#######################################
generate_config()
{
  local l_config_path

  l_config_path=${kernel_src}/arch/${KERNEL_ARCH}/configs/

  # Generate .config
  generate_kernel ${kernel_defconfig}
  if [ $? -ne 0 ]; then
    error "Not possible to generate kernel defconfig"
    popd >/dev/null 2>&1
    exit 1
  fi

  # Generate .config.required (Android required configuration = base + recommended)
  \cat ${KERNEL_SOURCE_PATH}/kconfig/${KERNEL_VERSION}/${KERNEL_ANDROID_BASE_CONFIG} ${KERNEL_SOURCE_PATH}/kconfig/${KERNEL_VERSION}/${KERNEL_ANDROID_RECOMMENDED_CONFIG} > ${KERNEL_OUT}/.config.required

  # Merge .config and .config.required with fragments and SoC configuration for Android
  ${KERNEL_SOURCE_PATH}/kconfig/${KERNEL_MERGE_CONFIG} ${kernel_src} ${KERNEL_OUT} ${KERNEL_ARCH} ${KERNEL_CROSS_COMPILE_PATH}/${KERNEL_CROSS_COMPILE} ${KERNEL_OUT}/.config ${l_config_path}/${kernel_cleanup_fragment} ${l_config_path}/${kernel_addon_fragment} ${KERNEL_SOURCE_PATH}/kconfig/${KERNEL_VERSION}/${KERNEL_ANDROID_SOC_CONFIG} ${KERNEL_OUT}/.config.required > ${KERNEL_OUT}/mergeconfig.log 2>&1
  green "  mergeconfig logs added in ${KERNEL_OUT}/mergeconfig.log"

  # Generate the corresponding defconfig file as refrence
  state "Generate corresponding defconfig.default for ${SOC_FAMILY}"
  generate_kernel savedefconfig
  mv ${KERNEL_OUT}/defconfig ${KERNEL_OUT}/defconfig.default
  
}

#######################################
# Clean Kernel out directory to force full rebuild
# Globals:
#   I KERNEL_OUT
# Arguments:
#   None
# Returns:
#   None
#######################################
clean_kernel_out()
{
  \rm -rf ${KERNEL_OUT}/*
}

#######################################
# Generate Kernel binary
# Globals:
#   I kernel_src
#   I KERNEL_OUT
#   I KERNEL_ARCH
#   I KERNEL_CROSS_COMPILE_PATH
#   I KERNEL_CROSS_COMPILE
#   I BOARD_FLAVOUR_LIST
#   I dtc_flags
#   I force
# Arguments:
#   Compilation rule:
#                  all
#                  <defconfig file name>
#                  dtb
#                  menuconfig
#                  modules
#                  mrproper
#                  savedefconfig
#                  vmlinux
#                  zImage
# Returns:
#   None
#######################################
generate_kernel()
{
  # Force alignment on page size for the geberated DTB files
  for board_flavour in "${BOARD_FLAVOUR_LIST[@]}"
  do
    dtc_flags+="DTC_FLAGS_${SOC_VERSION}-${board_flavour}=-a4096 "
  done

  \make ${verbose} -j8 -C ${kernel_src} O=${KERNEL_OUT} ARCH="${KERNEL_ARCH}" CROSS_COMPILE=${KERNEL_CROSS_COMPILE_PATH}/${KERNEL_CROSS_COMPILE} ${force} ${dtc_flags} $1 &>${redirect_out}
  if [ $? -ne 0 ]; then
    error "Not possible to generate the kernel image"
    popd >/dev/null 2>&1
    exit 1
  fi
}

#######################################
# Generate GPU driver
# Globals:
#   I kernel_gpu_name
#   I kernel_gpu_src
#   I KERNEL_OUT
#   I KERNEL_ARCH
#   I KERNEL_CROSS_COMPILE_PATH
#   I KERNEL_CROSS_COMPILE
# Arguments:
#   None
# Returns:
#   None
#######################################
generate_gpu_driver()
{
  # Copy source in temporary directory (out)
  \mkdir -p ${KERNEL_OUT}/${kernel_gpu_name}
  \find ${KERNEL_OUT}/${kernel_gpu_name} -type l -exec rm {} +
  \cp -prs ${kernel_gpu_src}/* ${KERNEL_OUT}/${kernel_gpu_name}
  # Build GPU driver
  \make ${verbose} -C ${KERNEL_OUT}/${kernel_gpu_name} O=${KERNEL_OUT} KERNEL_DIR=${KERNEL_OUT} CROSS_COMPILE=${KERNEL_CROSS_COMPILE_PATH}/${KERNEL_CROSS_COMPILE} ARCH_TYPE=${KERNEL_ARCH} all SOC_PLATFORM=st-st &>${redirect_out}
  if [ $? -ne 0 ]; then
    error "Not possible to generate gpu driver module"
    popd >/dev/null 2>&1
    exit 1
  fi
}

#######################################
# Main
#######################################

# Check that the current script is not sourced
if [[ "$0" != "$BASH_SOURCE" ]]; then
  empty_line
  error "This script shall not be sourced"
  empty_line
  usage
  \popd >/dev/null 2>&1
  return
fi

# Check the current usage
if [ $# -gt 4 ]
then
  usage
  popd >/dev/null 2>&1
  exit 0
fi

while test "$1" != ""; do
  arg=$1
  case $arg in
    "-h"|"--help" )
      usage
      popd >/dev/null 2>&1
      exit 0
      ;;

    "-v"|"--version" )
      echo "`basename $0` version ${SCRIPT_VERSION}"
      \popd >/dev/null 2>&1
      exit 0
      ;;

    "--verbose" )
      verbose_level=${2}
      redirect_out="/dev/stdout"
      if ! in_list "0 1 2" "${verbose_level}"; then
        error "unknown verbose level ${verbose_level}"
        \popd >/dev/null 2>&1
        exit 1
      fi
      if [ ${verbose_level} == 2 ];then
        verbose=
      fi
      shift
      ;;

    "-i"|"--install" )
      nb_states=$((nb_states+1))
      do_install=1
      ;;

    "-ns"|"--nostrip" )
      do_strip=0
      ;;

    "dtb" )
      nb_states=$((nb_states+3))
      do_onlydtb=1
      cmd_cnt=$((cmd_cnt+1))
      cmd_req+="${arg} "
      ;;

    "gpu" )
      nb_states=$((nb_states+5))
      do_onlygpu=1
      cmd_cnt=$((cmd_cnt+1))
      cmd_req+="${arg} "
      ;;

    "defaultconfig" )
      nb_states=$((nb_states+2))
      do_onlydefaultconfig=1
      force="-B"
      cmd_cnt=$((cmd_cnt+1))
      cmd_req+="${arg} "
      ;;

    "menuconfig" )
      nb_states=$((nb_states+3))
      do_onlymenuconfig=1
      cmd_cnt=$((cmd_cnt+1))
      cmd_req+="${arg} "
      ;;

    "modules" )
      nb_states=$((nb_states+5))
      do_onlymodules=1
      cmd_cnt=$((cmd_cnt+1))
      cmd_req+="${arg} "
      ;;

    "mrproper" )
      nb_states=$((nb_states+1))
      do_onlymrproper=1
      cmd_cnt=$((cmd_cnt+1))
      cmd_req+="${arg} "
      ;;

    "vmlinux" )
      nb_states=$((nb_states+4))
      do_onlyvmlinux=1
      cmd_cnt=$((cmd_cnt+1))
      cmd_req+="${arg} "
      ;;

    ** )
      usage
      popd >/dev/null 2>&1
      exit 0
      ;;
  esac
  shift
done

# Check that only one command is requested
if [[ ${cmd_cnt} > 1 ]]; then
  error "Only one command resquest support. Current commands are : ${cmd_req}!"
  popd >/dev/null 2>&1
  exit 1
fi

# In case of full compilation is requested, set nb_states
if [[ ${cmd_cnt} == 0 ]]; then
  nb_states=7
  if [[ ${do_install} == 1 ]]; then
    nb_states=$((nb_states+1))
  fi
  do_full=1
fi

# Check existence of the KERNEL build configuration file
if [[ ! -f ${KERNEL_SOURCE_PATH}/${KERNEL_BUILDCONFIG} ]]; then
  error "Kernel configuration ${KERNEL_BUILDCONFIG} file not available"
  popd >/dev/null 2>&1
  exit 1
fi

if [[ ! -d ${KERNEL_CROSS_COMPILE_PATH} ]]; then
  error "Required toolchain ${KERNEL_TOOLCHAIN} not available, please execute bspsetup"
  popd >/dev/null 2>&1
  exit 1
fi

# Extract Kernel build configuration
extract_buildconfig

# Check existence of the kernel source
if [[ ! -f ${kernel_src}/Makefile ]]; then
  error "Kernel source ${kernel_src} not available, please execute load_kernel first"
  popd >/dev/null 2>&1
  exit 1
fi

# Create Kernel out directory
\mkdir -p ${KERNEL_OUT}

# Execute mrproper command if requested, then exit
if [[ ${do_onlymrproper} == 1 ]]; then
  state "Delete the current configuration, and all generated files for ${SOC_FAMILY}"
  generate_kernel mrproper
  popd >/dev/null 2>&1
  exit 0
fi

# Adapt value of nb_states following curent conditions
# Remove 2 states when .config is present and do not request to regenerate it
if [[ -f ${KERNEL_OUT}/.config ]] && [[ ${do_onlydefaultconfig} == 0 ]]; then
  nb_states=$((nb_states-2))
fi
# Remove 2 states when zImage is present and do not request to regenerate it
if [[ -f ${KERNEL_OUT}/arch/${KERNEL_ARCH}/boot/zImage ]] && [[ ${do_full} == 0 ]] && [[ ${do_onlyvmlinux} == 0 ]] && [[ ${do_onlymenuconfig} == 0 ]] && [[ ${do_onlydefaultconfig} == 0 ]]; then
  nb_states=$((nb_states-2))
fi

# Generate .config if needed or if requested
if [[ ! -f ${KERNEL_OUT}/.config ]] || [[ ${do_onlydefaultconfig} == 1 ]]; then
  state "Generate .config for ${SOC_FAMILY}"
  generate_config
  
  if [[ ${do_onlydefaultconfig} == 1 ]]; then
    popd >/dev/null 2>&1
    exit 0
  fi
fi

# Execute menuconfig command if requested, then exist
if [[ ${do_onlymenuconfig} == 1 ]]; then
  state "Start menuconfig panel for ${SOC_FAMILY}"
  # need to force redirection to stdout for menuconfig
  redirect_out="/dev/stdout"
  generate_kernel menuconfig
  if [ ${verbose_level} > 0 ];then
    redirect_out="/dev/null"
  fi
  generate_kernel savedefconfig
  popd >/dev/null 2>&1
  exit 0
fi

# Generate dtb files. If only dtb command requested, then go to install if needed
if [[ ${do_onlymodules} == 0 ]] && [[ ${do_onlyvmlinux} == 0 ]] && [[ ${do_onlygpu} == 0 ]]; then

  state "Generate dtb binaries"
  generate_kernel dtbs
  if [[ ${do_onlydtb} == 1 ]]; then
    execute_more=0
  fi

fi

# Build Kernel if required. If only vmlinux command requested, then go to install if needed
do_execute || {

  if [[ ! -f ${KERNEL_OUT}/arch/${KERNEL_ARCH}/boot/zImage ]] || ([[ ${do_onlymodules} == 0 ]] && [[ ${do_onlygpu} == 0 ]]); then

    state "Generate vmlinux for ${SOC_FAMILY}"
    generate_kernel vmlinux
    state "Generate zImage for ${SOC_FAMILY}"
    generate_kernel zImage
    if [[ ${do_onlyvmlinux} == 1 ]]; then
      execute_more=0
    fi

  fi
}

# Build Kernel if required. If only modules command requested, then go to install if needed
do_execute || {

  if [[ ${do_onlygpu} == 0 ]]; then
    state "Generate modules for ${SOC_FAMILY}"
    generate_kernel modules
    if [[ ${do_onlymodules} == 1 ]]; then
      execute_more=0
    fi
  fi

}

# Generate gpu driver. If only gpu command requested, then go to install if needed
do_execute || {

  state "Generate GPU driver module for ${SOC_FAMILY}"
  generate_gpu_driver

}

# Copy generated images in kernel prebuilt directory if requested
if [[ ${do_install} == 1 ]]; then

  state "Update prebuilt images"
  if [[ ${do_onlygpu} == 0 ]]; then
    for board_flavour in "${BOARD_FLAVOUR_LIST[@]}"
    do
      \find ${KERNEL_OUT}/ -name "${SOC_VERSION}-${board_flavour}.dtb" -print0 | xargs -0 -I {} cp {} ${KERNEL_PREBUILT_PATH}/dts/
    done
    \find ${KERNEL_OUT}/ -name "*.ko" -print0 | xargs -0 -I {} cp {} ${KERNEL_PREBUILT_PATH}/modules/
    if [[ ${do_strip} == 1 ]]; then
      ${KERNEL_CROSS_COMPILE_PATH}/${KERNEL_CROSS_COMPILE}strip  --strip-debug  ${KERNEL_PREBUILT_PATH}/modules/*.ko
    fi
    \find ${KERNEL_OUT}/ -name "zImage" -print0 | xargs -0 -I {} cp {} ${KERNEL_PREBUILT_PATH}/kernel-${SOC_VERSION}
    \cp ${KERNEL_OUT}/vmlinux ${KERNEL_PREBUILT_PATH}/vmlinux-${SOC_VERSION}
  else
    \find ${KERNEL_OUT}/ -name "galcore.ko" -print0 | xargs -0 -I {} cp {} ${KERNEL_PREBUILT_PATH}/modules/
    if [[ ${do_strip} == 1 ]]; then
      ${KERNEL_CROSS_COMPILE_PATH}/${KERNEL_CROSS_COMPILE}strip  --strip-debug  ${KERNEL_PREBUILT_PATH}/modules/galcore.ko
    fi
  fi

fi

popd >/dev/null 2>&1
