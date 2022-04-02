#!/bin/bash
shopt -s extglob
set -euxo pipefail
if test -f /etc/os-release; then
   . /etc/os-release
elif test -f /usr/lib/os-release; then
   . /usr/lib/os-release
fi

RHEL=$(rpm -E 0%{?rhel})
# removes leading zeros, e.g. 07 becomes 0, but 0 stays 0
RHEL=${RHEL##+(0)}

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
          PACKAGES="dnf-plugins-core gcc rpmlint git rpm-build rpmdevtools tar gcc-c++ redhat-rpm-config redhat-release which xz sed make bzip2 gzip gcc unzip shadow-utils diffutils cpio bash gawk rpm-build info patch util-linux findutils grep lua libarchive"
        fi
        if [[ ${RELEASE_EPEL} -eq 8 ]]; then
          PACKAGES="${PACKAGES} python27"
        fi
        # no Python 2 in EL 8?
        # @buildsys-build is to better "emulate" mock by preinstalling gcc thus preventing devtoolset-* lookup for "BuildRequires: gcc"
        # devtoolset-8 is for faster CI builds of packages that want to use it
        ;;
    fedora|mageia)
        PKGR="dnf";
        # Just a dummy pre-install to simplify RUN step below
        PRE_PRE_PACKAGES="https://extras.getpagespeed.com/release-latest.rpm"
        PRE_PACKAGES="dnf-plugins-core"
        PACKAGES="dnf-plugins-core gcc rpmlint git rpm-build rpmdevtools tar gcc-c++ redhat-rpm-config which xz sed make bzip2 gzip gcc unzip shadow-utils diffutils cpio bash gawk rpm-build info patch util-linux findutils grep python2 lua libarchive"
        ;;
    opensuse)
        PKGR="dnf"
        # "zypper --non-interactive"
        # Just a dummy pre-install to simplify RUN step below
        PRE_PRE_PACKAGES="dnf"
        PRE_PACKAGES="dnf-plugins-core"
        PACKAGES="dnf-plugins-core gcc rpmlint git rpm-build rpmdevtools tar gcc-c++ rpm-config-SUSE which xz sed make bzip2 gzip gcc unzip diffutils cpio bash gawk rpm-build info patch util-linux findutils grep lua spectool"
        ;;
esac

# Fix up base repos in a way that we can install any packages at all ...

if test -n "${ID-}"; then
  if [ "$ID" = "opensuse-leap" ]; then
      echo "Do something Leap specific"
      zypper --non-interactive install dnf libdnf-repo-config-zypp
      # this repo has None for type=
      rm -rf /etc/zypp/repos.d/repo-backports-debug-update.repo
  fi
fi


if [[ $RHEL == 6 ]]; then
  curl https://www.getpagespeed.com/files/centos6-eol.repo --output /etc/yum.repos.d/CentOS-Base.repo
  rpm --rebuilddb && yum -y install yum-plugin-ovl
  yum -y install yum-plugin-ovl
  yum -y install centos-release-scl
  curl https://www.getpagespeed.com/files/centos6-scl-eol.repo --output /etc/yum.repos.d/CentOS-SCLo-scl.repo
  curl https://www.getpagespeed.com/files/centos6-scl-rh-eol.repo --output /etc/yum.repos.d/CentOS-SCLo-scl-rh.repo

  yum -y install epel-release
  curl https://www.getpagespeed.com/files/centos6-epel-eol.repo --output /etc/yum.repos.d/epel.repo
fi

if [[ $RHEL == 8 ]]; then
  # mirrorlist service is very often 503. avoid it by direct use
  sed -i 's@^#baseurl@baseurl@g' /etc/yum.repos.d/Rocky-*.repo
  sed -i 's@^mirrorlist@#mirrorlist@g' /etc/yum.repos.d/Rocky-*.repo
fi

if [[ $PKGR == "dnf" ]]; then
  # dnf-command(builddep)' and 'dnf-command(config-manager)'
  $PKGR -y install dnf-plugins-core
fi

${PKGR} -y install ${PRE_PRE_PACKAGES}

/tmp/fix-getpagespeed-repo.sh

${PKGR} -y install ${PRE_PACKAGES}

${PKGR} -y install ${PACKAGES}

ln -sf ${RPM_BUILD_DIR} /root/rpmbuild
mkdir -p ${SOURCES} ${WORKSPACE} ${OUTPUT} ${RPM_BUILD_DIR}/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

# Fix up things so that things work fine and do not break while building
# Ensures required default repos as well

if ((RHEL > 0 && RHEL <= 7)); then
  patch /usr/bin/yum-builddep --forward /tmp/yum-builddep.patch
  # because we patched yum, versionlock ше:
  yum -y install yum-plugin-versionlock
  yum versionlock yum-utils
fi

if (( RHEL == 8 )); then
  dnf config-manager --enable powertools
fi

if (( RHEL >= 9 )); then
  dnf config-manager --enable crb
fi

if test -f /etc/dnf/dnf.conf; then
  sed -i 's@best=True@best=0@' /etc/dnf/dnf.conf
fi

${PKGR} -y clean all && rm -rf /tmp/* && rm -rf /var/cache/*

# fix up /usr/bin/build with the right packager
sed -i -r "s@^PKGR=yum@PKGR=${PKGR}@" /usr/bin/build