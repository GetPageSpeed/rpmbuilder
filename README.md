# RPM build containers for RedHat-based various distros

[![CI](https://github.com/GetPageSpeed/rpmbuilder/actions/workflows/dockerbuild.yml/badge.svg)](https://github.com/GetPageSpeed/rpmbuilder/actions/workflows/dockerbuild.yml) [![Docker Pulls](https://img.shields.io/docker/pulls/getpagespeed/rpmbuilder.svg)](https://hub.docker.com/r/getpagespeed/rpmbuilder/)

This is different from upstream because:

* it allows for faster-failed builds: a failed build can be detected early through building SRPM first, as well as optional `rpmlint` checks. In the upstream docker image, a failed build will have an exit status code of 0, so CI tools will not be able to detect failed builds to begin with.
* a patch is applied to `yum-builddep` to prevent unnecessary enablement of `-source` repos, to facilitate faster builds.
, the patch for `yum-builddep` to NOT enable source repos if .spec file is used (fixes a bug)

### Available versions

Available versions can be located by visiting [Docker Hub Repository](https://hub.docker.com/r/getpagespeed/rpmbuilder/tags/).

### Fetch image

For example, to use RHEL 7 based image:

```bash
BUILDER_VERSION=el7
docker pull getpagespeed/rpmbuilder:${BUILDER_VERSION}
```

Most images are tagged with the `dist` RPM tag, so you can use `el7`, `el8`, 
`fc38` etc.

### Run
In this example `SOURCE_DIR` contains the `.spec` file and sources for the the RPM we are building.

```bash
# set env variables for convenience
SOURCE_DIR=$(pwd)/sources
OUTPUT_DIR=$(pwd)/output

# create a output directory
mkdir -p ${OUTPUT_DIR}

# make SELinux happy
chcon -Rt svirt_sandbox_file_t ${OUTPUT_DIR} ${SOURCE_DIR}

# build rpm
docker run -v ${SOURCE_DIR}:/sources -v ${OUTPUT_DIR}:/output getpagespeed/rpmbuilder:${BUILDER_VERSION}
```

The output files will be available in `OUTPUT_DIR`.

#### Custom run

* You may pass `RPMLINT=1` for failing on `rpmlint` checks (pedantic way of producing quality RPMs)
* You may pass `SRPM_ONLY=1` for only fast checks of particular file's build-ability

###  Debugging
If you are creating a spec file, it is often useful to have a clean room debugging environment. You can achieve this by using the following command.

```bash
docker run --rm -it --entrypoint bash \
    -v ${SOURCE_DIR}:/sources \
    -v ${OUTPUT_DIR}:/output \
    getpagespeed/rpmbuilder:${BUILDER_VERSION}
```
This command will drop you into a bash shell within the container. From here, you can execute `build` to build the spec file. You can also iteratively modify the specfile and re-run `build`.

## Volumes
The following volumes can be mounted from the host.

| Volume  | Description |
| :------------ | :------------ |
| /sources | Source to build RPM from |
| /output | Output directory where all built RPMs and SRPMs are extracted to |
| /root/rpmbuild | rpmbuild directory for debugging etc |
