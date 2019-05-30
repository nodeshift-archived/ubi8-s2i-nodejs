#!/bin/bash
#
# The 'run' performs a simple test that verifies that STI image.
# The main focus here is to excersise the STI scripts.
#
# IMAGE_NAME specifies a name of the candidate image used for testing.
# The image has to be available before this script is executed.
#
BUILDER=${BUILDER}
NODE_VERSION=${NODE_VERSION}

APP_IMAGE="$(echo ${BUILDER} | cut -f 1 -d':')-testapp"

test_dir=`dirname ${BASH_SOURCE[0]}`
image_dir="${test_dir}/.."
cid_file=`date +%s`$$.cid

# Since we built the candidate image locally, we don't want S2I attempt to pull
# it from Docker hub
s2i_args="--pull-policy never "

# TODO: This should be part of the image metadata
test_port=8080

image_exists() {
  docker inspect $1 &>/dev/null
}

container_exists() {
  image_exists $(cat $cid_file)
}

container_ip() {
  docker inspect --format="{{ .NetworkSettings.IPAddress }}" $(cat $cid_file)
}

container_logs() {
  docker logs $(cat $cid_file)
}

run_s2i_build() {
  echo "Running s2i build ${s2i_args} ${test_dir}/test-app ${BUILDER} ${APP_IMAGE}"
  s2i build ${s2i_args} --exclude "(^|/)node_modules(/|$)" ${test_dir}/test-app ${BUILDER} ${APP_IMAGE}
}

run_s2i_build_incremental() {
  echo "Running s2i build ${s2i_args} ${test_dir}/test-app ${BUILDER} ${APP_IMAGE} --incremental=true"
  s2i build ${s2i_args} --exclude "(^|/)node_modules(/|$)" ${test_dir}/test-app ${BUILDER} ${APP_IMAGE} --incremental=true
}

prepare() {
  if ! image_exists ${BUILDER}; then
    echo "ERROR: The image ${BUILDER} must exist before this script is executed."
    exit 1
  fi
}

run_test_application() {
  echo "Starting test application ${APP_IMAGE}..."
  docker run --cidfile=${cid_file} -p ${test_port}:${test_port} $1 ${APP_IMAGE}
}

cleanup() {
  if [ -f $cid_file ]; then
    if container_exists; then
      cid=$(cat $cid_file)
      docker stop $cid
      exit_code=`docker inspect --format="{{ .State.ExitCode }}" $cid`
      echo "Container exit code = $exit_code"
      # Only check the exist status for non DEV_MODE
      if [ "$1" == "false" ] &&  [ "$exit_code" != "222" ] ; then
        echo "ERROR: The exist status should have been 222."
        exit 1
      fi
    fi
  fi
  cids=`ls -1 *.cid 2>/dev/null | wc -l`
  if [ $cids != 0 ]
  then
    rm *.cid
  fi
}

check_result() {
  local result="$1"
  if [[ "$result" != "0" ]]; then
    echo "STI image '${BUILDER}' test FAILED (exit code: ${result})"
    cleanup
    exit $result
  fi
}

wait_for_cid() {
  local max_attempts=10
  local sleep_time=1
  local attempt=1
  local result=1
  while [ $attempt -le $max_attempts ]; do
    [ -f $cid_file ] && [ -s $cid_file ] && break
    echo "Waiting for container start..."
    attempt=$(( $attempt + 1 ))
    sleep $sleep_time
  done
}

test_s2i_usage() {
  echo "Testing 's2i usage'..."
  s2i usage ${s2i_args} ${BUILDER} &>/dev/null
}

test_docker_run_usage() {
  echo "Testing 'docker run' usage..."
  docker run ${BUILDER} &>/dev/null
}

test_connection() {
  echo "Testing HTTP connection..."
  local max_attempts=10
  local sleep_time=1
  local attempt=1
  local result=1
  while [ $attempt -le $max_attempts ]; do
    echo "Sending GET request to http://localhost:${test_port}/"
    response_code=$(curl -s -w %{http_code} -o /dev/null http://localhost:${test_port}/)
    status=$?
    if [ $status -eq 0 ]; then
      if [ $response_code -eq 200 ]; then
	result=0
      fi
      break
    fi
    attempt=$(( $attempt + 1 ))
    sleep $sleep_time
  done
  return $result
}

test_builder_node_version() {
  local run_cmd="node --version"
  local expected_version="v${NODE_VERSION}"

  echo "Checking nodejs runtime version ..."
  out=$(docker run ${BUILDER} /bin/bash -c "${run_cmd}")
  if ! echo "${out}" | grep -q "${expected_version}"; then
    echo "ERROR[/bin/bash -c "${run_cmd}"] Expected '${expected_version}', got '${out}'"
    return 1
  fi

  echo "Checking NPM_CONFIG_TARBALL environment variable"
  out=$(docker run ${BUILDER} /bin/bash -c 'echo $NPM_CONFIG_TARBALL')
  local expected_var="/usr/share/node/node-v${NODE_VERSION}-headers.tar.gz"
  if ! echo "${out}" | grep -q "${expected_var}"; then
    echo "ERROR[/bin/bash -c "${run_cmd}"] Expected '${expected_var}', got '${out}'"
    return 1
  fi
}

test_nss_wrapper() {
  read -d '' run_cmd <<-"HERE"
  echo 'danbev:x:1000:1000:danbev test:/home/danbev:/bin/false' > passwd &&
  LD_PRELOAD=libnss_wrapper.so NSS_WRAPPER_PASSWD=passwd NSS_WRAPPER_GROUP=group getent passwd danbev
HERE
  echo "Checking nss_wrapper ..."
  out=$(docker run ${BUILDER} /bin/bash -c "${run_cmd}" 2>&1)
  if echo "${out}" | grep -q "ERROR"; then
    echo "ERROR[/bin/bash -c "${run_cmd}"] '${out}'"
    return 1
  fi
}

test_node_version() {
  local run_cmd="node --version"
  local expected="v${NODE_VERSION}"

  echo "Checking nodejs runtime version ..."
  out=$(docker exec $(cat ${cid_file}) /bin/bash -c "${run_cmd}" 2>&1)
  if ! echo "${out}" | grep -q "${expected}"; then
    echo "ERROR[exec /bin/bash -c "${run_cmd}"] Expected '${expected}', got '${out}'"
    return 1
  fi
  out=$(docker exec $(cat ${cid_file}) /bin/sh -ic "${run_cmd}" 2>&1)
  if ! echo "${out}" | grep -q "${expected}"; then
    echo "ERROR[exec /bin/sh -ic "${run_cmd}"] Expected '${expected}', got '${out}'"
    return 1
  fi
}

test_directory_permissions() {
  local run_cmd="echo 'hello world' > public/index.html && cat public/index.html"
  local expected="hello world"

  echo "Checking directory writability ..."
  out=$(docker exec $(cat ${cid_file}) /bin/bash -c "${run_cmd}")
  if ! echo "${out}" | grep -q "${expected}"; then
    echo "ERROR[exec /bin/bash -c "${run_cmd}"] Expected '${expected}', got '${out}'"
    return 1
  fi
}

test_post_install() {
  local run_cmd="ls greeting.js"
  local expected="greeting.js"

  echo "Checking post install ..."
  out=$(docker exec $(cat ${cid_file}) /bin/bash -c "${run_cmd}")
  if ! echo "${out}" | grep -q "${expected}"; then
    echo "ERROR[exec /bin/bash -c "${run_cmd}"] Expected '${expected}', got '${out}'"
    return 1
  fi
}

test_development_dependencies() {
  local run_cmd="ls -d node_modules/tape"
  local expected="tape"

  echo "Checking development dependencies ..."
  out=$(docker exec $(cat ${cid_file}) /bin/bash -c "${run_cmd}")
  if ! echo "${out}" | grep -q "${expected}"; then
    echo "ERROR[exec /bin/bash -c "${run_cmd}"] Expected '${expected}', got '${out}'"
    return 1
  fi
}

test_no_development_dependencies() {
  local run_cmd="if [ -d node_modules/nodemon ] ; then echo 'exists' ; else echo 'not exists' ; fi"
  local expected="not exists"

  echo "Checking development dependencies not installed ..."
  out=$(docker exec $(cat ${cid_file}) /bin/bash -c "${run_cmd}")
  if ! echo "${out}" | grep -q "${expected}"; then
    echo "ERROR[exec /bin/bash -c "${run_cmd}"] Expected '${expected}', got '${out}'"
    return 1
  fi
}

test_symlinks() {
  local run_cmd="test -h node_modules/.bin/tape; echo $?"
  local expected="0"

  echo "Checking symlinks ..."
  out=$(docker exec $(cat ${cid_file}) /bin/bash -c "${run_cmd}")
  if ! echo "${out}" | grep -q "${expected}"; then
    echo "ERROR[exec /bin/bash -c "${run_cmd}"] Expected '${expected}', got '${out}'"
    return 1
  fi
}

test_git_configuration() {
  local run_cmd="git config -l"
  local expected="url.https://github.com.insteadof=git@github.com:
url.https://.insteadof=ssh://
url.https://github.com.insteadof=ssh://git@github.com"

  echo "Checking git configuration ..."
  out=$(docker exec $(cat ${cid_file}) /bin/bash -c "${run_cmd}")
  if ! echo "${out}" | grep -q "${expected}"; then
    echo "ERROR[exec /bin/bash -c "${run_cmd}"] Expected '${expected}', got '${out}'"
    return 1
  fi
}

test_git_clone() {
  local run_cmd="git clone https://github.com/nodeshift/world && ls world/index.js"
  local expected="world/index.js"

  echo "Checking git clone ..."
  out=$(docker exec $(cat ${cid_file}) /bin/bash -c "${run_cmd}")
  if ! echo "${out}" | grep -q "${expected}"; then
    echo "ERROR[exec /bin/bash -c "${run_cmd}"] Expected '${expected}', got '${out}'"
    return 1
  fi
}

test_image_usage_label() {
  local expected="s2i build . nodeshift/ubi8-s2i-nodejs myapp"
  local prod_expected="s2i build . rhoar-nodejs/nodejs-12-rhel8 myapp"
  local failed=false
  echo "Checking image usage label ..."
  out=$(docker inspect --format '{{ index .Config.Labels "usage" }}' $BUILDER)

  if ! echo "${out}" | grep -q "${expected}"; then
    if echo "${out}" | grep -q "${prod_expected}"; then
      return 0;
    else
      echo "ERROR[docker inspect --format \"{{ index .Config.Labels \"usage\" }}\"] Expected '${prod_expected}', got '${out}'"
      return 1
    fi
    echo "ERROR[docker inspect --format \"{{ index .Config.Labels \"usage\" }}\"] Expected '${expected}', got '${out}'"
    return 1
  fi
}

test_scl_nodejs_exists() {
  local run_cmd="rpm -qa | grep ^rh-nodejs"
  local expected=""
  echo "Checking if SCL nodejs packages exists..."
  out=$(docker exec $(cat ${cid_file}) /bin/bash -c "${run_cmd}")
  if [ ! "$out" == "$expected" ]; then
    echo "ERROR[exec /bin/bash -c "${run_cmd}"] Expected '${expected}', got '${out}'"
    return 1
  fi
}

prepare
test_image_usage_label
check_result $?

test_builder_node_version
check_result $?

test_nss_wrapper
check_result $?

# Build the application image twice to ensure the 'save-artifacts' and
# 'restore-artifacts' scripts are working properly
prepare
run_s2i_build
check_result $?

run_s2i_build_incremental
check_result $?

# Verify the 'usage' script is working properly when running the base image with 's2i usage ...'
test_s2i_usage
check_result $?

# Verify the 'usage' script is working properly when running the base image with 'docker run ...'
test_docker_run_usage
check_result $?

# Verify that the HTTP connection can be established to test application container
run_test_application &

# Wait for the container to write it's CID file
wait_for_cid

test_directory_permissions
check_result $?

test_post_install
check_result $?

test_node_version
check_result $?

test_connection
check_result $?

test_git_configuration
check_result $?

test_git_clone
check_result $?

echo "Testing DEV_MODE=false (default)"
logs=$(container_logs)
echo ${logs} | grep -q DEV_MODE=false
check_result $?
echo ${logs} | grep -q NODE_ENV=production
check_result $?
echo ${logs} | grep -q DEBUG_PORT=5858
check_result $?
test_no_development_dependencies
check_result $?
# The argument to clean up is the DEV_MODE
cleanup false

run_test_application "-e DEV_MODE=true" &
wait_for_cid
echo "$(cat ${cid_file}) running"
echo "Testing DEV_MODE=true"
logs=$(container_logs)
echo ${logs} | grep -q DEV_MODE=true
check_result $?
echo "Testing NODE_ENV=development"
echo ${logs} | grep -q NODE_ENV=development
check_result $?
echo "Testing DEBUG_PORT=5858"
echo ${logs} | grep -q DEBUG_PORT=5858
check_result $?
# # Ensure that we install dev dependencies in dev mode
sleep 10
echo "Testing dev dependencies"
test_development_dependencies
check_result $?
echo "Testing symlinks"
test_symlinks
check_result $?

test_scl_nodejs_exists
check_result $?

# The argument to clean up is the DEV_MODE
cleanup true
if image_exists ${APP_IMAGE}; then
  docker rmi -f ${APP_IMAGE}
  # echo "<><><><><><><><><><><> NOT CLEANING UP åå<><><><><><><><><><><>"
fi

echo "Success!"
