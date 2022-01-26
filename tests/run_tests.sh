#!/usr/bin/env bash

# Copyright 2022 Balena Ltd.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

TEST_DIR="$(dirname "${BASH_SOURCE[0]}")"

if [ -f "${TEST_DIR}/test-config.sh" ]; then
	# shellcheck disable=SC1091
	source "${TEST_DIR}/test-config.sh"
fi

# BEGIN - test configuration variables
# The tests are executed against a real/live balenaOS device on the local network
# (either production or development image). These variables specify the details of
# the test device. The device should be running an application with services.
# One of the services should have 'rsync' installed and the service name should be
# assigned to the TEST_SERVICE variable. The TEST_SERVICE_ISSUE variable should be
# assigned the contents of the '/etc/issue' file for the service. You can avoid
# editing this file directly by creating a a file named 'test-config.sh' on the
# same folder as this file, and setting you device configuration variables there.
TEST_DEVICE_IP="${TEST_DEVICE_IP:-192.168.1.50}"
TEST_DEVICE_UUID="${TEST_DEVICE_UUID:-a123456abcdef123456abcdef1234567}"
TEST_DEVICE_HOST="${TEST_DEVICE_UUID}.balena"
TEST_DEVICE_OS_VERSION="${TEST_DEVICE_OS_VERSION:-2.85.2}"
TEST_SERVICE="${TEST_SERVICE:-my-service}"
TEST_SERVICE_ISSUE="${TEST_SERVICE_ISSUE:-Debian GNU/Linux 11 \n \l}"
# END - test configuration variables

SCP_UUID="${TEST_DIR}/scp-uuid"
SSH_UUID="${TEST_DIR}/ssh-uuid"

SSH_WITH_IP_ADDRESS=(ssh -p 22222 "root@${TEST_DEVICE_IP}")
SSH_WITH_UUID=("${SSH_UUID}" "${TEST_DEVICE_HOST}")
SSH_WITH_SERVICE=("${SSH_UUID}" --service "${TEST_SERVICE}" "${TEST_DEVICE_HOST}")

TEST_COUNTER=0

function quit {
	echo -e "\nERROR: $1" >/dev/stderr
	exit 1
}

# escape array
function escape_a {
	# local escaped_str
	# printf -v escaped_str '%q ' "$@"
	# declare -ag ESCAPED_ARRAY="( ${escaped_str} )"
	printf '%q ' "$@"
}

function run_test {
	local test_name="$1"
	local -a cmd="($2)" # unescaped array
	local expected="$3"
	local expected_status="$4"
	local actual
	local actual_status

	set -x
	actual="$("${cmd[@]}" 2>&1)"
	{ actual_status="$?"; set +x; } 2>/dev/null

	# echo "actual: ~${actual}~ (${actual_status})"
	# echo "expected: ~${expected}~ (${expected_status})"

	if [ "${actual}" != "${expected}" ]; then
		quit "\nTEST '${test_name}': FAIL\n
Mismatched output:
Expected: '${expected}'
Actual: '${actual}'"
	fi
	if [ "${actual_status}" != "${expected_status}" ]; then
		quit "\nTEST '${test_name}': FAIL\n
Mismatched exit status code:
Expected: '${expected_status}'
Actual: '${actual_status}'"
	fi
	echo -e "\nTEST '${test_name}': PASS\n"
	(( TEST_COUNTER++ ))
}

function test_host_os_status {
	local c
	local expected=''
	local expected_status
	for c in true false; do
		if [ "$c" = 'true' ]; then expected_status='0'; else expected_status='1'; fi
		local cmd1=("${SSH_WITH_IP_ADDRESS[@]}" "$c")
		local cmd2=("${SSH_WITH_UUID[@]}" "$c")

		run_test "${FUNCNAME[0]} (IP address)" "$(escape_a "${cmd1[@]}")" "${expected}" "${expected_status}"
		run_test "${FUNCNAME[0]} (UUID)" "$(escape_a "${cmd2[@]}")" "${expected}" "${expected_status}"
	done
}

function test_host_os_cat {
	local cmd1=("${SSH_WITH_IP_ADDRESS[@]}" cat /etc/issue)
	local cmd2=("${SSH_WITH_UUID[@]}" cat /etc/issue)
	local expected="balenaOS ${TEST_DEVICE_OS_VERSION} \n \l"
	local expected_status='0'

	run_test "${FUNCNAME[0]} (IP address)" "$(escape_a "${cmd1[@]}")" "${expected}" "${expected_status}"
	run_test "${FUNCNAME[0]} (UUID)" "$(escape_a "${cmd2[@]}")" "${expected}" "${expected_status}"
}

function test_host_os_cat_with_spaces {
	local contents='hi there'
	local fname='/tmp/test\ host\ os\ cat\ with\ spaces.txt'
	local cmd1=("${SSH_WITH_IP_ADDRESS[@]}" echo "${contents}" '>' "${fname}")
	local expected1=''
	local cmd2=("${SSH_WITH_UUID[@]}" cat "${fname}")
	local expected2="${contents}"
	local expected_status='0'

	run_test "${FUNCNAME[0]} (IP address 1)" "$(escape_a "${cmd1[@]}")" "${expected1}" "${expected_status}"
	run_test "${FUNCNAME[0]} (UUID 1)" "$(escape_a "${cmd2[@]}")" "${expected2}" "${expected_status}"

	# change contents and swap ssh commands
	contents='hi there (new contents)'
	cmd1=("${SSH_WITH_UUID[@]}" echo "'${contents}'" '>' "${fname}")
	expected1=''
	cmd2=("${SSH_WITH_IP_ADDRESS[@]}" cat "${fname}")
	expected2="${contents}"

	run_test "${FUNCNAME[0]} (IP address 2)" "$(escape_a "${cmd1[@]}")" "${expected1}" "${expected_status}"
	run_test "${FUNCNAME[0]} (UUID 2)" "$(escape_a "${cmd2[@]}")" "${expected2}" "${expected_status}"
}

function test_host_os_cat_with_encoded_line_breaks {
	local contents='hi there\nline2'
	local fname='/tmp/test\ host\ os\ cat\ with\ spaces.txt'
	local cmd1=("${SSH_WITH_IP_ADDRESS[@]}" echo -e "'${contents}'" '>' "${fname}")
	local expected1=''
	local cmd2=("${SSH_WITH_UUID[@]}" cat "${fname}")
	local expected2
	printf -v expected2 '%b' "${contents}"
	local expected_status='0'

	run_test "${FUNCNAME[0]} (IP address 1)" "$(escape_a "${cmd1[@]}")" "${expected1}" "${expected_status}"
	run_test "${FUNCNAME[0]} (UUID 1)" "$(escape_a "${cmd2[@]}")" "${expected2}" "${expected_status}"

	# change contents and swap ssh commands
	contents='hi there\nline2 (new contents)'
	cmd1=("${SSH_WITH_UUID[@]}" echo -e "'${contents}'" '>' "${fname}")
	expected1=''
	cmd2=("${SSH_WITH_IP_ADDRESS[@]}" cat "${fname}")
	printf -v expected2 '%b' "${contents}"

	run_test "${FUNCNAME[0]} (UUID 2)" "$(escape_a "${cmd1[@]}")" "${expected1}" "${expected_status}"
	run_test "${FUNCNAME[0]} (IP address 2)" "$(escape_a "${cmd2[@]}")" "${expected2}" "${expected_status}"
}

function test_host_os_cat_with_unencoded_line_breaks {
	local contents='hi there
line2 (with unencoded newline characters)'
	local fname='/tmp/test\ host\ os\ cat\ with\ spaces.txt'
	local cmd1=("${SSH_WITH_IP_ADDRESS[@]}" echo "'${contents}'" '>' "${fname}")
	local expected1=''
	local cmd2=("${SSH_WITH_UUID[@]}" cat "${fname}")
	local expected2="${contents}"
	local expected_status='0'

	run_test "${FUNCNAME[0]} (IP address 1)" "$(escape_a "${cmd1[@]}")" "${expected1}" "${expected_status}"
	run_test "${FUNCNAME[0]} (UUID 1)" "$(escape_a "${cmd2[@]}")" "${expected2}" "${expected_status}"

	# change contents and swap ssh commands
	contents='hi there
line2 (with unencoded newline characters)
(new contents)'
	cmd1=("${SSH_WITH_UUID[@]}" echo "'${contents}'" '>' "${fname}")
	expected1=''
	cmd2=("${SSH_WITH_IP_ADDRESS[@]}" cat "${fname}")
	expected2="${contents}"

	run_test "${FUNCNAME[0]} (UUID 2)" "$(escape_a "${cmd1[@]}")" "${expected1}" "${expected_status}"
	run_test "${FUNCNAME[0]} (IP address 2)" "$(escape_a "${cmd2[@]}")" "${expected2}" "${expected_status}"
}

function test_service_status {
	local c
	local expected=''
	local expected_status
	for c in true false; do
		if [ "$c" = 'true' ]; then expected_status='0'; else expected_status='1'; fi
		local cmd=("${SSH_WITH_SERVICE[@]}" "$c")

		run_test "${FUNCNAME[0]} (UUID)" "$(escape_a "${cmd[@]}")" "${expected}" "${expected_status}"
	done
}

function test_service_cat {
	local cmd=("${SSH_WITH_SERVICE[@]}" cat /etc/issue)
	local expected="${TEST_SERVICE_ISSUE}"
	local expected_status='0'

	run_test "${FUNCNAME[0]}" "$(escape_a "${cmd[@]}")" "${expected}" "${expected_status}"
}

function test_service_cat_with_spaces {
	local contents='hi there'
	local fname='/tmp/test\ host\ os\ cat\ with\ spaces\ \(service\).txt'
	local cmd1=("${SSH_WITH_SERVICE[@]}" echo "${contents}" '>' "${fname}")
	local expected1=''
	local cmd2=("${SSH_WITH_SERVICE[@]}" cat "${fname}")
	local expected2="${contents}"
	local expected_status='0'

	run_test "${FUNCNAME[0]} (1)" "$(escape_a "${cmd1[@]}")" "${expected1}" "${expected_status}"
	run_test "${FUNCNAME[0]} (2)" "$(escape_a "${cmd2[@]}")" "${expected2}" "${expected_status}"
}

function test_service_cat_with_encoded_line_breaks {
	local contents='hi there
line2 (service)'
	local fname='/tmp/test\ host\ os\ cat\ with\ spaces\ \(service\).txt'
	local cmd1=("${SSH_WITH_SERVICE[@]}" echo "'${contents}'" '>' "${fname}")
	local expected1=''
	local cmd2=("${SSH_WITH_SERVICE[@]}" cat "${fname}")
	local expected2
	printf -v expected2 '%b' "${contents}"
	local expected_status='0'

	run_test "${FUNCNAME[0]} (1)" "$(escape_a "${cmd1[@]}")" "${expected1}" "${expected_status}"
	run_test "${FUNCNAME[0]} (2)" "$(escape_a "${cmd2[@]}")" "${expected2}" "${expected_status}"
}

function test_service_cat_with_unencoded_line_breaks {
	local contents='hi there
line2 (service)'
	local fname='/tmp/test\ host\ os\ cat\ with\ spaces\ \(service\).txt'
	local cmd1=("${SSH_WITH_SERVICE[@]}" echo "'${contents}'" '>' "${fname}")
	local expected1=''
	local cmd2=("${SSH_WITH_SERVICE[@]}" cat "${fname}")
	local expected2="${contents}"
	local expected_status='0'

	run_test "${FUNCNAME[0]} (1)" "$(escape_a "${cmd1[@]}")" "${expected1}" "${expected_status}"
	run_test "${FUNCNAME[0]} (2)" "$(escape_a "${cmd2[@]}")" "${expected2}" "${expected_status}"
}

function test_scp_local_to_remote {
	local contents="hi there
(local)"
	local fname='/tmp/local copy.txt'
	local escaped_fname
	printf -v escaped_fname '%q' "${fname}"

	# clean up previous runs and create local file
	"${SSH_WITH_IP_ADDRESS[@]}" rm -f "${escaped_fname}"
	echo "${contents}" > "${fname}"

	local cmd1=("${SCP_UUID}" "${fname}" "${TEST_DEVICE_HOST}:${escaped_fname}")
	local expected1=''
	local cmd2=("${SSH_WITH_IP_ADDRESS[@]}" cat "${escaped_fname}")
	local expected2="${contents}"
	local expected_status='0'

	run_test "${FUNCNAME[0]} (1)" "$(escape_a "${cmd1[@]}")" "${expected1}" "${expected_status}"
	run_test "${FUNCNAME[0]} (2)" "$(escape_a "${cmd2[@]}")" "${expected2}" "${expected_status}"

	# clean up
	rm -f "${fname}"
}

function test_scp_remote_to_local {
	local contents="hi there
(remote)"
	local fname='/tmp/remote copy.txt'
	local escaped_fname
	printf -v escaped_fname '%q' "${fname}"

	# clean up previous runs and create remote file
	rm -f "${fname}"
	"${SSH_WITH_IP_ADDRESS[@]}" echo "'${contents}'" '>' "${escaped_fname}"

	local cmd1=("${SCP_UUID}" "${TEST_DEVICE_HOST}:${escaped_fname}" "${fname}")
	local expected1=''
	local cmd2=(cat "${fname}")
	local expected2="${contents}"
	local expected_status='0'

	run_test "${FUNCNAME[0]} (1)" "$(escape_a "${cmd1[@]}")" "${expected1}" "${expected_status}"
	run_test "${FUNCNAME[0]} (2)" "$(escape_a "${cmd2[@]}")" "${expected2}" "${expected_status}"

	# clean up
	rm -f "${fname}"
}

function test_scp_service_local_to_remote {
	local contents="hi there
(local)"
	local fname='/tmp/local copy.txt'
	local escaped_fname
	printf -v escaped_fname '%q' "${fname}"

	# clean up previous runs and create local file
	"${SSH_WITH_SERVICE[@]}" rm -f "${escaped_fname}"
	echo "${contents}" > "${fname}"

	local cmd1=("${SCP_UUID}" --service "${TEST_SERVICE}" "${fname}" "${TEST_DEVICE_HOST}:${escaped_fname}")
	local expected1=''
	local cmd2=("${SSH_WITH_SERVICE[@]}" cat "${escaped_fname}")
	local expected2="${contents}"
	local expected_status='0'

	run_test "${FUNCNAME[0]} (1)" "$(escape_a "${cmd1[@]}")" "${expected1}" "${expected_status}"
	run_test "${FUNCNAME[0]} (2)" "$(escape_a "${cmd2[@]}")" "${expected2}" "${expected_status}"

	# clean up
	rm -f "${fname}"
	"${SSH_WITH_SERVICE[@]}" rm -f "${escaped_fname}"
}

function test_scp_service_remote_to_local {
	local contents="hi there
(remote)"
	local fname='/tmp/remote copy.txt'
	local escaped_fname
	printf -v escaped_fname '%q' "${fname}"

	# clean up previous runs and create remote file
	rm -f "${fname}"
	"${SSH_WITH_SERVICE[@]}" echo "'${contents}'" '>' "${escaped_fname}"

	local cmd1=("${SCP_UUID}" --service "${TEST_SERVICE}" "${TEST_DEVICE_HOST}:${escaped_fname}" "${fname}")
	local expected1=''
	local cmd2=(cat "${fname}")
	local expected2="${contents}"
	local expected_status='0'

	run_test "${FUNCNAME[0]} (1)" "$(escape_a "${cmd1[@]}")" "${expected1}" "${expected_status}"
	run_test "${FUNCNAME[0]} (2)" "$(escape_a "${cmd2[@]}")" "${expected2}" "${expected_status}"

	# clean up
	rm -f "${fname}"
	"${SSH_WITH_SERVICE[@]}" rm -f "${escaped_fname}"
}

function test_rsync_local_to_remote {
	local contents="hi there
(local, rsync)"
	local fname='/tmp/local copy (rsync).txt'
	local escaped_fname
	printf -v escaped_fname '%q' "${fname}"

	# clean up previous runs and create local file
	"${SSH_WITH_SERVICE[@]}" rm -f "${escaped_fname}"
	echo "${contents}" > "${fname}"

	local cmd1=('rsync' '-e' "ssh-uuid --service ${TEST_SERVICE}" "${fname}" "${TEST_DEVICE_HOST}:${escaped_fname}")
	local expected1=''
	local cmd2=("${SSH_WITH_SERVICE[@]}" cat "${escaped_fname}")
	local expected2="${contents}"
	local expected_status='0'

	run_test "${FUNCNAME[0]} (1)" "$(escape_a "${cmd1[@]}")" "${expected1}" "${expected_status}"
	run_test "${FUNCNAME[0]} (2)" "$(escape_a "${cmd2[@]}")" "${expected2}" "${expected_status}"

	# clean up
	rm -f "${fname}"
	"${SSH_WITH_SERVICE[@]}" rm -f "${escaped_fname}"
}

function test_rsync_remote_to_local {
	local contents="hi there
(remote, rsync)"
	local fname='/tmp/remote copy (rsync).txt'
	local escaped_fname
	printf -v escaped_fname '%q' "${fname}"

	# clean up previous runs and create local file
	rm -f "${fname}"
	"${SSH_WITH_SERVICE[@]}" echo "'${contents}'" '>' "${escaped_fname}"

	local cmd1=('rsync' '-e' "ssh-uuid --service ${TEST_SERVICE}" "${TEST_DEVICE_HOST}:${escaped_fname}" "${fname}")
	local expected1=''
	local cmd2=(cat "${fname}")
	local expected2="${contents}"
	local expected_status='0'

	run_test "${FUNCNAME[0]} (1)" "$(escape_a "${cmd1[@]}")" "${expected1}" "${expected_status}"
	run_test "${FUNCNAME[0]} (2)" "$(escape_a "${cmd2[@]}")" "${expected2}" "${expected_status}"

	# clean up
	rm -f "${fname}"
	"${SSH_WITH_SERVICE[@]}" rm -f "${escaped_fname}"
}

function test_counter {
	local expected_count=39
	if [ "${TEST_COUNTER}" != "${expected_count}" ]; then
		quit "\nTEST COUNT FAILED: expected '${expected_count}' tests to run, counted '${TEST_COUNTER}'"
	fi
	echo -e "\nALL '${TEST_COUNTER}' TESTS COMPLETED SUCCESSFULLY!\n"
}

function run_tests {
	test_host_os_status
	test_service_status

	test_host_os_cat
	test_host_os_cat_with_spaces
	test_host_os_cat_with_encoded_line_breaks
	test_host_os_cat_with_unencoded_line_breaks

	test_service_cat
	test_service_cat_with_spaces
	test_service_cat_with_encoded_line_breaks
	test_service_cat_with_unencoded_line_breaks

	test_scp_local_to_remote
	test_scp_remote_to_local

	test_scp_service_local_to_remote
	test_scp_service_remote_to_local

	test_rsync_local_to_remote
	test_rsync_remote_to_local

	test_counter
}

run_tests
