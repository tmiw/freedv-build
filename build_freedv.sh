#!/bin/bash

# Usage: /build_freedv.sh {windows,macos}

PLATFORM=$1
export PATH=/opt/$PLATFORM/bin:$PATH
cd /workspace
mkdir build_$PLATFORM
cd build_$PLATFORM

if [ "$PLATFORM" == "windows" ]; then
    cmake -DCMAKE_TOOLCHAIN_FILE=/freedv-mingw-llvm-x86_64.cmake -DLPCNET_DISABLE=1 -DPython3_ROOT_DIR=/opt/windows/wine-env/drive_c/Program\ Files/Python312 -DHAMLIB_LIBRARY=/opt/windows/lib/libhamlib.dll.a -DHAMLIB_INCLUDE_DIR=/opt/windows/include -DSIOCLIENT_LIBRARY=/opt/windows/lib/libsioclient.a -DSIOCLIENT_INCLUDE_DIR=/opt/windows/include -DLIBSNDFILE=/opt/windows/lib/libsndfile.a -DLIBSNDFILE_INCLUDE_DIR=/opt/windows/include -DLIBSAMPLERATE=/opt/windows/lib/libsamplerate.a -DLIBSAMPLERATE_INCLUDE_DIR=/opt/windows/include -DSPEEXDSP_LIBRARY=/opt/windows/lib/libspeexdsp.a -DSPEEXDSP_INCLUDE_DIR=/opt/windows/include  ..
    make -j6 && make package
fi

