#!/bin/bash

#
# Copyright 2015 The Android Open Source Project
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

array=( "$@" )

KERNEL_PATH=${array[0]}
OUTPUT=${array[1]}
TARGET_ARCH=${array[2]}

unset "array[0]"
unset "array[1]"
unset "array[2]"

cd $KERNEL_PATH

# Merge .config with fragments
# Force CONFIG_LSM default config (depends on choice which is not well managed in merge script)
ARCH=$TARGET_ARCH ./scripts/kconfig/merge_config.sh -d CONFIG_LSM -C -O $OUTPUT ${array[*]}
