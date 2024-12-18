#!/bin/bash
shopt -s extglob
set -euxo pipefail
if test -f /etc/os-release; then
   . /etc/os-release
elif test -f /usr/lib/os-release; then
   . /usr/lib/os-release
fi

# Retry function: tries a command multiple times
retry() {
    local -r max_attempts="$1"
    shift
    local -r cmd="$@"
    local attempt=1
    while (( attempt <= max_attempts )); do
        echo "Attempt ${attempt} to run: ${cmd}"
        if ${cmd}; then
            return 0
        fi
        echo "Attempt ${attempt} failed. Waiting 5 seconds before retry..."
        sleep 5
        ((attempt++))
    done
    echo "All ${max_attempts} attempts failed for: ${cmd}"
    return 1
}

RHEL=$(rpm -E "0%{?rhel}")
# removes leading zeros, e.g. 07 becomes 0, but 0 stays 0
RHEL=${RHEL##+(0)}

AMZN=$(rpm -E "0%{?amzn}")
# removes leading zeros, e.g. 07 becomes 0, but 0 stays 0
AMZN=${AMZN##+(0)}

FEDORA=$(rpm -E "0%{?fedora}")
# removes leading zeros, e.g. 07 becomes 0, but 0 stays 0
FEDORA=${FEDORA##+(0)}

PKGR="yum"
CONFIG_MANAGER="yum-config-manager"
# yum-utils is provided by "dnf-utils" in recent OS versions, but it always brings up yum-config-manager
PACKAGES="rpm-build rpmdevtools yum-utils rpmlint"
echo "DISTRO: ${DISTRO}, RHEL: ${RHEL}, AMZN: ${AMZN}"
case "${DISTRO}" in
    amazonlinux|centos|cloudrouter*centos)
        # Amazon Linux 2023 does not support EPEL or EPEL-like repositories
        if [[ "$DISTRO" == "amazonlinux" ]] && [[ "$AMZN" -ge 2023 ]]; then
          echo "Amazon Linux 2023 does not support EPEL or EPEL-like repositories"
          PKGR="dnf";
          CONFIG_MANAGER="dnf config-manager"
          PRIMARY_REPO_PACKAGES="https://extras.getpagespeed.com/release-latest.rpm";
          PRE_PACKAGES="dnf-plugins-core"
          PACKAGES="dnf-plugins-core gcc rpmlint git rpm-build rpmdevtools tar gcc-c++ redhat-rpm-config which xz sed make bzip2 gzip gcc unzip shadow-utils diffutils cpio bash gawk rpm-build info patch util-linux findutils grep lua libarchive bc"
        else
          # The PRE_ packages are typically release files, and need to be installed in a separate step to build ones
          PRIMARY_REPO_PACKAGES="https://epel.cloud/pub/epel/epel-release-latest-${RELEASE_EPEL}.noarch.rpm https://extras.getpagespeed.com/release-latest.rpm";
          # in case either of URL-based RPMs are not available with a 404, rpm simply installs one that is available
          # thus we need to list them once again in the second step
          SECONDARY_REPO_PACKAGES="epel-release getpagespeed-extras-release";
          PRE_PACKAGES="epel-release"
          # bypassing weird bug?
          # we do this whole concept of PRE_PRE because for amzn2 this release pkg is in our repo:
          if [[ ${RELEASE_EPEL} -le 7 ]]; then
            SECONDARY_REPO_PACKAGES="${SECONDARY_REPO_PACKAGES} centos-release-scl";
            # yum-plugin-versionlock required to freeze our patched version of yum-builddep script
            # we also freeze "yum" for keeping User-Agent hack
            PACKAGES="${PACKAGES} yum-plugin-versionlock bc"
          fi
          # CircleCI in EL6 sometimes fails (support claims it's due to lack of "official" git)
          # We threw latest git to our EL6 repo (clean Fedora rebuilt)
          PACKAGES="${PACKAGES} @buildsys-build git devtoolset-8-gcc-c++ devtoolset-8-binutils"
          if [[ ${RELEASE_EPEL} -ge 8 ]]; then
            PKGR="dnf";
            CONFIG_MANAGER="dnf config-manager"
            PACKAGES="dnf-plugins-core gcc rpmlint git rpm-build rpmdevtools tar gcc-c++ redhat-rpm-config redhat-release which xz sed make bzip2 gzip gcc unzip shadow-utils diffutils cpio bash gawk rpm-build info patch util-linux findutils grep lua libarchive bc"
          fi
          if [[ ${RELEASE_EPEL} -eq 8 ]]; then
            PACKAGES="${PACKAGES} python27"
          fi
          # no Python 2 in EL 8?
          # @buildsys-build is to better "emulate" mock by preinstalling gcc thus preventing devtoolset-* lookup for "BuildRequires: gcc"
          # devtoolset-8 is for faster CI builds of packages that want to use it
        fi
        ;;
    fedora|mageia)
        PKGR="dnf";
        # Just a dummy pre-install to simplify RUN step below
        PRIMARY_REPO_PACKAGES="https://extras.getpagespeed.com/release-latest.rpm"
        PRE_PACKAGES="dnf-plugins-core"
        # glibc-langpack-en is required to stop rpmlint from erroring like this: E: specfile-error LANGUAGE = (unset),
        PACKAGES="dnf-plugins-core gcc rpmlint git rpm-build rpmdevtools tar gcc-c++ redhat-rpm-config which xz sed make bzip2 gzip gcc unzip shadow-utils diffutils cpio bash gawk rpm-build info patch util-linux findutils grep lua libarchive glibc-langpack-en bc"
        # If Fedora 40 or prior, we need to install python2
        if [[ ${FEDORA} -le 40 ]]; then
          PACKAGES="${PACKAGES} python2"
        fi
        ;;
    opensuse)
        PKGR="dnf"
        # "zypper --non-interactive"
        # Just a dummy pre-install to simplify RUN step below
        PRIMARY_REPO_PACKAGES="https://extras.getpagespeed.com/release-latest.rpm"
        PRE_PACKAGES="dnf-plugins-core"
        PACKAGES="dnf-plugins-core gcc rpmlint git rpm-build rpmdevtools tar gcc-c++ rpm-config-SUSE which xz sed make bzip2 gzip gcc unzip diffutils cpio bash gawk rpm-build info patch util-linux findutils grep lua spectool bc"
        ;;
esac

# Fix up base repos in a way that we can install any packages at all ...

if test -n "${ID-}"; then
  if [ "$ID" = "opensuse-leap" ]; then
      echo "Do something Leap specific"
      retry 5 zypper --non-interactive install dnf libdnf-repo-config-zypp
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
  retry 5 $PKGR -y install dnf-plugins-core
fi

# May be installed already
${PKGR} -y install ${PRIMARY_REPO_PACKAGES} || true
# if SECONDARY_REPO_PACKAGES is set, install them
if test -n "${SECONDARY_REPO_PACKAGES-}"; then
  retry 5 ${PKGR} -y install ${SECONDARY_REPO_PACKAGES}
fi

/tmp/fix-repos.sh

retry 5 ${PKGR} -y install ${PRE_PACKAGES}

retry 5 ${PKGR} -y install ${PACKAGES}

ln -sf ${RPM_BUILD_DIR} /root/rpmbuild
mkdir -p ${SOURCES} ${WORKSPACE} ${OUTPUT} ${RPM_BUILD_DIR}/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

# Fix up things so that things work fine and do not break while building
# Ensures required default repos as well

if ((RHEL > 0 && RHEL <= 7)); then
  patch /usr/bin/yum-builddep --forward /tmp/yum-builddep.patch
  # because we patched yum, versionlock ше:
  retry 5 yum -y install yum-plugin-versionlock
  retry 5 yum versionlock yum-utils
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

# Symlink packager command to /usr/bin/pkgr (yum or dnf)
# The build script uses /usr/bin/pkgr to install build dependencies
ln -sf /usr/bin/${PKGR} /usr/bin/pkgr
