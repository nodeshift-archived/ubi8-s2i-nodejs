#!/bin/bash

set -ex

yum install --disableplugin=subscription-manager -y --setopt=tsflags=nodocs nss_wrapper python2

# Ensure git uses https instead of ssh for NPM install
# See: https://github.com/npm/npm/issues/5257
echo -e "Setting git config rules"
git config --system url."https://github.com".insteadOf git@github.com:
git config --global url."https://github.com".insteadOf ssh://git@github.com
git config --system url."https://".insteadOf git://
git config --system url."https://".insteadOf ssh://
git config --list

ls /opt/app-root
yum remove -y nodejs
yum install -y /opt/app-root/rhoar-nodejs-${NODE_VERSION}-1.el8.x86_64.rpm
yum install -y /opt/app-root/npm-${NPM_VERSION}-1.${NODE_VERSION}.1.el8.x86_64.rpm
export PYTHON=`which python2`

rpm -V nss_wrapper
yum clean all -y
ldconfig

# Make sure npx is available
if [ ! -h /usr/bin/npx ] ; then
  ln -s /usr/lib/node_modules/npm/bin/npx-cli.js /usr/bin/npx
fi

echo "---> Setting directory write permissions"
fix-permissions /opt/app-root

# Delete NPM things that we don't really need (like tests) from node_modules
find /usr/local/lib/node_modules/npm -name test -o -name .bin -type d | xargs rm -rf

# Clean up the stuff we downloaded
yum clean all -y
