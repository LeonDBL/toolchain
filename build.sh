#!/bin/bash

##################################################################
#                                                                #
#                         Initial Setup                          #
#                                                                #
##################################################################

# Set component versions also used in determining paths
function toolchain_set_component_versions()
{
    [ -z "$BINUTILS" ] && BINUTILS=upstream
    [ -z "$CLOOG" ] && CLOOG=0.18.0
    [ -z "$PPL" ] && PPL=1.0
    [ -z "$GCC" ] && GCC=4.8
    [ -z "$GDB" ] && GDB=linaro-7.6-2013.05
    [ -z "$GMP" ] && GMP=5.1.2
    [ -z "$MPFR" ] && MPFR=3.1.2
    [ -z "$MPC" ] && MPC=1.0.1
}

# Set common variables used for the build
function toolchain_common_setup()
{
    # Export gcc version as an environment variable for
    # use elsewhere in the Android Build System
    export GCC_SOURCE_VER=$GCC

    # Parallel build flag passed to make
    if [ -e /proc/cpuinfo ]; then
        SMP="-j`cat /proc/cpuinfo | grep processor | wc -l`"
    else
        SMP="-j1"
    fi

    # Set cpu variant to be used in configure
    cpu_variant="$TARGET_CPU_VARIANT"
    if [ "$cpu_variant" = "krait" ]; then
       tune_variant=cortex-a9
    else
       tune_variant="$TARGET_CPU_VARIANT"
    fi
}


##################################################################
#                                                                #
#                         Path handling                          #
#                                                                #
##################################################################

# Set and clear destinations
function toolchain_prepare_destination()
{
    BUILD_OBJ=$OUT/toolchain_obj
    DEST=$ANDROID_BUILD_TOP/prebuilts/gcc/linux-x86/arm/$TOOLCHAIN_TARGET-$TARGET_GCC_VERSION
    rm -rf $BUILD_OBJ
    rm -rf $DEST
    mkdir -p $BUILD_OBJ
}

# Set local paths
function toolchain_set_local_paths()
{
    BIONIC_LIBC="$ANDROID_BUILD_TOP/bionic/libc"
    DEP_BIN="$DIR/bin"
    DIR="$ANDROID_BUILD_TOP/toolchain"
    SRC="$DIR/src"
}

# Set common paths and $PATH.
function toolchain_set_common_paths()
{
    # The path to the prebuilt host toolchain provided
    # by the Android Build System
    HOST_TC_PATH="$ANDROID_BUILD_TOP/prebuilts/gcc/linux-x86/host/x86_64-linux-glibc2.7-4.6/x86_64-linux/bin"

    # Backup $PATH with ABS additions
    export NEWPATH=$PATH

    # Set a generic $PATH
    export PATH=/home/$USER/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/share/bin:$DEP_BIN:$HOST_TC_PATH
}


##################################################################
#                                                                #
#                      Dependency handling                       #
#                                                                #
##################################################################

# Check that the user has makeinfo or texinfo installed
# before proceeding. If not, then build texinfo from source.
# texinfo will be installed to $DEP_BIN
# TODO: add dependency checking for patch and make.
function toolchain_dependency_resolution()
{
    if ! makeinfo --version > /dev/null; then
        $SRC/texinfo/configure \
            --prefix=$DEP_BIN \
            --exec_prefix=$DEP_BIN

        make $SMP
        make $SMP install exec_prefix=$DEP_BIN
    fi
}


##################################################################
#                                                                #
#                         Patch handling                         #
#                                                                #
##################################################################

# Apply squashed linaro patchset onto binutils
function toolchain_patch_binutils()
{
    cd $SRC/binutils/binutils-$BINUTILS
    git add .
    git add --all
    git reset --hard --quiet
    patch -p1 < "$DIR/cfx-R1-binutils_$BINUTILS-android.patch"
}


##################################################################
#                                                                #
#                    Toolchain Configuration                     #
#                                                                #
##################################################################

# Configure for TOOLCHAIN_TARGET triplet
function toolchain_configure()
{
    cd $BUILD_OBJ
    $SRC/build/configure --prefix="$DEST" \
        --with-mpc-version="$MPC" \
        --with-gdb-version="$GDB" \
        --with-cloog-version="$CLOOG" \
        --with-ppl-version="$PPL" \
        --with-mpfr-version="$MPFR" \
        --with-gmp-version="$GMP" \
        --with-binutils-version="$BINUTILS" \
        --with-gold-version="$BINUTILS" \
        --with-gcc-version="$GCC" \
        --with-sysroot=/ \
        --with-headers="$BIONIC_LIBC"/include \
        --with-headers="$BIONIC_LIBC"/arch-arm/include \
        --with-tune="$tune_variant" \
        --target="$TOOLCHAIN_TARGET" \
        --enable-graphite=yes \
        --disable-libsanitizer
}


##################################################################
#                                                                #
#                        Toolchain Build                         #
#                                                                #
##################################################################

# This is generic
function toolchain_make_install()
{
    make $SMP
    make install
}

# Build libgccunwind
function toolchain_make_arm_libgccunwind()
{
    local GCC_BUILD_OBJ_PREFIX="$BUILD_OBJ/gcc-$GCC/$TOOLCHAIN_TARGET"
    local ARM_OBJ_PATH="$GCC_BUILD_OBJ_PREFIX/libgcc"
    local ARM_THUMB_OBJ_PATH="$GCC_BUILD_OBJ_PREFIX/thumb/libgcc"
    local ARM_V7A_OBJ_PATH="$GCC_BUILD_OBJ_PREFIX/armv7-a/libgcc"
    local ARM_V7A_THUMB_OBJ_PATH="$GCC_BUILD_OBJ_PREFIX/armv7-a/thumb/libgcc"
    local UNWIND_TARGET_PREFIX="$DEST/lib/gcc/$TOOLCHAIN_TARGET/$GCC"
    local ARM_OBJS ARM_THUMB_OBJS ARM_V7A_OBJS ARM_V7A_THUMB_OBJS

    for OBJ in unwind-arm.o libunwind.o pr-support.o unwind-c.o; do
        ARM_OBJS=$ARM_OBJ_PATH/$OBJ
    done

    for OBJ in unwind-arm.o libunwind.o pr-support.o unwind-c.o; do
        ARM_THUMB_OBJS=$ARM_THUMB_OBJ_PATH/$OBJ
    done

    for OBJ in unwind-arm.o libunwind.o pr-support.o unwind-c.o; do
        ARM__V7A_OBJS=$ARM_V7A_OBJ_PATH/$OBJ
    done

    for OBJ in unwind-arm.o libunwind.o pr-support.o unwind-c.o; do
        ARM_V7A_THUMB_OBJS=$ARM_V7A_THUMB_OBJ_PATH/$OBJ
    done

    ar crs $UNWIND_TARGET_PREFIX/libgccunwind.a $ARM_OBJS
    ar crs $UNWIND_TARGET_PREFIX/thumb/libgccunwind.a $ARM_THUMB_OBJS
    ar crs $UNWIND_TARGET_PREFIX/armv7-a/libgccunwind.a $ARM_V7A_OBJS
    ar crs $UNWIND_TARGET_PREFIX/armv7-a/thumb/libgccunwind.a \
    $ARM_V7A_THUMB_OBJS
}


##################################################################
#                                                                #
#                      Toolchain PostBuild                       #
#                                                                #
##################################################################

# Copy makefiles into compiled destination
function toolchain_copy_makefiles()
{
    cp $DIR/Makefiles/Android.mk $DEST/Android.mk
    cp $DIR/Makefiles/toolchain.mk $DEST/toolchain.mk
    cp $DIR/Makefiles/lib32-Android.mk $DEST/lib32/Android.mk
}

# Print completion info
function toolchain_print_succeed_info()
{
    echo ""
    echo "=========================================================="
    echo "$TOOLCHAIN_TARGET toolchain build successful."
    echo "The toolchain can be found in $DEST."
    echo "Now building Android with cfX-Toolchain."
    echo "=========================================================="
    echo ""
    echo "=========================================================="
    echo "The toolchain was built with the following:"
    echo "=========================================================="
    echo "Binutils=\"$BINUTILS\""
    echo "Cloog=\"$CLOOG\""
    echo "PPL=\"$PPL\""
    echo "GCC=\"$GCC\""
    echo "GDB=\"$GDB\""
    echo "GMP=\"$GMP\""
    echo "MPFR=\"$MPFR\""
    echo "MPC=\"$MPC\""
    echo "=========================================================="
    echo ""
    echo "=========================================================="
    echo "A few notes:"
    echo "=========================================================="
    echo "1) If you do not want to build the toolchain inline in the"
    echo "future, run \"choosecombo\" instead of lunch."
    echo "Select \"release\" from the build type menu instead of"
    echo "\"development\""
    echo ""
    echo "2) We use $OUT for toolchain building due to some"
    echo "build configurations using paths other than"
    echo "$ANDROID_BUILD_TOP/out."
    echo ""
    echo "3) You may build the toolchain for a full target of your"
    echo "choosing by running your target as the toolchain_build"
    echo "argument."
    echo "=========================================================="
}

# Print failure info
function toolchain_print_fail_info()
{
    echo ""
    echo "=========================================================="
    echo "$TOOLCHAIN_TARGET toolchain build failed!"
    echo "Please check scrollback for the issue."
    echo "If needed, please mail the log to \"synergye (at) codefi.re\"."
    echo "=========================================================="
}

# Reset binutils and restore PATH
function toolchain_sanity_reset()
{
    cd $SRC/binutils/binutils-$BINUTILS
    git add .
    git add --all
    git reset --hard --quiet

    export PATH=$NEWPATH
    cd $ANDROID_BUILD_TOP
}


##################################################################
#                                                                #
#                        Build Functions                         #
#                                                                #
##################################################################

# Fully build TOOLCHAIN_TARGET triplet
function toolchain_build()
{
    TOOLCHAIN_TARGET=$1
    toolchain_set_component_versions
    toolchain_common_setup
    toolchain_prepare_destination
    toolchain_set_local_paths
    toolchain_set_common_paths
    toolchain_dependency_resolution
    toolchain_patch_binutils
    toolchain_configure
    toolchain_make_install
    if [ "$TOOLCHAIN_TARGET" = "arm-linux-androideabi" ]; then
        toolchain_make_arm_libgccunwind
        toolchain_copy_makefiles
    fi

    if $DEST/bin/$TOOLCHAIN_TARGET-gcc --version > /dev/null; then
        toolchain_print_succeed_info
    else
        toolchain_print_fail_info
    fi

    toolchain_sanity_reset
}


##################################################################
#                                                                #
#                      Packaging Functions                       #
#                                                                #
##################################################################

function toolchain_destination_tar()
{
    if [ ! $COMP_OPTS ]; then
        COMP_OPTS=cjf
    fi
    tar -$COMP_OPTS $1 $DEST
}

function toolchain_package()
{
    FILENAME=$2

    while getopts o:p: opt; do
        case $opt in
            o) COMP_OPTS=$OPTARG
                ;;
            p) PACK_PATH=$OPTARG
                ;;
        esac
    done

    if [ ! $FILENAME ]; then
        FILENAME=cfX-$GCC-$TOOLCHAIN_TARGET-toolchain.$(date +%Y%m%d).tar.bz2
    fi

    if [ ! $1 ]; then
        echo "Error: You must specify a toolchain target"
        echo "Usage: toolchain_package [TOOLCHAIN_TARGET] [OPTIONAL: FILENAME]"
        echo ""
        echo "Running \"toolchain_package arm-linux-androideabi\" would package"
        echo "the freshly built toolchain to your current directory."
        echo "If non-existent, it will build prior to packaging."
        echo ""
        echo "Additional flags:"
        echo "  -o, modify \"tar\" compatible compression options"
        echo "      i.e. cjf"
        echo ""
        echo "  -p, specify a new package path"
        echo "      a specified filename is still optional"
        echo ""
    else
        if [ $1 != $TOOLCHAIN_TARGET ]; then
            toolchain_build $1
        fi

        if [ $PACK_PATH ]; then
            toolchain_destination_tar $PACK_PATH/$FILENAME
        else
            toolchain_destination_tar $FILENAME
        fi
    fi
}
