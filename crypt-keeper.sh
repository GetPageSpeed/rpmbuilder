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
    # Last EPEL is 9 so far:
    RELEASE_EPEL=${2-9}

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
    ASSETS=${ROOT}/assets
    DOCKERFILE=${ROOT}/Dockerfile
    rm -rf "${ROOT}" && mkdir -p "${ROOT}"

    # prepare files
    cp -R ./assets ${ROOT}/.
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
    if [[ "${DISTRO}" = "opensuse" ]]; then FROM_DISTRO="opensuse/leap"; fi
    cat > ${DOCKERFILE} << EOF
FROM ${FROM_DISTRO}:${FROM_RELEASE_TAG}
MAINTAINER "Danila Vershinin" <info@getpagespeed.com>

ENV WORKSPACE=${WORKSPACE} \\
    SOURCES=${SOURCES} \\
    OUTPUT=${OUTPUT} \\
    RPM_BUILD_DIR=${RPM_BUILD_DIR}

ADD ./assets/build /usr/bin/build
ADD ./assets/rpmlint.config /etc/rpmlint/config
ADD ./assets/transient/* /tmp/

RUN DISTRO=${DISTRO} RELEASE=${RELEASE} RELEASE_EPEL=${RELEASE_EPEL} /tmp/setup.sh

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
    # Ensure buildx is set up and ready for multi-architecture builds
    docker buildx create --use --name multiarch-builder --driver docker-container || true
    # Build and load amd64 architecture image locally
    echo "Building amd64 architecture image for ${DISTRO}-${VERSION}..."
    cd "${DISTRO}/${VERSION}" \
        && docker buildx build --platform linux/amd64 \
        --load \
        -t "$(docker-image-name ${DISTRO} ${VERSION})" \
        -t "$(docker-image-alt-name ${DISTRO} ${VERSION})" .

    # Build and load arm64 architecture image locally
    echo "Building arm64 architecture image for ${DISTRO}-${VERSION}..."
    docker buildx build --platform linux/arm64 \
        --load \
        -t "$(docker-image-name ${DISTRO} ${VERSION})" \
        -t "$(docker-image-alt-name ${DISTRO} ${VERSION})" .

    cd -
}

function push() {
    DISTRO=${1}
    VERSION=${2}
    # Generate the main and alternate tags for the multi-architecture image
    MAIN_TAG="$(docker-image-name ${DISTRO} ${VERSION})"
    ALT_TAG="$(docker-image-alt-name ${DISTRO} ${VERSION})"

    # Combine and push multi-architecture manifest with both tags
    echo "Combining and pushing multi-architecture image with multiple tags..."
    docker buildx imagetools create \
      --tag "${MAIN_TAG}" \
      --tag "${ALT_TAG}" \
      "${MAIN_TAG}" \
      "${ALT_TAG}"

    # Push the multi-architecture manifest to the Docker registry under all tags
    echo "Pushing multi-architecture image under all tags..."
    docker push "${MAIN_TAG}"
    docker push "${ALT_TAG}"

    echo "Multi-architecture image has been pushed successfully with tags: ${MAIN_TAG} and ${ALT_TAG}."
}


function test() {
    # Test build
    DISTRO=${1}
    VERSION=${2}
    docker run --rm --platform linux/amd64 -v $(pwd)/tests/hello:/sources $(docker-image-name ${DISTRO} ${VERSION}) build
}

case "$1" in
    generate|build|push|test)
        if [ "$2" == "all" ]; then
            map-all $1
        else
            $1 $2 $3
        fi ;;
esac
