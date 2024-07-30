#!/bin/bash
# Basically fixes up GetPageSpeed repo usage from these images
# by removing plugin and setting up the desired user-agent
# Runs after installation of release package
shopt -s extglob
RHEL=$(rpm -E 0%{?rhel})
# removes leading zeros, e.g. 07 becomes 0, but 0 stays 0
RHEL=${RHEL##+(0)}

SLES=$(rpm -E 0%{?suse_version})
# removes leading zeros, e.g. 07 becomes 0, but 0 stays 0
SLES=${SLES##+(0)}

if [[ $(rpm -E %{amzn}) == 2 ]]; then
  sed -i "s@redhat/7@amzn/2@g" /etc/yum.repos.d/getpagespeed-extras.repo
fi

if ((SLES > 0)); then
# 1500 => 15
SLES_MAJOR=${SLES::-2}
echo "%dist .sles${SLES_MAJOR}" > /etc/rpm/macros.custom
fi

# if RHEL exactly 7, fix SCLO repos:
if ((RHEL == 7)); then
  # disable mirrorlist, enable and replace entire line with baseurl (only one line in the file):
  VAULT_VER="7.9.2009"
  SCLO_BASE_NEW_URL="https://vault.epel.cloud/${VAULT_VER}/sclo/x86_64/sclo/"
  sed -i.orig -e '/mirrorlist=/d' \
    -e "0,/baseurl=/s@.*baseurl=.*@baseurl=${SCLO_BASE_NEW_URL}@" \
    /etc/yum.repos.d/CentOS-SCLo-scl.repo
  SCLO_RH_NEW_URL="https://vault.epel.cloud/${VAULT_VER}/sclo/x86_64/rh/"
  echo "New SCLO RH URL: ${SCLO_RH_NEW_URL}"
  sed -i.orig -e '/mirrorlist=/d' \
    -e "0,/^#\?baseurl=/s@^#\?baseurl=.*@baseurl=${SCLO_RH_NEW_URL}@" \
    /etc/yum.repos.d/CentOS-SCLo-scl-rh.repo
fi

if ((RHEL > 0 && RHEL <= 7)); then
  # set up desired user-agent by patching yum
  sed -ri 's@^default_grabber\.opts\.user_agent\s+.*@default_grabber.opts.user_agent = "XXXXXXXXXX"@' \
    /usr/lib/python2.*/site-packages/yum/__init__.py
  # remove our plugin
  rm -rf /usr/lib/yum-plugins/getpagespeed.py* /etc/yum/pluginconf.d/getpagespeed.conf
  # because we patched yum, versionlock it:
  # because we patched yum, versionlock ше:
  yum -y install yum-plugin-versionlock
  yum versionlock yum yum-utils
fi

# for any DNF client, copy in custom user-agent plugin for DNF
# and overwrite our plugin in the process
DNF_PLUGINS_DIR="/usr/lib/python*/site-packages/dnf-plugins"
if test -f "/usr/bin/dnf"; then
  for D in $DNF_PLUGINS_DIR; do
    if test -d "$D"; then
      \cp -f /tmp/user-agent.py $D/getpagespeed.py;
    fi
  done
fi
