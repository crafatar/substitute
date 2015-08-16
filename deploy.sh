#!/usr/bin/env bash

# exit on error
set -e

info() {
  tput setf 6 # yellow
  echo "> ${*}"
  tput sgr0
}

error() {
  tput setf 4 # red
  echo "> ${*}"
  tput sgr0
}

app="crafatar"
script="www.js"

# determine the script's location
this="$(which "${0}")"
whereami="$(cd "$( dirname "$(readlink "${this}" || echo "${this}")")"; pwd)"

deploy_dir="${whereami}/deploy"
nd_file="${deploy_dir}/next_deploy"

if [ ! -f "${nd_file}" ]; then
  echo "a" > "${nd_file}"
  info "WARNING: ${nd_file} did not exist, first deploy?"
fi

next_deploy="$(cat "${nd_file}")"
if [ -z "${next_deploy}" ]; then
  info "WARNING: ${nd_file} was empty"
  next_deploy="a"
fi

# can be changed to "rollback" later
mode="deploy"

start() {
  start_name="${1}"
  start_dir="${2}"
  port="${3}"
  info "Starting ${start_name}"
  env PORT="${port}" forever start --uid "${start_name}" -l "logs/forever.log" -o "${start_dir}/logs/out.log" -e "${start_dir}/logs/error.log" --workingDir "${start_dir}" --sourceDir "${start_dir}" -p "${start_dir}" -a --minUptime 9000 --killSignal SIGTERM "${script}" > /dev/null
}

stop() {
  stop_name="$1"
  if forever stop "${stop_name}" > /dev/null; then
    info "Stopped ${stop_name}."
  else
    info "Couldn't stop ${stop_name}. Maybe it was not running?"
  fi
}

is_running() {
  forever list --no-color | grep -v "STOPPED" | grep -q "${1}"
}

substitute() {
  deploy_app="${app}_${next_deploy}"

  if is_running "${deploy_app}"; then
    error "Looks like ${deploy_app} is already running"
    error "Please fix manually"
    return 1
  fi

  stop_char="a"
  port="3001"
  if [ "${next_deploy}" = "a" ]; then
    stop_char="b"
    port="3002"
  fi

  stop_app="${app}_${stop_char}"
  app_dir="${whereami}/${deploy_app}"

  if [  "${mode}" = "deploy" ]; then
    pushd "${app_dir}/"
    commit="origin/master"
    if [ -n "${1}" ]; then
      commit="${1}"
    fi

    info "starting deploy for ${deploy_app}"
    tput setf 3
    git fetch --all
    info "git fetch completed"
    tput setf 3
    git reset --hard "${commit}"
    info "git checkout completed"

    tput setf 3
    npm install --production 2>&1 | grep "" # disable colors
    info "npm install completed"

    popd
  fi
  start "${deploy_app}" "${app_dir}" "${port}"

  if [ "${mode}" = "deploy" ]; then
    cleanup() {
      kill "${tail_pid}"
    }
    trap cleanup INT # run cleanup on ^C
    info "Showing log for 10 seconds"
    echo
    tail -n 0 -F "${app_dir}/logs/forever.log" &
    tail_pid="$!"
    sleep 10
    cleanup
  fi

  if is_running "${deploy_app}"; then
    tput setf 2; echo -e "\n> ${deploy_app} has been deployed on port ${port}.\n"; tput sgr0
  else
    error "${deploy_app} is no longer running, deploy failed"
    return 1
  fi

  info "Sending SIGTERM to ${stop_app}"
  stop "${stop_app}"
  info "Setting next_deploy to ${stop_app}"
  echo "${stop_char}" > "${nd_file}"

  tput setf 2; echo -e "\n> ${mode} completed!\n"; tput sgr0
}

case "${1}" in
deploy)
  substitute "${2}";;
rollback)
  mode="rollback"
  substitute;;
start)
  start "${2}" "${3}" "${4}";;
stop)
  stop "${2}";;
*)
  echo "Usage:"
  echo "  $0 deploy [COMMIT]"
  echo "  $0 rollback"
  echo "  $0 start <APP_NAME> <APP_DIR> <PORT>"
  echo "  $0 stop <APP_NAME>"
esac