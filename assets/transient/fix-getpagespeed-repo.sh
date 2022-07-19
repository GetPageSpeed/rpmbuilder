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
cat << 'EOF' > /etc/zypp/repos.d/repo-getpagespeed-extras.repo
[repo-getpagespeed-extras-noarch]
name=GetPageSpeed Extras Repository noarch
enabled=1
autorefresh=1
baseurl=https://extras.getpagespeed.com/sles/$releasever/noarch/

[repo-getpagespeed-extras]
name=GetPageSpeed Extras Repository
enabled=1
autorefresh=1
baseurl=https://extras.getpagespeed.com/sles/$releasever/x86_64/
EOF
zypper -n install axel
axel https://extras.getpagespeed.com/RPM-GPG-KEY-GETPAGESPEED
rpm --import RPM-GPG-KEY-GETPAGESPEED
# 1500 => 15
SLES_MAJOR=${SLES::-2}
echo "%dist .sles${SLES_MAJOR}" > /etc/rpm/macros.custom
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

if ((RHEL > 0 && RHEL >= 9)); then
  dnf -y install crypto-policies-scripts
  echo 'Fixing crypto policy to match with our key'
  update-crypto-policies --set DEFAULT:SHA1 ||:
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
