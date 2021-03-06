#!/usr/bin/env bash

# *******************************************************************************
# Copyright 2020 Arm Limited and affiliates.
# SPDX-License-Identifier: Apache-2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# *******************************************************************************


# Staged docker build for TensorFlow
# ==================================

################################################################################
function print_usage_and_exit {
  echo "Usage: build.sh [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  -h, --help                   Display this message"
  echo "      --jobs                   Specify number of jobs to run in parallel during the build"
  echo "      --bazel_memory_limit     Set a memory limit for Bazel build"
  echo "      --dnnl                   Build and link to MKL-DNN / DNNL"
  echo "                                 * reference  - use the C++ reference kernels throughout."
  echo "                                 * openblas   - use OpenBLAS rather than reference kernel where possibe"
  echo "      --tf_version	       TensorFlow version (use 1 for TF=1.15.2 / 2 for TF=2.2.0)"
  echo "      --build-type             Type of build to perform:"
  echo "                                 * base       - build the basic portion of the image, OS and essential packages"
  echo "                                 * libs       - build image including maths libraries and Python3."
  echo "                                 * tools      - build image including Python3 venv, with numpy."
  echo "                                 * dev        - build image including Bazel and TensorFlow, with sources."
  echo "                                 * tensorflow - build image including TensorFlow build and benchmarks installed"
  echo "                                 * full       - build all images."
  echo ""
  echo "Example:"
  echo "  build.sh --build-type full"
  exit $1
}

################################################################################

# Enable Buildkit
# Required for advanced multi-stage builds
# Requires Docker v 18.09.1
export DOCKER_BUILDKIT=1

# Default build flags
build_base_image=
build_libs_image=
build_tools_image=
build_dev_image=
build_tensorflow_image=1
readonly target_arch="aarch64"
readonly host_arch=$(arch)

if ! [ "$host_arch" == "$target_arch" ]; then 
   echo "Error: $(arch) is not supported"
   print_usage_and_exit 1
fi


# Default args
extra_args=""
nproc_build=
bazel_mem=
dnnl_blas=
tf_version=1

while [ $# -gt 0 ]
do
  case $1 in
    --build-type )
      case $2 in
        base )
          build_base_image=1
          build_libs_image=
          build_tools_image=
          build_dev_image=
          build_tensorflow_image=
          ;;
        libs )
          build_base_image=
          build_libs_image=1
          build_tools_image=
          build_dev_image=
          build_tensorflow_image= 
          ;;
         tools )
          build_base_image=
          build_libs_image=
          build_tools_image=1
          build_dev_image=
          build_tensorflow_image=
          ;;
        dev )
          build_base_image=
          build_libs_image=
          build_tools_image=
          build_dev_image=1
          build_tensorflow_image=
          ;;
        full )
          build_base_image=1
          build_libs_image=1
          build_tools_image=1
          build_dev_image=1
          build_tensorflow_image=1
          ;;
        tensorflow )
          build_base_image=
          build_libs_image=
          build_tools_image=
          build_dev_image=
          build_tensorflow_image=1
          ;;
        * )
          echo "Error: $2 is an invalid build type!"
          print_usage_and_exit 1
          ;;
      esac
      shift
      ;;

    --jobs )
      nproc_build=$2
      shift
      ;;

    --bazel_memory_limit )
      bazel_mem=$2
      shift
      ;;

    --dnnl )
      dnnl_blas=$2
      shift
      ;;

    --tf_version )
      tf_version=$2
      shift
      ;;	

    -h | --help )
      print_usage_and_exit 0
      ;;

  esac
  shift
done

exec > >(tee -i build.log)
exec 2>&1

if [[ $nproc_build ]]; then
  # Set -j to use for builds, if specified
  extra_args="$extra_args --build-arg njobs=$nproc_build"
fi

if [[ $bazel_mem ]]; then
  # Set -j to use for builds, if specified
  extra_args="$extra_args --build-arg bazel_mem=$bazel_mem"
fi

if [[ $dnnl_blas ]]; then
  # DNNL based build 
  extra_args="$extra_args --build-arg dnnl_opt=$dnnl_blas"
fi

echo 'TF Version:' $tf_version

if [[ $tf_version == "1" ]]; then
   # TF1 version 
   version=1.15.2
   bazel_version=0.29.1	
   extra_args="$extra_args --build-arg tf_id=$tf_version"
   extra_args="$extra_args --build-arg tf_version=$version"
   extra_args="$extra_args --build-arg bazel_version=$bazel_version"	
elif [[ $tf_version == "2" ]]; then
   # TF2 version 
   version=2.2.0
   bazel_version=2.0.0
   extra_args="$extra_args --build-arg tf_id=$tf_version"
   extra_args="$extra_args --build-arg tf_version=$version"
   extra_args="$extra_args --build-arg bazel_version=$bazel_version"	
else
   echo 'TensorFlow version set to invalid value'
   exit 1	
fi

echo $extra_args

if [[ $build_base_image ]]; then
  # Stage 1: Base image, Ubuntu with core packages and GCC9
  docker build $extra_args --target tensorflow-base -t tensorflow-base-v$tf_version:latest .
fi

if [[ $build_libs_image ]]; then
  # Stage 2: Libs image, essential maths libs and Python built and installed
  docker build $extra_args --target tensorflow-libs -t tensorflow-libs-v$tf_version:latest .
fi

if [[ $build_tools_image ]]; then
  # Stage 3: Tools image, Python3 venv added with additional Python essentials
  docker build $extra_args --target tensorflow-tools -t tensorflow-tools-v$tf_version:latest .
fi

if [[ $build_dev_image ]]; then
  # Stage 4: Adds bazel and TensorFlow builds with sources
  docker build $extra_args --target tensorflow-dev -t tensorflow-dev-v$tf_version:latest .
fi

if [[ $build_tensorflow_image ]]; then
  # Stage 5: Adds bazel and TensorFlow builds with sources
  docker build $extra_args --target tensorflow -t tensorflow-v$tf_version:latest .
fi
