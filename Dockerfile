# Docker container for building FreeDV. Source tree is expected to be
# mounted in /workspace.

FROM ubuntu:latest
LABEL org.opencontainers.image.authors="mooneer@gmail.com"

# Install prerequisite packages for building stuff in the first place
RUN apt-get update && \
    apt-get -y install build-essential unzip cmake nsis git automake autoconf libtool pkg-config tar gzip wget xvfb curl software-properties-common  cpio libssl-dev lzma-dev libxml2-dev xz-utils bzip2 libbz2-dev zlib1g-dev clang llvm-dev uuid-dev bash patch make xz-utils sed liblzma-dev

# Set up WINE (for Windows build).
RUN dpkg --add-architecture i386 && \
    sh -c "curl https://dl.winehq.org/wine-builds/winehq.key | gpg --dearmor > /etc/apt/trusted.gpg.d/winehq.gpg" && \
    sh -c "apt-add-repository \"https://dl.winehq.org/wine-builds/ubuntu\"" && \
    apt-get update && \
    apt install -y --install-recommends winehq-staging

# Set up Python for Windows (needed for RADE).
RUN mkdir -p /opt/windows && \
    export WINEPREFIX=/opt/windows/wine-env && \
    export WINEARCH=win64 && \
    DISPLAY= winecfg /v win10 && \
    wget https://www.python.org/ftp/python/3.12.7/python-3.12.7-amd64.exe && \
    xvfb-run -a -e /dev/stdout --server-args="-screen 0 1024x768x24" wine ./python-3.12.7-amd64.exe /quiet /log c:\\python.log InstallAllUsers=1 Include_doc=0 Include_tcltk=0 || : && \
    DISPLAY= wine c:\\Program\ Files\\Python312\\Scripts\\pip.exe install numpy && \
    rm python-3.12.7-amd64.exe

# Set up MinGW LLVM (Windows build)
RUN wget https://github.com/mstorsjo/llvm-mingw/releases/download/20230320/llvm-mingw-20230320-ucrt-ubuntu-18.04-x86_64.tar.xz && \
    tar xvf llvm-mingw-20230320-ucrt-ubuntu-18.04-x86_64.tar.xz && \
    mv llvm-mingw-20230320-ucrt-ubuntu-18.04-x86_64/* /opt/windows && \
    rm llvm-mingw-20230320-ucrt-ubuntu-18.04-x86_64.tar.xz

# Set up macOS Clang (macOS build)
COPY Command_Line_Tools_for_Xcode_16.2.dmg /Command_Line_Tools_for_Xcode_16.2.dmg
ARG UNATTENDED=1 INSTALLPREFIX=/opt/macos ENABLE_CLANG_INSTALL=1
RUN git clone https://github.com/tpoechtrager/osxcross && \
    cd osxcross && \
    ./build_apple_clang.sh && \
    PATH=/opt/macos/bin:$PATH ./tools/gen_sdk_package_tools_dmg.sh /Command_Line_Tools_for_Xcode_16.2.dmg && \
    mv *.tar.* tarballs/ && \
    PATH=/opt/macos/bin:$PATH TARGET_DIR=/opt/macos SDK_VERSION=15 ./build.sh && \
    cd .. && rm -rf osxcross /Command_Line_Tools_for_Xcode_16.2.dmg

# Copy cross-compilation files for FreeDV dependencies that use CMake.
# TBD -- only using x86 for now due to PyTorch not having an ARM for Windows version.
COPY freedv-mingw-llvm-aarch64.cmake /freedv-mingw-llvm-aarch64.cmake
COPY freedv-mingw-llvm-x86_64.cmake /freedv-mingw-llvm-x86_64.cmake

# Build dependency: libsamplerate
RUN git clone https://github.com/libsndfile/libsamplerate.git && \
    cd libsamplerate && \
    git checkout 0.2.2 && \
    mkdir build_windows && \
    cd build_windows && \
    PATH=/opt/windows/bin:$PATH cmake -DCMAKE_INSTALL_PREFIX=/opt/windows -DCMAKE_TOOLCHAIN_FILE=/freedv-mingw-llvm-x86_64.cmake .. && \
    PATH=/opt/windows/bin:$PATH make -j6 install && \
    cd ../.. && rm -rf libsamplerate

# Build dependency: socket.io
RUN git clone --recursive https://github.com/socketio/socket.io-client-cpp.git && \
    cd socket.io-client-cpp && \
    mkdir build_windows && \
    cd build_windows && \
    PATH=/opt/windows/bin:$PATH cmake -DCMAKE_INSTALL_PREFIX=/opt/windows -DBUILD_SHARED_LIBS=OFF -DCMAKE_TOOLCHAIN_FILE=/freedv-mingw-llvm-x86_64.cmake .. && \
    PATH=/opt/windows/bin:$PATH make -j6 install && \
    cd ../.. && rm -rf socket.io-client-cpp

# Build depednency: wxWidgets
RUN git clone --recursive -b v3.2.6 https://github.com/wxWidgets/wxWidgets.git && \
    cd wxWidgets && \
    mkdir build_windows && \
    cd build_windows && \
    PATH=/opt/windows/bin:$PATH cmake -DCMAKE_INSTALL_PREFIX=/opt/windows -DwxBUILD_SHARED=OFF -DwxBUILD_SHARED=OFF -DwxBUILD_MONOLITHIC=OFF -DwxUSE_STL=OFF -DwxUSE_STL=builtin -DwxUSE_ZLIB=builtin -DwxUSE_EXPAT=builtin -DwxUSE_LIBJPEG=builtin -DwxUSE_LIBPNG=builtin -DwxUSE_LIBTIFF=builtin -DwxUSE_NANOSVG=OFF -DwxUSE_LIBLZMA=OFF -DwxUSE_LIBSDL=OFF -DwxUSE_LIBMSPACK=OFF -DwxUSE_LIBICONV=OFF -DCMAKE_TOOLCHAIN_FILE=/freedv-mingw-llvm-x86_64.cmake .. && \
    PATH=/opt/windows/bin:$PATH make -j6 install && \
    cd ../.. && rm -rf wxWidgets

# Build dependency: portaudio
RUN git clone https://github.com/PortAudio/portaudio.git && \
    cd portaudio && \
    mkdir build_windows && \
    cd build_windows && \
    PATH=/opt/windows/bin:$PATH cmake -DCMAKE_INSTALL_PREFIX=/opt/windows -DCMAKE_TOOLCHAIN_FILE=/freedv-mingw-llvm-x86_64.cmake .. && \
    PATH=/opt/windows/bin:$PATH make -j6 install && \
    cd ../.. && rm -rf portaudio

# Build dependency: hamlib
COPY hamlib-windows.patch /hamlib-windows.patch
RUN git clone -b 4.6 https://github.com/Hamlib/hamlib.git && \
    cd hamlib && \
    patch -p1 < /hamlib-windows.patch && \
    ./bootstrap && \
    PATH=/opt/windows/bin:$PATH ./configure --without-cxx-binding --enable-shared --prefix=/opt/windows --host=x86_64-w64-mingw32 --target=x86_64-w64-mingw32 && \
    PATH=/opt/windows/bin:$PATH make -j6 && \
    PATH=/opt/windows/bin:$PATH make install && \
    cd .. && rm -rf hamlib && rm hamlib-windows.patch

# Build dependency: libsndfile
RUN wget http://www.mega-nerd.com/libsndfile/files/libsndfile-1.0.28.tar.gz && \
    tar xvzf libsndfile-1.0.28.tar.gz && \
    cd libsndfile-1.0.28 && \
    autoreconf -i && PATH=/opt/windows/bin:$PATH ./configure --prefix=/opt/windows --host=x86_64-w64-mingw32 --target=x86_64-w64-mingw32 --disable-external-libs --disable-shared --disable-sqlite && \
    PATH=/opt/windows/bin:$PATH make -j6 && \
    PATH=/opt/windows/bin:$PATH make install && \
    cd .. && rm -rf libsndfile*

# Build dependency: speexdsp
RUN git clone https://github.com/xiph/speexdsp && \
    cd speexdsp && \
    ./autogen.sh && PATH=/opt/windows/bin:$PATH ./configure --prefix=/opt/windows --host=x86_64-w64-mingw32 --target=x86_64-w64-mingw32 --disable-examples && \
    PATH=/opt/windows/bin:$PATH make -j6 && \
    PATH=/opt/windows/bin:$PATH make install && \
    cd .. && rm -rf speexdsp

# Copy build script
COPY build_freedv.sh /build_freedv.sh

CMD ["/bin/bash"]
