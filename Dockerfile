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
COPY freedv-macos.cmake /freedv-macos.cmake

# Add symlink for install_name_tool
RUN ln -s /opt/macos/bin/x86_64-apple-darwin24-install_name_tool /opt/macos/bin/install_name_tool

# Build macdylibbundler (needed for FreeDV .app generation)
RUN git clone https://github.com/auriamg/macdylibbundler && \
    cd macdylibbundler && \
    mkdir build && \
    cd build && \
    cmake .. && \
    make -j6 && \
    cp dylibbundler /usr/bin && \
    cd ../.. && rm -rf macdylibbundler

# Build dependency: libsamplerate
RUN git clone https://github.com/libsndfile/libsamplerate.git && \
    cd libsamplerate && \
    git checkout 0.2.2 && \
    mkdir build_windows && \
    cd build_windows && \
    PATH=/opt/windows/bin:$PATH cmake -DCMAKE_INSTALL_PREFIX=/opt/windows -DCMAKE_TOOLCHAIN_FILE=/freedv-mingw-llvm-x86_64.cmake .. && \
    PATH=/opt/windows/bin:$PATH make -j6 install && \
    cd .. && mkdir build_macos && cd build_macos && \
    PATH=/opt/macos/bin:$PATH cmake -DCMAKE_INSTALL_PREFIX=/opt/macos -DCMAKE_OSX_ARCHITECTURES="x86_64;arm64"  -DCMAKE_TOOLCHAIN_FILE=/freedv-macos.cmake .. && \
    PATH=/opt/macos/bin:$PATH make -j6 install && \
    cd .. && rm -rf libsamplerate

# Build dependency: OpenSSL
RUN wget https://github.com/openssl/openssl/releases/download/openssl-3.4.0/openssl-3.4.0.tar.gz && \
    tar xvzf openssl-3.4.0.tar.gz && \
    cd openssl-3.4.0 && \
    mkdir build_macos_x86 && cd build_macos_x86 && \
    PATH=/opt/macos/bin:$PATH CC=clang CXX=clang++ CROSS_COMPILE=x86_64-apple-darwin24- ../Configure --prefix=/opt/macos no-asm darwin64-x86_64-cc && \
    PATH=/opt/macos/bin:$PATH make -j6 && \
    PATH=/opt/macos/bin:$PATH make install && \
    cd .. && mkdir build_macos_arm64 && cd build_macos_arm64 && \
    PATH=/opt/macos/bin:$PATH CC=clang CXX=clang++ CROSS_COMPILE=arm64-apple-darwin24- ../Configure --prefix=/opt/macos no-asm darwin64-arm64-cc && \
    PATH=/opt/macos/bin:$PATH make -j6 && \
    cd .. && \
    PATH=/opt/macos/bin:$PATH lipo -create build_macos_x86/libcrypto.a build_macos_arm64/libcrypto.a -output /opt/macos/lib/libcrypto.a && \
    PATH=/opt/macos/bin:$PATH lipo -create build_macos_x86/libcrypto.3.dylib build_macos_arm64/libcrypto.3.dylib -output /opt/macos/lib/libcrypto.3.dylib && \
    PATH=/opt/macos/bin:$PATH lipo -create build_macos_x86/libssl.a build_macos_arm64/libssl.a -output /opt/macos/lib/libssl.a && \
    PATH=/opt/macos/bin:$PATH lipo -create build_macos_x86/libssl.3.dylib build_macos_arm64/libssl.3.dylib -output /opt/macos/lib/libssl.3.dylib && \
    PATH=/opt/macos/bin:$PATH install_name_tool -id '@rpath/libcrypto.3.dylib' /opt/macos/lib/libcrypto.3.dylib && \
    PATH=/opt/macos/bin:$PATH install_name_tool -id '@rpath/libssl.3.dylib' /opt/macos/lib/libssl.3.dylib && \
    mkdir build_windows && cd build_windows && \
    PATH=/opt/windows/bin:$PATH CC=clang CXX=clang++ CROSS_COMPILE=x86_64-w64-mingw32- ../Configure --prefix=/opt/windows mingw64 && \
    PATH=/opt/windows/bin:$PATH make -j6 && \
    PATH=/opt/windows/bin:$PATH make install && \
    cd ../.. && rm -rf openssl*

## Build dependency: socket.io
RUN git clone --recursive https://github.com/socketio/socket.io-client-cpp.git && \
    cd socket.io-client-cpp && \
    mkdir build_windows && \
    cd build_windows && \
    PATH=/opt/windows/bin:$PATH cmake -DCMAKE_INSTALL_PREFIX=/opt/windows -DBUILD_SHARED_LIBS=OFF -DCMAKE_TOOLCHAIN_FILE=/freedv-mingw-llvm-x86_64.cmake -DOPENSSL_ROOT_DIR=/opt/windows .. && \
    PATH=/opt/windows/bin:$PATH make -j6 install && \
    cd .. && \
    mkdir build_macos && cd build_macos && \
    PATH=/opt/macos/bin:$PATH cmake -DCMAKE_INSTALL_PREFIX=/opt/macos -DCMAKE_OSX_ARCHITECTURES="x86_64;arm64"  -DBUILD_SHARED_LIBS=OFF -DCMAKE_TOOLCHAIN_FILE=/freedv-macos.cmake -DOPENSSL_ROOT_DIR=/opt/macos .. && \
    PATH=/opt/macos/bin:$PATH make -j6 install && \
    cd ../.. && rm -rf socket.io-client-cpp

## Build depednency: wxWidgets
RUN wget https://github.com/wxWidgets/wxWidgets/releases/download/v3.2.6/wxWidgets-3.2.6.tar.bz2 && \
    tar xvjf wxWidgets-3.2.6.tar.bz2 && \
    cd wxWidgets-3.2.6 && \
    mkdir build_windows && \
    cd build_windows && \
    PATH=/opt/windows/bin:$PATH cmake -DCMAKE_INSTALL_PREFIX=/opt/windows -DwxBUILD_SHARED=OFF -DwxBUILD_PRECOMP=OFF -DwxBUILD_MONOLITHIC=OFF -DwxUSE_STL=OFF -DwxUSE_STL=builtin -DwxUSE_ZLIB=builtin -DwxUSE_EXPAT=builtin -DwxUSE_LIBJPEG=builtin -DwxUSE_LIBPNG=builtin -DwxUSE_LIBTIFF=builtin -DwxUSE_NANOSVG=OFF -DwxUSE_LIBLZMA=OFF -DwxUSE_LIBSDL=OFF -DwxUSE_LIBMSPACK=OFF -DwxUSE_LIBICONV=OFF -DCMAKE_TOOLCHAIN_FILE=/freedv-mingw-llvm-x86_64.cmake .. && \
    PATH=/opt/windows/bin:$PATH make -j6 install && \
    cd .. && mkdir build_macos && cd build_macos && \
    PATH=/opt/macos/bin:$PATH cmake -DCMAKE_INSTALL_PREFIX=/opt/macos -DCMAKE_OSX_ARCHITECTURES="x86_64;arm64" -DwxBUILD_SHARED=OFF -DwxBUILD_PRECOMP=OFF -DwxBUILD_MONOLITHIC=OFF -DwxUSE_STL=OFF -DwxUSE_STL=builtin -DwxUSE_ZLIB=builtin -DwxUSE_EXPAT=builtin -DwxUSE_LIBJPEG=builtin -DwxUSE_LIBPNG=builtin -DwxUSE_LIBTIFF=builtin -DwxUSE_NANOSVG=OFF -DwxUSE_LIBLZMA=OFF -DwxUSE_LIBSDL=OFF -DwxUSE_LIBMSPACK=OFF -DwxUSE_LIBICONV=OFF -DCMAKE_TOOLCHAIN_FILE=/freedv-macos.cmake .. && \
    PATH=/opt/macos/bin:$PATH make -j6 install && \
    cd ../.. && rm -rf wxWidgets

# Build dependency: portaudio
RUN git clone https://github.com/PortAudio/portaudio.git && \
    cd portaudio && \
    mkdir build_windows && \
    cd build_windows && \
    PATH=/opt/windows/bin:$PATH cmake -DCMAKE_INSTALL_PREFIX=/opt/windows -DCMAKE_TOOLCHAIN_FILE=/freedv-mingw-llvm-x86_64.cmake .. && \
    PATH=/opt/windows/bin:$PATH make -j6 install && \
    cd .. && mkdir build_macos && cd build_macos && \
    PATH=/opt/macos/bin:$PATH cmake -DCMAKE_INSTALL_PREFIX=/opt/macos -DCMAKE_OSX_ARCHITECTURES="x86_64;arm64" -DCMAKE_TOOLCHAIN_FILE=/freedv-macos.cmake .. && \
    PATH=/opt/macos/bin:$PATH make -j6 install && \
    cd ../.. && rm -rf portaudio

## Build dependency: hamlib
COPY hamlib-windows.patch /hamlib-windows.patch
RUN git clone -b 4.6 https://github.com/Hamlib/hamlib.git && \
    cd hamlib && \
    patch -p1 < /hamlib-windows.patch && \
    ./bootstrap && \
    PATH=/opt/windows/bin:$PATH ./configure --without-cxx-binding --enable-shared --prefix=/opt/windows --host=x86_64-w64-mingw32 --target=x86_64-w64-mingw32 && \
    PATH=/opt/windows/bin:$PATH make -j6 && \
    PATH=/opt/windows/bin:$PATH make install && \
    make distclean && ./bootstrap && \
    PATH=/opt/macos/bin:$PATH CC=x86_64-apple-darwin24-clang CXX=x86_64-apple-darwin24-clang++ ./configure --without-cxx-binding --enable-shared --prefix=/opt/macos --host=x86_64-apple-darwin24 --target=x86_64-apple-darwin24 --without-libusb CFLAGS=-g\ -O2\ -mmacosx-version-min=10.13\ -arch\ x86_64\ -arch\ arm64 CXXFLAGS=-g\ -O2\ -mmacosx-version-min=10.13\ -arch\ x86_64\ -arch\ arm64 && \
    PATH=/opt/macos/bin:$PATH make -j6 && \
    PATH=/opt/macos/bin:$PATH make install && \
    cd .. && rm -rf hamlib && rm hamlib-windows.patch

## Build dependency: libsndfile
RUN wget http://www.mega-nerd.com/libsndfile/files/libsndfile-1.0.28.tar.gz && \
    tar xvzf libsndfile-1.0.28.tar.gz && \
    cd libsndfile-1.0.28 && \
    autoreconf -i && PATH=/opt/windows/bin:$PATH ./configure --prefix=/opt/windows --host=x86_64-w64-mingw32 --target=x86_64-w64-mingw32 --disable-external-libs --disable-shared --disable-sqlite && \
    PATH=/opt/windows/bin:$PATH make -j6 && \
    PATH=/opt/windows/bin:$PATH make install && \
    make distclean && autoreconf -i && \
    PATH=/opt/macos/bin:$PATH CC=x86_64-apple-darwin24-clang CXX=x86_64-apple-darwin24-clang++ ./configure --prefix=/opt/macos --host=x86_64-apple-darwin24 --target=x86_64-apple-darwin24 --disable-external-libs --disable-shared --disable-sqlite CFLAGS=-g\ -O2\ -mmacosx-version-min=10.13\ -arch\ x86_64\ -arch\ arm64 LDFLAGS=-arch\ x86_64\ -arch\ arm64 && \
    PATH=/opt/macos/bin:$PATH make -j6 && \
    PATH=/opt/macos/bin:$PATH make install && \
    cd .. && rm -rf libsndfile*

# Build dependency: speexdsp
RUN git clone https://github.com/xiph/speexdsp && \
    cd speexdsp && \
    ./autogen.sh && PATH=/opt/windows/bin:$PATH ./configure --prefix=/opt/windows --host=x86_64-w64-mingw32 --target=x86_64-w64-mingw32 --disable-examples && \
    PATH=/opt/windows/bin:$PATH make -j6 && \
    PATH=/opt/windows/bin:$PATH make install && \
    make distclean && \
    ./autogen.sh && PATH=/opt/macos/bin:$PATH CC=x86_64-apple-darwin24-clang CXX=x86_64-apple-darwin24-clang++ ./configure --prefix=/opt/macos --host=x86_64-apple-darwin24 --target=x86_64-apple-darwin24 --disable-examples CFLAGS=-g\ -O2\ -mmacosx-version-min=10.13\ -arch\ x86_64\ -arch\ arm64 LDFLAGS=-arch\ x86_64\ -arch\ arm64 && \
    PATH=/opt/macos/bin:$PATH make -j6 && \
    PATH=/opt/macos/bin:$PATH make install && \
    cd .. && rm -rf speexdsp

# Copy build script
COPY build_freedv.sh /build_freedv.sh

CMD ["/bin/bash"]
