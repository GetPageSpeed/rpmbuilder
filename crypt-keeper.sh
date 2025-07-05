#!/usr/bin/env bash
set -exo pipefail
DOCKER_REGISTRY_USER=getpagespeed

declare -A DISTRO_DISTS=( [centos]=el [fedora]=fc [amazonlinux]=amzn [opensuse]=sles )

function generate() {
    SOURCES=${SOURCES-/sources}
    OUTPUT=${OUTPUT-/output}
    WORKSPACE=${WORKSPACE-/workspace}
    RPM_BUILD_DIR=${RPM_BUILD_DIR-/rpmbuild}

    DISTRO=${1-fedora}
    RELEASE=${2-latest}
    # Last EPEL is 10 so far:
    RELEASE_EPEL=${2-10}

    if [[ "$DISTRO" == "amazonlinux" ]]; then
        case "$RELEASE" in
        2)
           RELEASE_EPEL=7
           ;;
        2023)
           RELEASE_EPEL=
           ;;
        *)
           RELEASE_EPEL=7
           ;;
        esac
    fi

    ROOT=$(pwd)/${DISTRO}/${RELEASE}/
    # shellcheck disable=SC2034
    ASSETS=${ROOT}/assets
    DOCKERFILE=${ROOT}/Dockerfile
    rm -rf "${ROOT}" && mkdir -p "${ROOT}"

    # prepare files
    cp -R ./assets "${ROOT}"/.
    # cp LICENCE README.md

    # header
    FROM_DISTRO="${DISTRO}"
    FROM_RELEASE_TAG="${RELEASE}"
    # Rocky Linux vs Oracle Linux. The selinux-policy in Oracle Linux has "bad" release
    # Instead of 3.14.3-67.el8, it is  3.14.3-67.0.1.el8
    # This makes %_selinux_policy_version usage cause issues with -selinux packages
    # Rocky Linux is closer to upstream in these regards and no issues, so we use it.
    if [[ "${DISTRO}" = "centos" ]] && [[ "$RELEASE" -eq 7 ]]; then
      FROM_DISTRO="getpagespeed/lts"
      FROM_RELEASE_TAG="el7"
    fi
    if [[ "${DISTRO}" = "centos" ]] && [[ "$RELEASE" -eq 8 ]]; then FROM_DISTRO="rockylinux/rockylinux"; fi
    if [[ "${DISTRO}" = "centos" ]] && [[ "$RELEASE" -eq 9 ]]; then FROM_DISTRO="rockylinux/rockylinux"; fi
    if [[ "${DISTRO}" = "centos" ]] && [[ "$RELEASE" -eq 10 ]]; then
      FROM_DISTRO="almalinux/almalinux"
      FROM_RELEASE_TAG="10"
    fi
    if [[ "${DISTRO}" = "opensuse" ]]; then FROM_DISTRO="opensuse/leap"; fi
    cat > "${DOCKERFILE}" << EOF
FROM ${FROM_DISTRO}:${FROM_RELEASE_TAG}
LABEL maintainer="Danila Vershinin <info@getpagespeed.com>"

ENV WORKSPACE=${WORKSPACE} \\
    SOURCES=${SOURCES} \\
    OUTPUT=${OUTPUT} \\
    RPM_BUILD_DIR=${RPM_BUILD_DIR}

ADD ./assets/build /usr/bin/build
ADD ./assets/rpmlint.config /etc/rpmlint/config
ADD ./assets/transient/* /tmp/

RUN DISTRO=${DISTRO} RELEASE=${RELEASE} RELEASE_EPEL=${RELEASE_EPEL} /tmp/setup.sh

# We create images on schedule to facilitate faster builds that do not need to fetch meta on every build
# but we still need to ensure that no metadata is cached for the GetPageSpeed repos to properly detect
# dependencies and whether packages need to be built at all
# Also this runs in a separate step to ensure that the base image goes into its own layer
RUN /usr/bin/pkgr -y clean all && rm -rf /tmp/* && rm -rf /var/cache/* && /usr/bin/pkgr --disablerepo "getpagespeed*" makecache

VOLUME ["\${SOURCES}", "\${OUTPUT}"]

CMD ["build"]
EOF
}

function map-all() {
    while IFS=' ' read -r -a input; do
        $1 "${input[0]}" "${input[1]}"
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
    MAIN_TAG="$(docker-image-name "${DISTRO}" "${VERSION}")"
    ALT_TAG="$(docker-image-alt-name "${DISTRO}" "${VERSION}")"
    # Ensure buildx is set up and ready for multi-architecture builds
    docker buildx create --use --name multiarch-builder --driver docker-container || true
    cd "${DISTRO}/${VERSION}" && docker buildx build --platform linux/amd64,linux/arm64 --push -t "${MAIN_TAG}" -t "${ALT_TAG}" .
    cd -
}

function push() {
    echo "Nothing to do, pushed in the build step"
}


function test() {
    # Test build
    DISTRO=${1}
    VERSION=${2}
    echo "Testing x86_64 build for ${DISTRO}-${VERSION}"
    docker run --rm --platform linux/amd64 -v "$(pwd)"/tests/hello:/sources "$(docker-image-name "${DISTRO}" "${VERSION}")" build
    echo "Done testing x86_64 build for ${DISTRO}-${VERSION}"
}

case "$1" in
    generate|build|push|test)
        if [ "$2" == "all" ]; then
            map-all "$1"
        else
            "$1" "$2" "$3"
        fi ;;
esac
