#!/bin/bash
# Basically fixes up GetPageSpeed repo usage from these images
# by removing plugin and setting up the desired user-agent
# Runs after installation of release package
shopt -s extglob
RHEL=$(rpm -E 0%{?rhel})
# removes leading zeros, e.g. 07 becomes 0, but 0 stays 0
RHEL=${RHEL##+(0)}

if ((RHEL >= 0 && RHEL <= 7)); then
  # set up desired user-agent by patching yum
  sed -ri 's@^default_grabber\.opts\.user_agent\s+.*@default_grabber.opts.user_agent = "rpmbuilder"@' /usr/lib/python2.*/site-packages/yum/__init__.py
  # remove our plugin
  rm -rf /usr/lib/yum-plugins/getpagespeed.py* /etc/yum/pluginconf.d/getpagespeed.conf
  # because we patched yum, versionlock it:
  # because we patched yum, versionlock ше:
  yum -y install yum-plugin-versionlock
  yum versionlock yum yum-utils

if [[ $(rpm -E %{amzn}) == 2 ]]; then
  sed -i "s@redhat/7@amzn/2@g" /etc/yum.repos.d/getpagespeed-extras.repo
fi

# for any DNF client, copy in custom user-agent plugin for DNF
# and overwrite our plugin in the process
DNF_PLUGINS_DIR="/usr/lib/python*/site-packages/dnf-plugins"
if test -f "/usr/bin/dnf"; then
  for D in $DNF_PLUGINS_DIR; do
    if test -d "$D"; then
      \cp -f /tmp/rpmbuilder-ua.py $D/getpagespeed.py;
    fi
  done
fi
