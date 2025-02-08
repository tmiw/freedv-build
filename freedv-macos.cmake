set(CMAKE_SYSTEM_NAME Darwin)
set(CMAKE_SYSTEM_PROCESSOR x86_64)
set(CMAKE_OSX_SYSROOT /opt/macos/SDK/MacOSX15.sdk)
set(triple ${CMAKE_SYSTEM_PROCESSOR}-apple-darwin24)
set(CMAKE_OSX_DEPLOYMENT_TARGET "10.13")

set(CMAKE_C_COMPILER ${triple}-clang)
set(CMAKE_C_COMPILER_TARGET ${triple})
set(CMAKE_CXX_COMPILER ${triple}-clang++)
set(CMAKE_CXX_COMPILER_TARGET ${triple})

set(CMAKE_AR ${triple}-ar)
set(CMAKE_RANLIB ${triple}-ranlib)

# For make package use.
set(CMAKE_OBJDUMP ${triple}-objdump)

# adjust the default behaviour of the FIND_XXX() commands:
# search headers and libraries in the target environment, search 
# programs in the host environment
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
