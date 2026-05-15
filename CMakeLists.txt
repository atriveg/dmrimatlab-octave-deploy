cmake_minimum_required(VERSION 3.16)
project(DMRIMatlab_Superbuild NONE)
cmake_policy(SET CMP0135 NEW)

include(ExternalProject)
include(ProcessorCount)

# --- TOOL VALIDATION ---
# Enable languages to trigger CMake's automatic compiler search
enable_language(C CXX Fortran)

# --- CONFIGURATION OPTIONS ---
# Default to OPENBLAS as it's the most portable for local builds
set(BLAS_STRATEGY "OPENBLAS" CACHE STRING "Options: SYSTEM, OPENBLAS, MKL")
set_property(CACHE BLAS_STRATEGY PROPERTY STRINGS SYSTEM OPENBLAS MKL)

set(INSTALL_PREFIX "${CMAKE_BINARY_DIR}/install" CACHE PATH "Final installation directory")

# --- RESOURCE DETECTION (Scientific Approach) ---
ProcessorCount(N_PROCS)
# Rule of thumb: 1 thread per 2GB of RAM to prevent OOM (Out Of Memory) crashes
file(READ "/proc/meminfo" MEM_INFO)
string(REGEX MATCH "MemTotal:[ ]+([0-9]+)" _ ${MEM_INFO})
set(TOTAL_RAM_KB ${CMAKE_MATCH_1})
math(EXPR MAX_THREADS_BY_RAM "${TOTAL_RAM_KB} / 2000000")

if(MAX_THREADS_BY_RAM LESS N_PROCS)
    set(SAFE_JOBS ${MAX_THREADS_BY_RAM})
else()
    set(SAFE_JOBS ${N_PROCS})
endif()
if(SAFE_JOBS LESS 1)
    set(SAFE_JOBS 1)
endif()

message(STATUS "Build resources: Using ${SAFE_JOBS} parallel jobs based on available RAM.")

# --- STEP 1: BLAS/LAPACK IMPLEMENTATION ---

if(BLAS_STRATEGY STREQUAL "SYSTEM")
    # Search for system-wide reference implementation (Netlib)
    find_library(BLAS_LIB NAMES blas)
    find_library(LAPACK_LIB NAMES lapack)
    get_filename_component(BLAS_DIR "${BLAS_LIB}" DIRECTORY)
    get_filename_component(LAPACK_DIR "${LAPACK_LIB}" DIRECTORY)
    set(BLAS_CONFIG "netlib")
    set(OCTAVE_BLAS_LIBS "-lblas -llapack")
    set(OCTAVE_LDFLAGS "-L${BLAS_DIR} -L${LAPACK_LIB}")
    set(OCTAVE_LDFLAGS "")
    set(OCTAVE_CPPFLAGS "")
    message(STATUS "Using system BLAS: ${BLAS_LIB}")
    #################################################################################################
elseif(BLAS_STRATEGY STREQUAL "OPENBLAS")
    set(OPENBLAS_DIR "${CMAKE_BINARY_DIR}/openblas_build")

    ExternalProject_Add(openblas_proj
        GIT_REPOSITORY      https://github.com/OpenMathLib/OpenBLAS.git
        GIT_TAG             v0.3.26
        PREFIX              ${OPENBLAS_DIR}
        BUILD_IN_SOURCE     1
        CONFIGURE_COMMAND   ""
        BUILD_COMMAND       /usr/bin/env -u MAKEFLAGS -u MFLAGS -u MAKELEVEL make -j${SAFE_JOBS}
                                DYNAMIC_ARCH=0
                                BINARY=64
                                INTERFACE=32
                                NO_AFFINITY=1
                                NO_WARMUP=1
                                USE_OPENMP=1
                                USE_LOCKING=1
                                NO_CBLAS=1
                                NO_LAPACKE=1
                                CFLAGS=-fexceptions\ -fPIC\ -fno-omit-frame-pointer\ -pthread\ -fwrapv\ -O3\ -DNDEBUG
                                CXXFLAGS=-fexceptions\ -fPIC\ -fno-omit-frame-pointer\ -pthread\ -fwrapv\ -O3\ -DNDEBUG
                                FFLAGS=-O3
        INSTALL_COMMAND     /usr/bin/env -u MAKEFLAGS -u MFLAGS -u MAKELEVEL make
                                PREFIX=${INSTALL_PREFIX}/openblas install
        STEP_TARGETS        install
    )

    set(BLAS_LIB "${INSTALL_PREFIX}/openblas/lib/libopenblas.so")
    set(LAPACK_LIB "${INSTALL_PREFIX}/openblas/lib/libopenblas.so")
    set(BLAS_CONFIG "openblas-local")
    set(OCTAVE_BLAS_LIBS "-lopenblas")
    set(OCTAVE_LDFLAGS "-L${INSTALL_PREFIX}/openblas/lib")
    set(OCTAVE_CPPFLAGS "-I${INSTALL_PREFIX}/openblas/include/openblas")
    set(LOCAL_OPENBLAS_SUFFIX "local")

elseif(BLAS_STRATEGY STREQUAL "MKL")
    # Intel OneAPI MKL will be used only to build mex files.
    set(MKL_INSTALLER_URL "https://registrationcenter-download.intel.com/akdlm/IRC_NAS/6a17080f-f0de-41b9-b587-52f92512c59a/intel-onemkl-2025.3.1.11_offline.sh")
    set(MKL_TEMP_DIR "${CMAKE_BINARY_DIR}/mkl_download")

    # Set proper variables and libraries for mexfiles:
    set(MKL_ROOT "${INSTALL_PREFIX}/mkl/mkl/latest" CACHE PATH "MKL Root" FORCE)
    set(MKL_REDIST "${INSTALL_PREFIX}/mkl/compiler/latest/lib" CACHE PATH "MKL Redist" FORCE)
    set(BLAS_CONFIG "mkl" CACHE STRING "Blas Config" FORCE)

    # If the user has already installed MKL, the installation script
    # throws an error, and it seems impossible to work around this. Check it:
    file(WRITE "${CMAKE_BINARY_DIR}/check_mkl.cmake" "
        if(EXISTS \"\$ENV{HOME}/intel\" AND IS_DIRECTORY \"\$ENV{HOME}/intel\")
            message(FATAL_ERROR \"[MKL ERROR] Intel OneAPI MKL seems to be already installed by this user. You will need to delete ~/intel and ~/.intel before you proceed.\")
        endif()
    ")

    ExternalProject_Add(mkl_proj
        URL                 ${MKL_INSTALLER_URL}
        DOWNLOAD_NO_EXTRACT TRUE
        PREFIX              ${MKL_TEMP_DIR}
        # 1. Check if MKL is already present
        CONFIGURE_COMMAND   ${CMAKE_COMMAND} -P "${CMAKE_BINARY_DIR}/check_mkl.cmake"
        # 2. Just add exec permission
        BUILD_COMMAND       chmod +x <DOWNLOADED_FILE>
        # 3. Actual install
        INSTALL_COMMAND     <DOWNLOADED_FILE> -a -s --install-dir=${INSTALL_PREFIX}/mkl --eula accept && rm -rf "$ENV{HOME}/intel" "$ENV{HOME}/.intel"
    )

    # OpenBLAS is still necessary since GNU Octave does not seem to work with MKL:
    set(OPENBLAS_DIR "${CMAKE_BINARY_DIR}/openblas_build")

    ExternalProject_Add(openblas_proj
        GIT_REPOSITORY      https://github.com/OpenMathLib/OpenBLAS.git
        GIT_TAG             v0.3.26
        PREFIX              ${OPENBLAS_DIR}
        BUILD_IN_SOURCE     1
        CONFIGURE_COMMAND   ""
        BUILD_COMMAND       /usr/bin/env -u MAKEFLAGS -u MFLAGS -u MAKELEVEL make -j${SAFE_JOBS}
                                DYNAMIC_ARCH=0
                                BINARY=64
                                INTERFACE=32
                                NO_AFFINITY=1
                                NO_WARMUP=1
                                USE_OPENMP=1
                                USE_LOCKING=1
                                NO_CBLAS=1
                                NO_LAPACKE=1
                                CFLAGS=-fexceptions\ -fPIC\ -fno-omit-frame-pointer\ -pthread\ -fwrapv\ -O3\ -DNDEBUG
                                CXXFLAGS=-fexceptions\ -fPIC\ -fno-omit-frame-pointer\ -pthread\ -fwrapv\ -O3\ -DNDEBUG
                                FFLAGS=-O3
        INSTALL_COMMAND     /usr/bin/env -u MAKEFLAGS -u MFLAGS -u MAKELEVEL make
                                PREFIX=${INSTALL_PREFIX}/openblas install
        STEP_TARGETS        install
    )

    # Set proper variables and libraries for GNU Octave:
    set(BLAS_LIB "${INSTALL_PREFIX}/openblas/lib/libopenblas.so")
    set(LAPACK_LIB "${INSTALL_PREFIX}/openblas/lib/libopenblas.so")
    set(OCTAVE_BLAS_LIBS "-lopenblas")
    set(OCTAVE_LDFLAGS "-L${INSTALL_PREFIX}/openblas/lib")
    set(OCTAVE_CPPFLAGS "-I${INSTALL_PREFIX}/openblas/include/openblas")

endif()

# --- PREPARE DEPENDENCIES FOR OCTAVE ---
set(OCTAVE_DEPENDS "")
if(BLAS_STRATEGY STREQUAL "OPENBLAS")
    set(OCTAVE_DEPENDS "openblas_proj")
elseif(BLAS_STRATEGY STREQUAL "MKL")
    set(OCTAVE_DEPENDS "mkl_proj")
endif()

# --- STEP 2: MINIMAL GNU OCTAVE ---
set(OCTAVE_DIR "${CMAKE_BINARY_DIR}/octave_build")

ExternalProject_Add(octave_proj
    DEPENDS        ${OCTAVE_DEPENDS}
    URL            https://ftp.gnu.org/gnu/octave/octave-9.1.0.tar.gz
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE
    PREFIX         ${OCTAVE_DIR}
    # We pass the environment variables inside CONFIGURE_COMMAND to ensure they are local to Octave
    CONFIGURE_COMMAND <SOURCE_DIR>/configure
        LIBS=${OCTAVE_BLAS_LIBS}
        LDFLAGS=${OCTAVE_LDFLAGS}
        CPPFLAGS=${OCTAVE_CPPFLAGS}
        --prefix=${INSTALL_PREFIX}/octave
        --disable-java --without-x --without-opengl --without-fltk
        --without-qt --without-magick --without-curl --without-fftw3 --without-arpack
        --without-qrupdate --without-amd --without-camd
        --without-colamd --without-ccolamd --without-cholmod --without-umfpack
        --disable-docs --disable-readline
        --with-blas=${BLAS_LIB}
        --with-lapack=${LAPACK_LIB}

    # We use the 'env -u' only for the build step to avoid the -a flag error
    BUILD_COMMAND  /usr/bin/env -u MAKEFLAGS -u MFLAGS -u MAKELEVEL make -j${SAFE_JOBS}
    INSTALL_COMMAND /usr/bin/env -u MAKEFLAGS -u MFLAGS -u MAKELEVEL make install
)

# --- STEPS 3, 4, & 5: TOOLBOX SETUP AND MEX COMPILATION ---
set(TOOLBOX_DIR "${CMAKE_BINARY_DIR}/toolbox_build")

# Define BLAS targets to trigger clean-up:
set(BLAS_DEP_TARGET "")
if(BLAS_STRATEGY STREQUAL "OPENBLAS")
    set(BLAS_DEP_TARGET "openblas_proj-install")
elseif(BLAS_STRATEGY STREQUAL "MKL")
    set(MKL_PROJ_DEPEND "mkl_proj")
endif()

# Create a helper CMake script to write the Octave build script perfectly
set(WRITE_HELPER_SCRIPT "${CMAKE_BINARY_DIR}/write_m_script.cmake")
file(WRITE "${WRITE_HELPER_SCRIPT}" [=[
    # Avoid writing the m-file if the toolbox does not exist yet
    if(EXISTS "${SRC_DIR}/setup__DMRIMatlab_toolbox.m")
        file(WRITE "${M_FILE}" "addpath('${SRC_DIR}'); cd('${SRC_DIR}'); setup__DMRIMatlab_toolbox; makefile_mexcode('${OCTAVE_MAKEFILE_ARG}'); exit();\n")
    else()
        # Create an empty m-file so that Otave does not crash
        file(WRITE "${M_FILE}" "exit();\n")
    endif()
]=])

ExternalProject_Add(dmrimatlab_proj
    DEPENDS         octave_proj ${MKL_PROJ_DEPEND}
    GIT_REPOSITORY  https://github.com/atriveg/dmrimatlab.git
    GIT_TAG         main
    PREFIX          ${TOOLBOX_DIR}
    CONFIGURE_COMMAND ""
    # STEP 4: Generate config.octave
    BUILD_COMMAND ${CMAKE_COMMAND} -E echo "GCC_FLAGS=-DMX_COMPAT_64 -D_GNU_SOURCE -fexceptions -fPIC -fno-omit-frame-pointer -pthread -fwrapv -O3 -DNDEBUG" > <SOURCE_DIR>/mexcode/config.octave
    COMMAND echo "BLAS_CONFIG=${BLAS_CONFIG}" >> <SOURCE_DIR>/mexcode/config.octave
    COMMAND echo "LOCAL_OPENBLAS_SUFFIX=${LOCAL_OPENBLAS_SUFFIX}" >> <SOURCE_DIR>/mexcode/config.octave
    COMMAND echo "LOCAL_OPENBLAS_BUILD_WARNING=no" >> <SOURCE_DIR>/mexcode/config.octave
    COMMAND echo "MKL_ROOT=${MKL_ROOT}" >> <SOURCE_DIR>/mexcode/config.octave
    COMMAND echo "MKL_REDIST=${MKL_REDIST}" >> <SOURCE_DIR>/mexcode/config.octave
    # STEP 5: Create the .m script using the helper and execute it
    COMMAND ${CMAKE_COMMAND}
            -DM_FILE=<BINARY_DIR>/build_mex.m
            -DSRC_DIR=<SOURCE_DIR>
            "-DOCTAVE_MAKEFILE_ARG=build"
            -P "${WRITE_HELPER_SCRIPT}"
    COMMAND /usr/bin/env -u MAKEFLAGS -u MFLAGS -u MAKELEVEL ${INSTALL_PREFIX}/octave/bin/octave --no-gui --no-window-system -q <BINARY_DIR>/build_mex.m
    INSTALL_COMMAND ""
)

# Make sure mex files are re-built only if necessary:
set(BLAS_STAMP_FILE "${CMAKE_BINARY_DIR}/blas_strategy.stamp")
file(WRITE "${BLAS_STAMP_FILE}.tmp" "${BLAS_STRATEGY}")
execute_process(COMMAND ${CMAKE_COMMAND} -E copy_if_different "${BLAS_STAMP_FILE}.tmp" "${BLAS_STAMP_FILE}")

ExternalProject_Add_Step(dmrimatlab_proj clean_mex_logic
    COMMAND ${CMAKE_COMMAND}
            -DM_FILE=<BINARY_DIR>/clean_mex.m
            -DSRC_DIR=<SOURCE_DIR>
            "-DOCTAVE_MAKEFILE_ARG=clean"
            -P "${WRITE_HELPER_SCRIPT}"

    COMMAND /usr/bin/env -u MAKEFLAGS -u MFLAGS -u MAKELEVEL ${INSTALL_PREFIX}/octave/bin/octave --no-gui --no-window-system -q <BINARY_DIR>/clean_mex.m

    DEPENDEE  download
    DEPENDERS build

    DEPENDS   "${BLAS_STAMP_FILE}" ${BLAS_DEP_TARGET}

    LOG 1
    COMMENT "Checking if MEX files need cleaning due to BLAS change..."
)

# --- STEP 6: FINAL DEPLOYMENT (ENFORCING ABSOLUTE PATHS) ---

# 1. Force absolute paths to prevent empty variables in the sub-shell
get_filename_component(ABS_INSTALL_BIN "${INSTALL_PREFIX}/bin" ABSOLUTE)
get_filename_component(ABS_OCTAVE_PATH "${INSTALL_PREFIX}/octave/bin/octave" ABSOLUTE)
get_filename_component(ABS_TOOLBOX_PATH "${TOOLBOX_DIR}/src/dmrimatlab_proj" ABSOLUTE)
get_filename_component(ABS_SCRIPTS_SRC  "${CMAKE_SOURCE_DIR}/scripts" ABSOLUTE)

# 2. Create the deployment helper script
set(DEPLOY_HELPER "${CMAKE_BINARY_DIR}/deploy_all.cmake")
file(WRITE "${DEPLOY_HELPER}" [=[
    # Safety check: ensure variables are not empty
    if(NOT OUTPUT_BIN OR NOT OCTAVE OR NOT TOOLBOX)
        message(FATAL_ERROR "Deployment failed: One or more paths are empty!
        OUTPUT_BIN: ${OUTPUT_BIN}
        OCTAVE: ${OCTAVE}
        TOOLBOX: ${TOOLBOX}")
    endif()

    message(STATUS "Deploying to: ${OUTPUT_BIN}")
    file(MAKE_DIRECTORY "${OUTPUT_BIN}")

    # Generate the main wrapper script
    file(READ "${INPUT_TEMPLATE}" CONTENT)
    string(REPLACE "@OCTAVE_EXE_PATH@" "${OCTAVE}" CONTENT "${CONTENT}")
    string(REPLACE "@TOOLBOX_ROOT_PATH@" "${TOOLBOX}" CONTENT "${CONTENT}")
    string(REPLACE "@SCRIPTS_INSTALL_PATH@" "${OUTPUT_BIN}" CONTENT "${CONTENT}")

    file(WRITE "${OUTPUT_BIN}/dmrimatlab" "${CONTENT}")
    execute_process(COMMAND chmod +x "${OUTPUT_BIN}/dmrimatlab")

    # Copy all auxiliary .m scripts
    message(STATUS "Copying .m scripts from ${SCRIPTS_SRC}...")
    file(GLOB M_SCRIPTS "${SCRIPTS_SRC}/*.m" "${SCRIPTS_SRC}/dmrimatlab.help" "${SCRIPTS_SRC}/dmrimatlab.list")
    foreach(SCRIPT ${M_SCRIPTS})
        file(COPY "${SCRIPT}" DESTINATION "${OUTPUT_BIN}")
    endforeach()
    message(STATUS "Don't forget to add ${OUTPUT_BIN} to your path so that dmrimatlab can be found")
]=])

# 3. The ExternalProject step
ExternalProject_Add(deployment_step
    DEPENDS             dmrimatlab_proj
    DOWNLOAD_COMMAND    ""
    CONFIGURE_COMMAND   ""
    BUILD_COMMAND       ""
    # Pass the FORCED absolute paths here
    INSTALL_COMMAND     ${CMAKE_COMMAND}
                        -DINPUT_TEMPLATE=${CMAKE_SOURCE_DIR}/scripts/dmrimatlab.in
                        -DSCRIPTS_SRC=${ABS_SCRIPTS_SRC}
                        -DOUTPUT_BIN=${ABS_INSTALL_BIN}
                        -DOCTAVE=${ABS_OCTAVE_PATH}
                        -DTOOLBOX=${ABS_TOOLBOX_PATH}
                        -P "${DEPLOY_HELPER}"
)


