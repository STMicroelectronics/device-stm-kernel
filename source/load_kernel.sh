#!/bin/bash
#
# Load Linux kernel source

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
SCRIPT_VERSION="1.0"

SOC_FAMILY="stm32mp1"
SOC_NAME="stm32mp15"
SOC_VERSION="stm32mp157c"

KERNEL_VERSION=4.19

if [ -n "${ANDROID_BUILD_TOP+1}" ]; then
  TOP_PATH=${ANDROID_BUILD_TOP}
elif [ -d "device/stm/${SOC_FAMILY}-kernel" ]; then
  TOP_PATH=$PWD
else
  echo "ERROR: ANDROID_BUILD_TOP env variable not defined, this script shall be executed on TOP directory"
  exit 1
fi

\pushd ${TOP_PATH} >/dev/null 2>&1

KERNEL_PATH="${TOP_PATH}/device/stm/${SOC_FAMILY}-kernel"
COMMON_PATH="${TOP_PATH}/device/stm/${SOC_FAMILY}"

KERNEL_CONFIG_PATH="${KERNEL_PATH}/source/patch/${KERNEL_VERSION}/android_kernel.config"
KERNEL_PATCH_PATH="${KERNEL_PATH}/source/patch/${KERNEL_VERSION}"

KERNEL_CONFIG_STATUS_PATH="${COMMON_PATH}/configs/kernel.config"

#######################################
# Variables
#######################################
nb_states=2
force_loading=0
msg_patch=0

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
  echo "Usage: `basename $0` [Options]"
  empty_line
  echo "  This script allows loading the Linux kernel source"
  echo "  based on the configuration file $KERNEL_CONFIG_PATH"
  empty_line
  echo "Options:"
  echo "  -h/--help: print this message"
  echo "  -v/--version: get script version"
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
  echo -ne "  [${action_state}/${nb_states}]: $1 \033[0K\r"
  action_state=$((action_state+1))
}

#######################################
# Clean before exit
# Globals:
#   All
# Arguments:
#   $1: ERROR or OK
# Returns:
#   None
#######################################
teardown() {

  if [[ "$1" == "ERROR" ]]; then
      \pushd $TOP_PATH >/dev/null 2>&1
      \rm -rf ${kernel_path}
      \popd >/dev/null 2>&1
  fi

  if [[ ${msg_patch} == 1 ]]; then
    \popd >/dev/null 2>&1
  fi

  # Come back to original directory
  \popd >/dev/null 2>&1
}

#######################################
# Check Kernel status within the status file
# Globals:
#   I KERNEL_CONFIG_STATUS_PATH
# Arguments:
#   None
# Returns:
#   1 if Kernel is already loaded
#   0 if Kernel is not already loaded
#######################################
check_kernel_status()
{
  local kernel_status

  \ls ${KERNEL_CONFIG_STATUS_PATH}  >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    kernel_status=`grep KERNEL ${KERNEL_CONFIG_STATUS_PATH}`
    if [[ ${kernel_status} =~ "LOADED" ]]; then
      return 1
    fi
  fi
  return 0
}

#######################################
# Apply selected patch in current target directory
# Globals:
#   I KERNEL_PATCH_PATH
# Arguments:
#   $1: patch
# Returns:
#   None
#######################################
apply_patch()
{
  local loc_patch_path

  loc_patch_path=${KERNEL_PATCH_PATH}/
  loc_patch_path+=$1
  loc_patch_path+=".patch"

  \git am ${loc_patch_path} &> /dev/null
  if [ $? -ne 0 ]; then
    error "Not possible to apply patch ${loc_patch_path}, please review android_kernel.config"
    teardown "ERROR"
    exit 1
  fi
}

#######################################
# Main
#######################################

# Check the current usage
if [ $# -gt 1 ]
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

    "-f"|"--force" )
      force_loading=1
      ;;

    ** )
      usage
      popd >/dev/null 2>&1
      exit 0
      ;;
  esac
  shift
done

# Check existence of the KERNEL configuration file
if [[ ! -f ${KERNEL_CONFIG_PATH} ]]; then
  error "Kernel configuration ${KERNEL_CONFIG_PATH} file not available"
  popd >/dev/null 2>&1
  exit 1
fi

# Check kernel status
check_kernel_status
kernel_status=$?

if [[ ${kernel_status} == 1 ]] && [[ ${force_loading} == 0 ]]; then
  blue "The kernel has been already loaded"
  echo " If you want to reload it"
  echo "   execute the script with -f/--force option"
  echo "   or remove the file ${KERNEL_CONFIG_STATUS_PATH}"
  popd >/dev/null 2>&1
  exit 0
fi

empty_line
echo "Start loading the kernel source (Linux)"

# Start Kernel config file parsing
while IFS='' read -r line || [[ -n $line ]]; do

  echo $line | grep '^KERNEL_'  >/dev/null 2>&1

  if [ $? -eq 0 ]; then

    line=$(echo "${line: 7}")

    unset kernel_value
    kernel_value=($(echo $line | awk '{ print $1 }'))
        
    case ${kernel_value} in
      "GIT_PATH" )
        git_path=($(echo $line | awk '{ print $2 }'))
        state "Loading Kernel source (it can take several minutes)"

        if [ -n "${KERNEL_CACHE_DIR+1}" ]; then
          \git clone --reference ${KERNEL_CACHE_DIR} ${git_path} ${kernel_path}  >/dev/null 2>&1
        else
          \git clone ${git_path} ${kernel_path}  >/dev/null 2>&1
        fi

        if [ $? -ne 0 ]; then
          error "Not possible to clone module from ${git_path}"
          teardown "ERROR"
          exit 1
        fi
        ;;
      "GIT_SHA1" )
        git_sha1=($(echo $line | awk '{ print $2 }'))
        \pushd ${kernel_path}  >/dev/null 2>&1
        \git checkout ${git_sha1} &> /dev/null
        if [ $? -ne 0 ]; then
          error "Not possible to checkout ${git_sha1} for ${git_path}"
          teardown "ERROR"
          exit 1
        fi
        \popd  >/dev/null 2>&1
                ;;
      "FILE_PATH" )
        kernel_path=($(echo $line | awk '{ print $2 }'))
        msg_patch=0
        \rm -rf ${kernel_path}
        if [[ ${force_loading} == 1 ]]; then
          \rm -f ${KERNEL_CONFIG_STATUS_PATH}
        fi
        ;;
      "PATCH"* )
        patch_path=($(echo $line | awk '{ print $2 }'))
        if [[ ${msg_patch} == 0 ]]; then
          state "Applying required patches to ${kernel_path}"
          pushd ${kernel_path}  >/dev/null 2>&1
          msg_patch=1
        fi
        apply_patch "${patch_path}"
        ;;
    esac
  fi
done < ${KERNEL_CONFIG_PATH}

echo "KERNEL LOADED" >> ${KERNEL_CONFIG_STATUS_PATH}

clear_line
green "The kernel has been successfully loaded in ${kernel_path}"

teardown "OK"
