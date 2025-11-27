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
SCRIPT_VERSION="1.8"

SOC_FAMILY="stm32mp2"
SOC_NAME="stm32mp25"
SOC_VERSIONS=( "stm32mp257f" )

KERNEL_VERSION=6.1
KERNEL_ARCH=arm64

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

LLVM_OPTION="LLVM=1 LLVM_IAS=1"
LLVM_TOOLCHAIN=llvm-

KERNEL_OUT=${TOP_PATH}/out-bsp/${SOC_FAMILY}/KERNEL_OBJ

# Board name and flavour shall be listed in associated order
BOARD_NAME_LIST=( "eval" "dk" )
BOARD_FLAVOUR_LIST=( "ev1" "dk" )

#######################################
# Variables
#######################################
nb_states=0

do_install=0
do_onlymenuconfig=0
do_onlydefaultconfig=0
do_onlymrproper=0
do_onlydtb=0
do_onlygpu=0
do_onlywifi=0
do_onlymodules=0
do_onlyvmlinux=0
do_full=0
do_gdb=0
do_kdebug=0
force_mrproper=0
force_defaultconfig=0

do_debug=0

execute_more=1

kernel_src=
modulesinstall_param=

kernel_defconfig=
kernel_soc_fragment=
kernel_debug_fragment=
kernel_user_fragment=
kernel_board_fragment=

kernel_gpu_name=
kernel_gpu_src=

kernel_wifi_name=
kernel_wifi_src=

modules_install_path=
gpu_module_install_path=

dtc_flags=

force=

verbose="--quiet"

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
  echo "  -h/--help: print this message and exit"
  echo "  -v/--version: print script version and exit"
  echo "  -i/--install: update prebuilt images"
  echo "  -d/--debug: enable script debug traces"
  echo "  -g/--gdb: generate vmlinux (kernel incl. symbols) and don't strip generated modules (keep symbols)"
  echo "  --verbose: enable verbosity"
  echo "Command: only one command at a time supported"
  echo "  dtb: build only device-tree binaries"
  echo "  gpu: build only gpu module (kernel is build if not already performed)"
  echo "  defaultconfig: build only .config based on default defconfig files and fragments"
  echo "  menuconfig: display standard Linux kernel menuconfig interface"
  echo "  modules: build kernel modules and sign (kernel is built if not already performed)"
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
# Print debug message in green
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
debug()
{
  if [[ ${do_debug} == 1 ]]; then
    echo "$(tput setaf 2)DEBUG: $1$(tput sgr0)"
  fi
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
#   O kernel_debug_fragment
#   O kernel_user_fragment
#   O kernel_soc_fragment
#   O kernel_board_fragment
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
      "DEBUG_FRAGMENT" )
        kernel_debug_fragment=($(echo $l_line | awk '{ print $2 }'))
        ;;
      "USER_FRAGMENT" )
        kernel_user_fragment=($(echo $l_line | awk '{ print $2 }'))
        ;;
      "SOC_FRAGMENT" )
        kernel_soc_fragment=($(echo $l_line | awk '{ print $2 }'))
        ;;
      "BOARD_FRAGMENT" )
        kernel_board_fragment=($(echo $l_line | awk '{ print $2 }'))
        ;;
      "GPU_NAME" )
        kernel_gpu_name=($(echo $l_line | awk '{ print $2 }'))
        ;;
      "GPU_SRC" )
        l_src=($(echo $l_line | awk '{ print $2 }'))
        kernel_gpu_src=($(realpath ${l_src}))
        ;;
      "WIFI_NAME" )
        l_src=($(echo $l_line | awk '{ print $2 }'))
        kernel_wifi_name=($(realpath ${l_src}))
        ;;
      "WIFI_SRC" )
        l_src=($(echo $l_line | awk '{ print $2 }'))
        kernel_wifi_src=($(realpath ${l_src}))
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
#   I kernel_debug_fragment
#   I kernel_user_fragment
#   I kernel_soc_fragment
#   I kernel_board_fragment
#   I KERNEL_SOURCE_PATH
#   I KERNEL_VERSION
#   I KERNEL_OUT
#   I KERNEL_ARCH
# Arguments:
#   None
# Returns:
#   None
#######################################
generate_config()
{
  local l_config_path

  l_config_path=${KERNEL_SOURCE_PATH}/kconfig/${KERNEL_VERSION}

  # Generate .config
  generate_kernel ${kernel_defconfig}
  if [ $? -ne 0 ]; then
    error "Not possible to generate kernel defconfig"
    popd >/dev/null 2>&1
    exit 1
  fi

    # Merge .config and .config.required with fragments and SoC configuration for Android
    if [[ ${do_kdebug} == 1 ]]; then
      ${KERNEL_SOURCE_PATH}/kconfig/${KERNEL_MERGE_CONFIG} ${kernel_src} ${KERNEL_OUT} ${KERNEL_ARCH} ${KERNEL_OUT}/.config ${l_config_path}/${kernel_soc_fragment} ${l_config_path}/${kernel_debug_fragment} ${l_config_path}/${kernel_board_fragment} > ${KERNEL_OUT}/mergeconfig.log 2>&1
    else
      ${KERNEL_SOURCE_PATH}/kconfig/${KERNEL_MERGE_CONFIG} ${kernel_src} ${KERNEL_OUT} ${KERNEL_ARCH} ${KERNEL_OUT}/.config ${l_config_path}/${kernel_soc_fragment} ${l_config_path}/${kernel_user_fragment} ${l_config_path}/${kernel_board_fragment} > ${KERNEL_OUT}/mergeconfig.log 2>&1
    fi

  green "  => mergeconfig logs added in ${KERNEL_OUT}/mergeconfig.log"

  # Generate the corresponding defconfig file as refrence
  state "Generate corresponding defconfig.default for ${SOC_FAMILY}"
  generate_kernel savedefconfig
  mv ${KERNEL_OUT}/defconfig ${KERNEL_OUT}/defconfig.default

  if [[ ${do_kdebug} == 1 ]]; then
    echo "DEBUG ENABLED" > ${KERNEL_OUT}/build.config
  else
    echo "DEBUG DISABLED" > ${KERNEL_OUT}/build.config
  fi
}

#######################################
# Check last build config
# Globals:
#   I KERNEL_OUT
#   I do_kdebug
#   O force_mrproper
#   O force_defaultconfig
# Arguments:
#   None
# Returns:
#   None
#######################################
check_buildconfig()
{
  force_mrproper=0
  force_defaultconfig=0
  if [[ -f $KERNEL_OUT/build.config ]]; then
    build_config=`grep "DEBUG" $KERNEL_OUT/build.config`
    if [[ ${build_config} =~ "ENABLED" ]] && [[ ${do_kdebug} == 0 ]]; then
      force_mrproper=1
      force_defaultconfig=1
    elif [[ ${build_config} =~ "DISABLED" ]] && [[ ${do_kdebug} == 1 ]]; then
      force_mrproper=1
      force_defaultconfig=1
    fi
  else
    # unclear status, clean in case
    force_mrproper=1
    force_defaultconfig=1
  fi
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
# Extract install path
# Globals:
#   I tmp_file (temporary file out of modules_install build)
# Arguments:
#   None
# Returns:
#   None
#######################################
extract_install_path()
{
  if [[ -f $1 ]]; then
    install_path=$(grep "DEPMOD" "$1" | tail -n 1 | awk '{print $2}')
  fi
}

#######################################
# Generate Kernel binary
# Globals:
#   I kernel_src
#   I KERNEL_OUT
#   I KERNEL_ARCH
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
#                  Image
# Returns:
#   None
#######################################
generate_kernel()
{
  # Force alignment on page size for the generated DTB files
  dtc_flags=""
  for soc_version in "${SOC_VERSIONS[@]}"
  do
    for board_flavour in "${BOARD_FLAVOUR_LIST[@]}"
    do
      dtc_flags+="DTC_FLAGS_${soc_version}-${board_flavour}=-a4096 "
    done
  done

  tmp_out=$(mktemp)

  if [[ "$1" == "modules_install" ]]; then
    modulesinstall_param="INSTALL_MOD_PATH=${KERNEL_OUT}"

    debug "make -j8 -C ${kernel_src} O=${KERNEL_OUT} ${LLVM_OPTION} ${modulesinstall_param} ARCH=${KERNEL_ARCH} ${force} ${dtc_flags} $1"
    \make -j8 -C ${kernel_src} O=${KERNEL_OUT} ${LLVM_OPTION} ${modulesinstall_param} ARCH=${KERNEL_ARCH} ${force} ${dtc_flags} $1 > ${tmp_out}
  if [ $? -ne 0 ]; then
      cat ${tmp_out}
    error "Not possible to generate the kernel image"
    popd >/dev/null 2>&1
    exit 1
  fi
    \cat ${tmp_out} &>${redirect_out}
    if [[ "$1" == "modules_install" ]]; then
      extract_install_path ${tmp_out}
      modules_install_path=${install_path}
    fi
    rm ${tmp_out}

  else

    if [[ "$1" == "dtbs" ]]; then
      ext_dt_param="KBUILD_EXTDTS=${kernel_ext_dt}/linux"
    else
      ext_dt_param=""
    fi

    debug "make -j8 -C ${kernel_src} O=${KERNEL_OUT} ${LLVM_OPTION} ${ext_dt_param} ARCH=${KERNEL_ARCH} ${force} ${dtc_flags} $1"
    \make -j8 -C ${kernel_src} O=${KERNEL_OUT} ${LLVM_OPTION} ${ext_dt_param} ARCH=${KERNEL_ARCH} ${force} ${dtc_flags} $1 &>${redirect_out}
    if [ $? -ne 0 ]; then
      error "Not possible to generate the kernel image"
      popd >/dev/null 2>&1
      exit 1
    fi

  fi

}

#######################################
# Generate GPU driver
# Globals:
#   I kernel_gpu_name
#   I kernel_gpu_src
#   I KERNEL_OUT
#   I KERNEL_ARCH
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
  # Build GPU driver (add DEBUG=1 if debug required)
  debug "make ${verbose} -C ${KERNEL_OUT}/${kernel_gpu_name} O=${KERNEL_OUT} ${LLVM_OPTION} CROSS_COMPILE=aarch64-none-linux-gnu- KERNEL_DIR=${KERNEL_OUT} ARCH_TYPE=${KERNEL_ARCH} all SOC_PLATFORM=st-mp2 VIVANTE_ENABLE_DRM=1"
  \make ${verbose} -C ${KERNEL_OUT}/${kernel_gpu_name} O=${KERNEL_OUT} ${LLVM_OPTION} CROSS_COMPILE=aarch64-none-linux-gnu- KERNEL_DIR=${KERNEL_OUT} ARCH_TYPE=${KERNEL_ARCH} all SOC_PLATFORM=st-mp2 VIVANTE_ENABLE_DRM=1 &>${redirect_out}
  if [ $? -ne 0 ]; then
    error "Not possible to generate gpu driver module"
    popd >/dev/null 2>&1
    exit 1
  fi
}

#######################################
# Install GPU driver
# Globals:
#   I kernel_gpu_name
#   I kernel_gpu_src
#   I KERNEL_OUT
#   I KERNEL_ARCH
# Arguments:
#   None
# Returns:
#   None
#######################################
install_gpu_driver()
{

  tmp_out=$(mktemp)
  modulesinstall_param="INSTALL_MOD_PATH=${KERNEL_OUT}"
  # Build GPU driver (add DEBUG=1 if debug required)
  debug "make -j8 -C ${kernel_src} O=${KERNEL_OUT} M=${KERNEL_OUT}/${kernel_gpu_name} ${modulesinstall_param} ${LLVM_OPTION} CROSS_COMPILE=aarch64-none-linux-gnu- KERNEL_DIR=${KERNEL_OUT} ARCH_TYPE=${KERNEL_ARCH} SOC_PLATFORM=st-mp2 VIVANTE_ENABLE_DRM=1 modules_install"
  \make -j8 -C ${kernel_src} O=${KERNEL_OUT} M=${KERNEL_OUT}/${kernel_gpu_name} ${modulesinstall_param} ${LLVM_OPTION} CROSS_COMPILE=aarch64-none-linux-gnu- KERNEL_DIR=${KERNEL_OUT} ARCH_TYPE=${KERNEL_ARCH} SOC_PLATFORM=st-mp2 VIVANTE_ENABLE_DRM=1 modules_install > ${tmp_out}
  if [ $? -ne 0 ]; then
    error "Not possible to install gpu driver module"
    popd >/dev/null 2>&1
    exit 1
  fi
  \cat ${tmp_out} &>${redirect_out}
  extract_install_path ${tmp_out}
  gpu_module_install_path=${install_path}
  rm ${tmp_out}
}



#######################################
# Generate WIFI driver
# Globals:
#   I kernel_wifi_name
#   I kernel_wifi_src
#   I KERNEL_OUT
#   I KERNEL_ARCH
# Arguments:
#   None
# Returns:
#   None
#######################################
generate_wifi_driver()
{
  # Copy source in temporary directory (out)
  \mkdir -p ${KERNEL_OUT}/${kernel_wifi_name}
  \find ${KERNEL_OUT}/${kernel_wifi_name} -type l -exec rm {} +
  \cp -prs ${kernel_wifi_src}/* ${KERNEL_OUT}/${kernel_wifi_name}
  # Build WIFI driver
  debug "make ${verbose} -C ${KERNEL_OUT}/${kernel_wifi_name} O=${KERNEL_OUT} KSRC=${KERNEL_OUT} ${LLVM_OPTION} ARCH=${KERNEL_ARCH}"
  \make ${verbose} -C ${KERNEL_OUT}/${kernel_wifi_name} O=${KERNEL_OUT} KSRC=${KERNEL_OUT} ${LLVM_OPTION} ARCH=${KERNEL_ARCH} &>${redirect_out}
  if [ $? -ne 0 ]; then
    error "Not possible to generate wifi driver module"
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

# force debug option by default if userdebug or eng build
if [ -n "${TARGET_BUILD_VARIANT+1}" ]; then
  if [ "${TARGET_BUILD_VARIANT}" == "user" ]; then
    do_kdebug=0
  else
    do_kdebug=1
  fi
fi

# check the options
while getopts "hvidg-:" option; do
    case "${option}" in
        -)
            # Treat long options
            case "${OPTARG}" in
                help)
                    usage
                    popd >/dev/null 2>&1
                    exit 0
                    ;;
                version)
                    echo "`basename $0` version ${SCRIPT_VERSION}"
                    \popd >/dev/null 2>&1
                    exit 0
                    ;;
                verbose)
                    redirect_out="/dev/stdout"
                        verbose=
                    ;;
                install)
                    if [[ ${do_install} == 0 ]]; then
                      nb_states=$((nb_states+1))
                    fi
                    do_install=1
                    ;;
                debug)
                      do_debug=1
                    ;;
                gdb)
                    do_gdb=1
                    ;;
                *)
                    usage
                    popd >/dev/null 2>&1
                    exit 1
                    ;;
            esac;;
        # Treat short options
        h)
            usage
            popd >/dev/null 2>&1
            exit 0
            ;;
        v)
            echo "`basename $0` version ${SCRIPT_VERSION}"
            \popd >/dev/null 2>&1
            exit 0
            ;;
        i)
            if [[ ${do_install} == 0 ]]; then
                nb_states=$((nb_states+1))
            fi
            do_install=1
            ;;
        d)
              do_debug=1
            ;;
        g)
            do_gdb=1
            ;;
        *)
            usage
            popd >/dev/null 2>&1
            exit 1
            ;;
    esac
done

shift $((OPTIND-1))

if [ $# -gt 1 ]; then
  error "Only one command resquest support. Current commands are : $*"
  popd >/dev/null 2>&1
  exit 1
fi

# check the options
if [ $# -eq 1 ]; then
  case $1 in
    "dtb" )
      nb_states=$((nb_states+5))
      do_onlydtb=1
      ;;

    "gpu" )
      nb_states=$((nb_states+6))
      do_onlygpu=1
      ;;

    "wifi" )
      nb_states=$((nb_states+6))
      do_onlywifi=1
      ;;

    "defaultconfig" )
      nb_states=$((nb_states+2))
      do_onlydefaultconfig=1
      force="-B"
      ;;

    "menuconfig" )
      nb_states=$((nb_states+3))
      do_onlymenuconfig=1
      ;;

    "modules" )
      nb_states=$((nb_states+6))
      do_onlymodules=1
      ;;

    "mrproper" )
      nb_states=$((nb_states+1))
      do_onlymrproper=1
      ;;

    "vmlinux" )
      nb_states=$((nb_states+4))
      do_onlyvmlinux=1
      ;;

    ** )
      usage
      popd >/dev/null 2>&1
      exit 0
      ;;
  esac
else
  # case all
  nb_states=10
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

# Extract Kernel build configuration
extract_buildconfig

# Check existence of the kernel source
if [[ ! -f ${kernel_src}/Makefile ]]; then
  error "Kernel source ${kernel_src} not available, please execute load_kernel first"
  popd >/dev/null 2>&1
  exit 1
fi

# Create Kernel out directory if needed
if [ ! -d "${KERNEL_OUT}" ]; then
  \mkdir -p ${KERNEL_OUT}
fi

# Execute mrproper command if requested, then exit
if [[ ${do_onlymrproper} == 1 ]] || [[ ${force_mrproper} == 1 ]]; then
  state "Delete the current configuration, and all generated files for ${SOC_FAMILY}"
  generate_kernel mrproper
  rm -f ${KERNEL_OUT}/build.config
  popd >/dev/null 2>&1
  exit 0
fi

# Adapt value of nb_states following curent conditions
# Remove 1 state if WIFI driver source not defined (bypass)
if [[ ! -n "${kernel_wifi_src}" ]] && [[ ${do_full} == 1 ]]; then
  nb_states=$((nb_states-1))
fi
# Remove 1 state if GPU driver source not defined (bypass)
if  [[ ! -n "${kernel_gpu_src}" ]] && [[ ${do_full} == 1 ]]; then
  nb_states=$((nb_states-1))
fi
# Remove 2 states when .config is present and do not request to regenerate it
if [[ -f ${KERNEL_OUT}/.config ]]; then
  check_buildconfig
  if [[ ${do_onlydefaultconfig} == 0 ]] && [[ ${force_defaultconfig} == 0 ]]; then
    nb_states=$((nb_states-2))
  fi
fi
# Remove 2 states when Image is present and do not request to regenerate it
if [[ -f ${KERNEL_OUT}/arch/${KERNEL_ARCH}/boot/Image ]] && [[ ${do_full} == 0 ]] && [[ ${do_onlyvmlinux} == 0 ]] && [[ ${do_onlymenuconfig} == 0 ]] && [[ ${do_onlydefaultconfig} == 0 ]]; then
  nb_states=$((nb_states-2))
fi

# Generate .config if needed or if requested
if [[ ! -f ${KERNEL_OUT}/.config ]] || [[ ${do_onlydefaultconfig} == 1 ]] || [[ ${force_defaultconfig} == 1 ]]; then
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
  store_redirect_out=${redirect_out}
  redirect_out="/dev/stdout"
  generate_kernel menuconfig
  redirect_out=${store_redirect_out}

  generate_kernel savedefconfig
  popd >/dev/null 2>&1
  exit 0
fi

# Generate dtb files. If only dtb command requested, then go to install if needed
if [[ ${do_onlymodules} == 0 ]] && [[ ${do_onlyvmlinux} == 0 ]] && [[ ${do_onlygpu} == 0 ]] && [[ ${do_onlywifi} == 0 ]]; then

  state "Generate dtb binaries"
  generate_kernel dtbs
  if [[ ${do_onlydtb} == 1 ]]; then
    execute_more=0
  fi

fi

# Build Kernel if required. If only vmlinux command requested, then go to install if needed
do_execute || {

  if [[ ! -f ${KERNEL_OUT}/arch/${KERNEL_ARCH}/boot/Image ]] || ([[ ${do_onlymodules} == 0 ]] && [[ ${do_onlygpu} == 0 ]]  && [[ ${do_onlywifi} == 0 ]]); then

    state "Generate vmlinux for ${SOC_FAMILY}"
    generate_kernel vmlinux
    state "Generate Image for ${SOC_FAMILY}"
    generate_kernel Image
    if [[ ${do_onlyvmlinux} == 1 ]]; then
      execute_more=0
    fi

  fi
}

# Build Kernel if required. If only modules command requested, then go to install if needed
do_execute || {

  if [[ ${do_onlygpu} == 0 ]] && [[ ${do_onlywifi} == 0 ]]; then
    state "Generate modules for ${SOC_FAMILY}"
    generate_kernel modules

    state "Sign modules for ${SOC_FAMILY}"
      generate_kernel modules_install

    # need to execute external modules also (keep execute_more enabled)

  fi

}

# Generate wifi driver. If only wifi command requested, then go to install if needed
do_execute || {
  if [[ ${do_onlygpu} == 0 ]]; then
    if [ -n "${kernel_wifi_src}" ] && [ -n "${kernel_wifi_name}" ]; then
      state "Generate WIFI driver module for ${SOC_FAMILY}"
      if  [ -d "${kernel_wifi_src}" ]; then
        generate_wifi_driver
      else
        warning "${kernel_wifi_src} directory not found, can't generate Wi-Fi module"
      fi
    fi
    if [[ ${do_onlywifi} == 1 ]]; then
      execute_more=0
    fi
  fi
}

# Generate gpu driver. If only gpu command requested, then go to install if needed
do_execute || {
  if [ -n "${kernel_gpu_src}" ] && [ -n "${kernel_gpu_name}" ]; then
    state "Generate GPU driver module for ${SOC_FAMILY}"
    if  [ -d "${kernel_gpu_src}" ]; then
      generate_gpu_driver

      state "Sign GPU driver module for ${SOC_FAMILY}"
      install_gpu_driver
    else
      warning "${kernel_gpu_src} directory not found, can't generate GPU module"
    fi
  fi
}

# Copy generated images in kernel prebuilt directory if requested
if [[ ${do_install} == 1 ]]; then

  # create prebuilt directories if required
  if  [ ! -d "${KERNEL_PREBUILT_PATH}/dts/" ]; then
    \mkdir -p ${KERNEL_PREBUILT_PATH}/dts/
  fi
  if  [ ! -d "${KERNEL_PREBUILT_PATH}/modules/" ]; then
    \mkdir -p ${KERNEL_PREBUILT_PATH}/modules/
  fi

  state "Update prebuilt images"
  if [[ ${do_onlygpu} == 0 ]] && [[ ${do_onlywifi} == 0 ]]; then
    # clean prebuilt directories

    if [[ ${do_onlymodules} == 0 ]] &&  [[ ${do_onlyvmlinux} == 0 ]]; then
      for soc_version in "${SOC_VERSIONS[@]}"
      do
        if  [ ! -d "${KERNEL_PREBUILT_PATH}/dts/${soc_version}" ]; then
          \mkdir -p ${KERNEL_PREBUILT_PATH}/dts/${soc_version}
        fi
        \rm -f ${KERNEL_PREBUILT_PATH}/dts/${soc_version}/*
        debug "cp $(find ${KERNEL_OUT}/ -name "${soc_version}.dtb" -print0 | tr '\0' '\n') ${KERNEL_PREBUILT_PATH}/dts/${soc_version}"
        \find ${KERNEL_OUT}/ -name "${soc_version}.dtb" -print0 | xargs -0 -I {} cp {} ${KERNEL_PREBUILT_PATH}/dts/${soc_version}

        for board_flavour in "${BOARD_FLAVOUR_LIST[@]}"
        do
          if  [ ! -d "${KERNEL_PREBUILT_PATH}/dts/${soc_version}-${board_flavour}" ]; then
            \mkdir -p ${KERNEL_PREBUILT_PATH}/dts/${soc_version}-${board_flavour}
          fi
          \rm -f ${KERNEL_PREBUILT_PATH}/dts/${soc_version}-${board_flavour}/*
          \find ${KERNEL_OUT}/ -name "${soc_version}-${board_flavour}-overlay.dtbo" -print0 | xargs -0 -I {} cp {} ${KERNEL_PREBUILT_PATH}/dts/${soc_version}-${board_flavour}
        done
      done
    fi

    if [[ ${do_onlydtb} == 0 ]] && [[ ${do_onlyvmlinux} == 0 ]]; then
      \rm -f ${KERNEL_PREBUILT_PATH}/modules/*
        if  [ -d "${modules_install_path}" ]; then
          \find ${modules_install_path}/ -name "*.ko" -print0 | xargs -0 -I {} cp {} ${KERNEL_PREBUILT_PATH}/modules/
          \find ${modules_install_path}/ -name "modules.dep" -print0 | xargs -0 -I {} cp {} ${KERNEL_PREBUILT_PATH}/modules/
          \find ${modules_install_path}/ -name "modules.order" -print0 | xargs -0 -I {} cp {} ${KERNEL_PREBUILT_PATH}/modules/
          \find ${modules_install_path}/ -name "modules.builtin" -print0 | xargs -0 -I {} cp {} ${KERNEL_PREBUILT_PATH}/modules/
          \find ${modules_install_path}/ -name "modules.builtin.modinfo" -print0 | xargs -0 -I {} cp {} ${KERNEL_PREBUILT_PATH}/modules/
        else
          error "Missing installation directory for modules, enable verbose for more information"
      fi
    fi

    if [[ ${do_onlydtb} == 0 ]] && [[ ${do_onlymodules} == 0 ]]; then
      \rm -f ${KERNEL_PREBUILT_PATH}/kernel-*
      \rm -f ${KERNEL_PREBUILT_PATH}/vmlinux-*
      \find ${KERNEL_OUT}/ -name "Image" -print0 | xargs -0 -I {} cp {} ${KERNEL_PREBUILT_PATH}/kernel-${SOC_FAMILY}
      if [[ ${do_gdb} == 1 ]]; then
        \cp ${KERNEL_OUT}/vmlinux ${KERNEL_PREBUILT_PATH}/vmlinux-${SOC_FAMILY}
      fi
    fi
  else
    if [[ ${do_onlygpu} == 1 ]]; then
      if [ -n "${kernel_gpu_name}" ]; then
        if  [ -d "${gpu_module_install_path}" ]; then
          \find ${gpu_module_install_path}/ -name "${kernel_gpu_name}.ko" -print0 | xargs -0 -I {} cp {} ${KERNEL_PREBUILT_PATH}/modules/
        else
          error "Missing installation directory for ${kernel_gpu_name}.ko, enable verbose for more information"
        fi
      else
        error "Undefined GPU name in build configuration file"
      fi
    fi
    if [[ ${do_onlywifi} == 1 ]]; then
      if [ -n "${kernel_wifi_name}" ]; then
        \find ${KERNEL_OUT}/ -name "${kernel_wifi_name}.ko" -print0 | xargs -0 -I {} cp {} ${KERNEL_PREBUILT_PATH}/modules/
      else
        error "Undefined WIFI name in build configuration file"
      fi
    fi
  fi

fi

popd >/dev/null 2>&1
