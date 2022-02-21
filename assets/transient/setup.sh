#!/bin/bash

PKGR="yum"
CONFIG_MANAGER="yum-config-manager"
# yum-utils is provided by "dnf-utils" in recent OS versions, but it always brings up yum-config-manager
PACKAGES="rpm-build rpmdevtools yum-utils rpmlint"
case "${DISTRO}" in
    amazonlinux|centos|cloudrouter*centos)
        # The PRE_ packages are typically release files, and need to be installed in a separate step to build ones
        PRE_PRE_PACKAGES="https://dl.fedoraproject.org/pub/epel/epel-release-latest-${RELEASE_EPEL}.noarch.rpm https://extras.getpagespeed.com/release-latest.rpm";
        PRE_PACKAGES="epel-release"
        # bypassing weird bug?
        # we do this whole concept of PRE_PRE because for amzn2 this release pkg is in our repo:
        if [[ ${RELEASE_EPEL} -le 7 ]]; then
          # yum-plugin-versionlock required to freeze our patched version of yum-builddep script
          # we also freeze "yum" for keeping User-Agent hack
          PACKAGES="${PACKAGES} yum-plugin-versionlock"
          if [[ "$DISTRO" == "amazonlinux" ]]; then
            PRE_PACKAGES="${PRE_PACKAGES} centos-release-scl"
          else
            PRE_PRE_PACKAGES="${PRE_PRE_PACKAGES} centos-release-scl"
          fi
        fi
        # CircleCI in EL6 sometimes fails (support claims it's due to lack of "official" git)
        # We threw latest git to our EL6 repo (clean Fedora rebuilt)
        PACKAGES="${PACKAGES} @buildsys-build git devtoolset-8-gcc-c++ devtoolset-8-binutils"
        if [[ ${RELEASE_EPEL} -ge 8 ]]; then
          PKGR="dnf";
          CONFIG_MANAGER="dnf config-manager"
          PACKAGES="dnf-plugins-core gcc rpmlint git rpm-build rpmdevtools tar gcc-c++ redhat-rpm-config redhat-release which xz sed make bzip2 gzip gcc unzip shadow-utils diffutils cpio bash gawk rpm-build info patch util-linux findutils grep python27 lua libarchive"
        fi
        # @buildsys-build is to better "emulate" mock by preinstalling gcc thus preventing devtoolset-* lookup for "BuildRequires: gcc"
        # devtoolset-8 is for faster CI builds of packages that want to use it
        ;;
    fedora|mageia)
        PKGR="dnf";
        # Just a dummy pre-install to simplify RUN step below
        PRE_PRE_PACKAGES="https://extras.getpagespeed.com/release-latest.rpm"
        PRE_PACKAGES="dnf-plugins-core"
        PACKAGES="dnf-plugins-core gcc rpmlint git rpm-build rpmdevtools tar gcc-c++ redhat-rpm-config which xz sed make bzip2 gzip gcc unzip shadow-utils diffutils cpio bash gawk rpm-build info patch util-linux findutils grep python27 lua libarchive"
        ;;
    opensuse)
        PKGR="dnf"
        # "zypper --non-interactive"
        # Just a dummy pre-install to simplify RUN step below
        PRE_PRE_PACKAGES="dnf"
        PRE_PACKAGES="dnf-plugins-core"
        PACKAGES="dnf-plugins-core gcc rpmlint git rpm-build rpmdevtools tar gcc-c++ rpm-config-SUSE which xz sed make bzip2 gzip gcc unzip diffutils cpio bash gawk rpm-build info patch util-linux findutils grep lua"
        ;;
esac

/tmp/distfix.sh

if [[ $PKGR == "dnf" ]]; then
  # dnf-command(builddep)'
  $PKGR -y install dnf-plugins-core
fi

${PKGR} -y install ${PRE_PRE_PACKAGES}

/tmp/fix-getpagespeed-repo.sh

${PKGR} -y install ${PRE_PACKAGES}

${PKGR} -y install ${PACKAGES}

ln -sf ${RPM_BUILD_DIR} /root/rpmbuild
mkdir -p ${SOURCES} ${WORKSPACE} ${OUTPUT} ${RPM_BUILD_DIR}/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

/tmp/post-distfix.sh

${PKGR} -y clean all && rm -rf /tmp/* && rm -rf /var/cache/*