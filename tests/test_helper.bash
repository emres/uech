#!/usr/bin/env bash

load lib

# ------------------------------------------------------------------------------
# Setup
# ------------------------------------------------------------------------------

super() {
	export PATH=$PWD:$PATH

	super.setup_once() {
		:
	}

	super.teardown_once() {
		:
	}

	super.setup() {
		[[ ! -f ${BATS_PARENT_TMPNAME}.skip ]] || skip "previous test failed! skipping remaining tests..."

		fixture.enter
		exe.create t ""
		git.create
	}

	super.teardown() {
		if [[ -z $BATS_TEST_COMPLETED ]]; then
			touch "${BATS_PARENT_TMPNAME}.skip"
			[[ ${#cleanup[@]} -eq 0 ]] || cry "Did not remove ${cleanup[*]} as test failed"
		else
			rm -rf -- "${cleanup[@]}"
		fi
	}
}

with_ssh() {
	export SSH_CONFIG=${BATS_TMPDIR:?}/example.com

	self.setup_once() {
		cry "Testing with SSH"

		super.setup_once

		if command -v nc >/dev/null; then
			nc -z localhost 2222 2>/dev/null || die "SSH unreachable"
		fi

		pushd "$BATS_TEST_DIRNAME" >/dev/null
		vagrant ssh-config --host '*' >"$SSH_CONFIG"
		popd >/dev/null
		echo
	}

	self.teardown_once() {
		super.teardown_once
		rm -f "$SSH_CONFIG"
	}

	self.setup() {
		super.setup

		UECH_BUFFER=$(
			ssh -F "$SSH_CONFIG" example.com bash -s <<-EOF
				readlink -f .cache/uech
			EOF
		)
		export UECH_BUFFER

		uech.default() {
			uech -config="$SSH_CONFIG" -buffer="$UECH_BUFFER" "$@"
		}

		uech.stdout() {
			uech.default "$@" 2>/dev/null
		}

		test.remote() {
			# shellcheck disable=SC2029
			ssh -F "$SSH_CONFIG" example.com test "$@"
		}

		touch.remote() {
			# shellcheck disable=SC2029
			ssh -F "$SSH_CONFIG" example.com bash -s "$1" <<-'EOF'
				mkdir -p "$(dirname "$1")"
				touch "$1"
			EOF
		}

		remove.remote() {
			# shellcheck disable=SC2029
			ssh -F "$SSH_CONFIG" example.com rm -rf "$1"
		}

		remove.remote .cache/uech
	}

	self.teardown() {
		:
	}
}

without_ssh() {
	self.setup_once() {
		cry "Testing locally"
	}

	self.teardown_once() {
		:
	}

	self.setup() {
		super.setup

		UECH_BUFFER=$(readlink -f "$PWD/../buffer")
		export UECH_BUFFER

		uech.default() {
			uech -local -buffer="$UECH_BUFFER" "$@"
		}

		uech.stdout() {
			uech.default "$@" 2>/dev/null
		}

		test.remote() {
			test "$@"
		}

		touch.remote() {
			mkdir -p "$(dirname "$1")"
			touch "$1"
		}

		remove.remote() {
			rm -rf "$1"
		}
	}

	self.teardown() {
		:
	}
}

super
if [[ -n $UECH_BATS_WITH_SSH ]]; then
	with_ssh
else
	without_ssh
fi

setup() {
	if [[ $BATS_TEST_NUMBER -eq 1 ]]; then
		super.setup_once
		self.setup_once
	fi
	super.setup
	self.setup
}

teardown() {
	self.teardown
	super.teardown
	if [[ $BATS_TEST_NUMBER -eq ${#BATS_TEST_NAMES[@]} ]]; then
		self.teardown_once
		super.teardown_once
	fi
}

# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------

cry() {
	printf "\x1B[K" >/dev/tty

	local arg
	for arg; do
		echo -e "\e[1;38;5;11m$arg\e[0m" >/dev/tty
	done
}

die() {
	printf "\x1B[K" >/dev/tty

	local arg
	for arg; do
		echo -e "\e[1;38;5;198m$arg\e[0m" >/dev/tty
	done

	exit 1
}

file.create() {
	local file=$1
	shift

	mkdir -p "$(dirname "$file")"

	if [[ $# -eq 0 ]]; then
		cat -
	else
		echo "$*"
	fi >"$file"
}

exe.create() {
	local file=$1
	shift

	mkdir -p "$(dirname "$file")"

	{
		echo "#!/bin/bash"
		if [[ $# -eq 0 ]]; then
			cat -
		else
			echo "$*"
		fi
	} >"$file"

	chmod +x "$file"
}

declare -ag cleanup=()

fixture.enter() {
	local tmpdir

	tmpdir="$(mktemp -d "${BATS_TMPDIR:-/tmp}/uech.XXXXX")"
	cleanup+=("$tmpdir")

	pushd "$tmpdir" &>/dev/null || exit 1
	mkdir -p fixture
	pushd fixture &>/dev/null || exit 1
}

git.create() {
	git init
	git config user.email "robot@example.com"
	git config user.name "Test Robot"
	git add .
	git commit -m "initial commit"
}
