#!/usr/bin/env bash
set -eo pipefail
DOCKER_REGISTRY_USER=getpagespeed

declare -A DISTRO_DISTS=( [centos]=el [fedora]=fc [amazonlinux]=amzn [opensuse]=sles )

function generate() {
    SOURCES=${SOURCES-/sources}
    OUTPUT=${OUTPUT-/output}
    WORKSPACE=${WORKSPACE-/workspace}
    RPM_BUILD_DIR=${RPM_BUILD_DIR-/rpmbuild}

    DISTRO=${1-fedora}
    RELEASE=${2-latest}
    # Last EPEL is 8 so far:
    RELEASE_EPEL=${2-8}

    if [[ "$DISTRO" == "amazonlinux" ]]; then
        case "$RELEASE" in
        2)
           RELEASE_EPEL=7
           ;;
        *)
           RELEASE_EPEL=7
           ;;
        esac
    fi

    ROOT=$(pwd)/${DISTRO}/${RELEASE}/
    ASSETS=${ROOT}/assets
    DOCKERFILE=${ROOT}/Dockerfile
    rm -rf ${ROOT} && mkdir -p ${ROOT}

    # prepare files
    cp -R ./assets ${ROOT}/.
    # cp LICENCE README.md
    YUM="yum"
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
              YUM="dnf";
              CONFIG_MANAGER="dnf config-manager"
              PACKAGES="'dnf-command(builddep)' gcc rpmlint git rpm-build rpmdevtools tar gcc-c++ redhat-rpm-config redhat-release which xz sed make bzip2 gzip gcc unzip shadow-utils diffutils cpio bash gawk rpm-build info patch util-linux findutils grep python27 lua libarchive"
            fi
            # @buildsys-build is to better "emulate" mock by preinstalling gcc thus preventing devtoolset-* lookup for "BuildRequires: gcc"
            # devtoolset-8 is for faster CI builds of packages that want to use it
            ;;
        fedora|mageia)
            YUM="dnf";
            # Just a dummy pre-install to simplify RUN step below
            PRE_PRE_PACKAGES="https://extras.getpagespeed.com/release-latest.rpm"
            PRE_PACKAGES="'dnf-command(builddep)'"
            PACKAGES="'dnf-command(builddep)' gcc rpmlint git rpm-build rpmdevtools tar gcc-c++ redhat-rpm-config which xz sed make bzip2 gzip gcc unzip shadow-utils diffutils cpio bash gawk rpm-build info patch util-linux findutils grep python27 lua libarchive"
            ;;
        opensuse)
            YUM="dnf"
            # "zypper --non-interactive"
            # Just a dummy pre-install to simplify RUN step below
            PRE_PRE_PACKAGES="dnf"
            PRE_PACKAGES="'dnf-command(builddep)'"
            PACKAGES="'dnf-command(builddep)' gcc rpmlint git rpm-build rpmdevtools tar gcc-c++ rpm-config-SUSE which xz sed make bzip2 gzip gcc unzip diffutils cpio bash gawk rpm-build info patch util-linux findutils grep lua"
            ;;
    esac
    # header
    FROM_DISTRO="${DISTRO}"
    # Rocky Linux vs Oracle Linux. The selinux-policy in Oracle Linux has "bad" release
    # Instead of 3.14.3-67.el8, it is  3.14.3-67.0.1.el8
    # This makes %_selinux_policy_version usage cause issues with -selinux packages
    # Rocky Linux is closer to upstream in these regards and no issues, so we use it.
    if [[ "${DISTRO}" = "centos" ]] && [[ "$RELEASE" -ge 8 ]]; then FROM_DISTRO="rockylinux/rockylinux"; fi
    if [[ "${DISTRO}" = "opensuse" ]]; then FROM_DISTRO="opensuse/leap"; fi
    cat > ${DOCKERFILE} << EOF
FROM ${FROM_DISTRO}:${RELEASE}
MAINTAINER "Danila Vershinin" <info@getpagespeed.com>

ENV WORKSPACE=${WORKSPACE} \\
    SOURCES=${SOURCES} \\
    OUTPUT=${OUTPUT} \\
    RPM_BUILD_DIR=${RPM_BUILD_DIR}

# this is required to disable source repos that yum-builddep unnecessarily enables. this is no longer required. see patch below
# RUN rm -rf /etc/yum.repos.d/{CentOS-Sources.repo,CentOS-Sources.repo} $(test "$EXTRA_RELEASES" && echo "&& yum -y install ${EXTRA_RELEASES}")
# RUN [ -f "/etc/yum.repos.d/CentOS-SCLo-scl-rh.repo" ] && sed -i '/centos-sclo-rh-source/,//d' /etc/yum.repos.d/CentOS-SCLo-scl-rh.repo
# RUN [ -f "/etc/yum.repos.d/CentOS-SCLo-scl.repo" ] && sed -i '/centos-sclo-sclo-source/,//d' /etc/yum.repos.d/CentOS-SCLo-scl.repo

ADD ./assets/build /usr/bin/build
ADD ./assets/rpmlint.config /etc/rpmlint/config
# patch for yum-builddep to NOT enable source repos if .spec file is used (fixes a bug)
ADD ./assets/yum-builddep.patch /tmp/yum-builddep.patch
ADD ./assets/rpmbuilder-ua.py /tmp/rpmbuilder-ua.py
ADD ./assets/distfix.sh /tmp/distfix.sh
ADD ./assets/post_distfix.sh /tmp/post-distfix.sh
ADD ./assets/fix-getpagespeed-repo.sh /tmp/fix-getpagespeed-repo.sh

RUN /tmp/distfix.sh \\
    && ${YUM} -y install ${PRE_PRE_PACKAGES} \\
    && /tmp/fix-getpagespeed-repo.sh \\
    && ${YUM} -y install ${PRE_PACKAGES} \\
    && ${YUM} -y install ${PACKAGES} \\
    && ln -sf \${RPM_BUILD_DIR} /root/rpmbuild \\
    && mkdir -p \${SOURCES} \\
        \${WORKSPACE} \\
        \${OUTPUT} \\
        \${RPM_BUILD_DIR}/{BUILD,RPMS,SOURCES,SPECS,SRPMS} \\
    && /tmp/post-distfix.sh \\
    && ${YUM} -y clean all && rm -rf /tmp/* && rm -rf /var/cache/*

VOLUME ["\${SOURCES}", "\${OUTPUT}"]

CMD ["build"]
EOF
}

function map-all() {
    while IFS=' ' read -r -a input; do
        $1 ${input[0]} ${input[1]}
    done < ./defaults
}

function docker-image-name() {
    DISTRO=${1}
    VERSION=${2}
    echo -n "${DOCKER_REGISTRY_USER}/rpmbuilder:${DISTRO/\//-}-${VERSION}"
}

function docker-image-alt-name() {
    DISTRO=${1}
    VERSION=${2}
    DIST=${DISTRO_DISTS[$DISTRO]}
    echo -n "${DOCKER_REGISTRY_USER}/rpmbuilder:${DIST}${VERSION}"
}

function build() {
    DISTRO=${1}
    VERSION=${2}
    cd "${DISTRO}/${VERSION}" \
        && docker build -t $(docker-image-name ${DISTRO} ${VERSION}) -t $(docker-image-alt-name ${DISTRO} ${VERSION}) .
    cd -
}

function push() {
    DISTRO=${1}
    VERSION=${2}
    docker push --all-tags "${DOCKER_REGISTRY_USER}/rpmbuilder" # $(docker-image-name ${DISTRO} ${VERSION})
}

case "$1" in
    generate|build|push)
        if [ "$2" == "all" ]; then
            map-all $1
        else
            $1 $2 $3
        fi ;;
esac
