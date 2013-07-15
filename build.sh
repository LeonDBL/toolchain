#!/bin/bash

# What we're building with
[ -z "$BINUTILS" ] && BINUTILS=upstream
[ -z "$CLOOG" ] && CLOOG=0.18.0
[ -z "$PPL" ] && PPL=1.0
[ -z "$GCC" ] && GCC=4.8
[ -z "$GDB" ] && GDB=linaro-7.6-2013.05
[ -z "$GMP" ] && GMP=5.1.2
[ -z "$MPFR" ] && MPFR=3.1.2
[ -z "$MPC" ] && MPC=1.0.1

# First check that the user has makeinfo installed.
# All other dependencies are installed in metapackages
# on debian systems in the ABS setup.
if ! makeinfo --version > /dev/null; then
   echo -e "makeinfo not found! This is required to build the toolchain inline!"
   echo -e "You may install on ubuntu or debian by selecting \"y\""
   echo -e "at the prompt and typing your password."
   echo -e "Otherwise, you want to install \"texinfo\" using your"
   echo -e "preferred package manager"
   echo -e "Install? (y/n) \c"
   read
   if [ "$REPLY" = "y" ]; then
      sudo apt-get install texinfo
   else
      echo -e "You're missing a necessary dependency."
      echo -e "The build cannot continue. To use a prebuilt toolchain,"
      echo -e "run \"choosecombo\" and select \"release\" for build type"
      echo -e "instead of running \"lunch\""
      exit 0
   fi
fi

# Export gcc version as an environment variable for
# use elsewhere in the Android Build System
export GCC_SOURCE_VER=$GCC

# Installation location
# Note: we're only building arm-linux-androideabi currently
#
# TODO: support more triplets
DEST=$ANDROID_BUILD_TOP/prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-$TARGET_GCC_VERSION

# Before we do anything else, ensure that $DEST is clean.
# This is due to the CleanSpec behavior not acting
# as we would like it to.
rm -rf $DEST

# Parallel build flag passed to make
[ -z "$SMP" ] && SMP="-j`getconf _NPROCESSORS_ONLN`"

cpu_variant="$TARGET_CPU_VARIANT"
krait_variant=krait

# Set locales to avoid python warnings
# or errors depending on configuration
export LC_ALL=C

# Set our local paths
DIR="$ANDROID_BUILD_TOP/external/codefirex"
SRC="$DIR/src"

# Ensure the GCC source to be used is in an
# unpatched state before we apply our patchset.
cd $SRC/gcc/gcc-$GCC
git add .
git reset --hard --quiet

# Apply the fully squashed cfX patchset
# patch onto the GCC source. The patchset
# is comprised of AOSP commits and GCC
# trunk backports.
patch -p1 < "$DIR/gcc-$GCC-android.patch"

# Apply Andrew Hsieh's patch to add
# -foptimize-sincos for BIONIC
patch -p1 < "$DIR/gcc-android-optimize-sincos.patch"

# Ensure the binutils source to be used is in an
# unpatched state before we apply our patchset.
cd $SRC/binutils/binutils-$BINUTILS
git add .
git reset --hard --quiet

# Apply the fully squashed linaro patchset
# patch onto the binutils source. The patchset
# is comprised of linaro commits from binutils-
# current
patch -p1 < "$DIR/binutils-$BINUTILS-android.patch"

mkdir -p $OUT/toolchain_build
cd $OUT/toolchain_build

# Configure the build for arm-linux-androideabi
# with all additional arguments.
# Also set --with-tune for TARGET_CPU_VARIANT
if [ "$cpu_variant" = "$krait" ]; then
    $SRC/build/configure \
            --prefix="$DEST" \
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
            --with-tune=cortex-a9 \
            --target=arm-linux-androideabi \
            --enable-graphite=yes \
            --disable-libsanitizer
else
    $SRC/build/configure \
            --prefix="$DEST" \
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
            --with-tune="$TARGET_CPU_VARIANT" \
            --target=arm-linux-androideabi \
            --enable-graphite=yes \
            --disable-libsanitizer
fi

# We must use a "generic" $PATH for building
# the toolchain inline so as not to use the
# path with the ABS additions.
# First backup the new $PATH with Android
# path additions.
export NEWPATH=$PATH

# Export a "generic" path for sysrooted toolchain building.
# This should be foolproof, but please let me know
# at synergye@codefi.re if there are any additions
# that should be made for your distro or configuration.
# Also add $DEST to the new $PATH.
#
# This uses the $USER environment variable. It's also
# in use on bsd and darwin systems, but if it isn't set
# for you, you may use the $(whoami) function instead.
export PATH=/home/$USER/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/share/bin:$DEST

# Make and install the toolchain to the proper path
make $SMP
make install

#We need to copy the necessary makefiles for the
# Android build system now.
cp $DIR/Makefiles/Android.mk $DEST/Android.mk
cp $DIR/Makefiles/toolchain.mk $DEST/toolchain.mk
cp $DIR/Makefiles/lib32-Android.mk $DEST/lib32/Android.mk

echo ""
echo "=========================================================="
echo "Toolchain build successful."
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
echo "build configurations using multiple drives or partitions."
echo ""
echo "3) We have the entire toolchain_build folder in a"
echo "cleanspec, so there's no need to delete it ourselves."
echo "This means if you do not make clean, no new toolchain is"
echo "built (or fully built)."
echo ""
echo "4) The toolchain build uses your *HOST* sysroot."
echo "If you don't know what this means don't worry."
echo "If you do know what this means, we did it this way"
echo "to rid your build system of unnecessary symlinks"
echo "=========================================================="

# HACK: reset gcc back to it's unpatched state
cd $SRC/gcc/gcc-$GCC
git add .
git reset --hard --quiet

# Restore Android Build System set $PATH
export PATH=$NEWPATH

# Go back to android build top to continue the build
cd $ANDROID_BUILD_TOP

exit 0
