#!/usr/bin/env bats

# All tests

load test_helper

@test "Run without arguments" {
	run uech
	assert_exit_status 2
	refute_line 2
}

@test "Display help" {
	run uech -help
	assert_exit_status 0
	refute_line 2
}

@test "Remove buffer at radius 0" {
	run uech.default example.com t
	assert_success

	run test.remote -d "$UECH_BUFFER"
	assert_failure
}

@test "Remove buffer at radius 1" {
	run uech.default -radius 1 example.com t
	assert_success

	run test.remote -d "$UECH_BUFFER"
	assert_failure
}

@test "Keep buffer at radius 0" {
	run uech.default -keep example.com t
	assert_success

	run test.remote -d "$UECH_BUFFER"
	assert_success
}

@test "Keep buffer at radius 1" {
	run uech.default -keep -radius 1 example.com t
	assert_success

	run test.remote -d "$UECH_BUFFER"
	assert_success
}

@test "Run executable three times" {
	exe.create ok "echo OK"
	run uech.default example.com ok
	assert_output_contains OK 3
}

@test "Run quiet" {
	exe.create ok "echo OK"
	run uech.default -quiet example.com ok

	refute_line 3

	assert_line_start_with 0 "OK"
	assert_line_start_with 1 "OK"
	assert_line_start_with 2 "OK"
}

@test "No CR seen by default" {
	exe.create ok '[[ ! $1 == REMOTE ]] || echo OK'
	run uech.stdout example.com ok

	refute_line 1
	assert_line 0 "       OK"
}

@test "CR seen on SSH if quiet" {
	using_ssh || skip
	exe.create ok '[[ ! $1 == REMOTE ]] || echo OK'
	run uech.stdout -quiet example.com ok

	refute_line 1
	assert_line 0 "$(echo -en "OK\r")"
}

@test "Pass correct arguments to the executable" {
	exe.create a 'for arg; do echo "$arg"; done'

	run uech.stdout example.com a myarg
	assert_success

	refute_line 6
	assert_line 0 "       LOCAL-"
	assert_line 1 "       myarg"
	assert_line 2 "       REMOTE"
	assert_line 3 "       myarg"
	assert_line 4 "       LOCAL+"
	assert_line 5 "       myarg"
}

@test "Exit on error" {
	exe.create ok <<-'EOF'
		echo $1
		case $1 in
		LOCAL-)
			;;
		REMOTE)
			exit 123
			;;
		LOCAL+)
			;;
		esac
	EOF
	run uech.default -quiet example.com ok

	assert_exit_status 123

	refute_line 2

	assert_line_start_with 0 "LOCAL-"
	assert_line_start_with 1 "REMOTE"
}


@test "Copy files inside periphery" {
	exe.create a/aa/aaa ""

	run uech.default -keep -radius 3 example.com a/aa/aaa
	assert_success

	run test.remote -d "$UECH_BUFFER/a"
	assert_success
}

@test "Set correct working directory" {
	exe.create a/aa/aaa 'echo "$1 $PWD"'

	run uech.stdout -radius 3 example.com a/aa/aaa
	assert_success

	refute_line 3
	assert_line 0 "       LOCAL- $PWD/a/aa"
	assert_line 1 "       REMOTE $UECH_BUFFER/a/aa"
	assert_line 2 "       LOCAL+ $PWD/a/aa"
}

@test "Fail if wanted clean without buffer" {
	run uech -local -clean example.com t
	assert_failure

	assert_output_contains "-clean" 1
	assert_output_contains "-buffer" 1
}

@test "Clean a previosly kept buffer" {
	touch.remote "$UECH_BUFFER/a"

	run uech.default -radius 1 example.com t
	assert_success

	run test -f "a"
	assert_success

	rm -f "a"

	touch.remote "$UECH_BUFFER/a"

	run uech.default -radius 1 -clean example.com t
	assert_success

	run test -f "a"
	assert_failure
}

@test "Succeed on noreuse flag" {
	run uech.default -noreuse example.com t
	assert_success
}

@test "Compute periphery through git" {
	exe.create a/aa/aaa ""

	git add a
	git commit -m .

	run uech.default -keep -git example.com a/aa/aaa
	assert_success

	run test.remote -d "$UECH_BUFFER/a"
	assert_success
}

@test "Ignore .git directory" {
	run uech.default -keep -git example.com t
	assert_success

	run test.remote -d "$UECH_BUFFER/.git"
	assert_failure
}

@test "Ignore gitignored files" {
	exe.create a/aa/aaa ""

	echo /b/ >>.gitignore

	git add a .
	git commit -m .

	file.create b/bb ""

	run uech.default -keep -git example.com a/aa/aaa
	assert_success

	run test.remote -d "$UECH_BUFFER/a"
	assert_success

	run test.remote -d "$UECH_BUFFER/b"
	assert_failure
}

@test "Fail if the executable is gitignored" {
	echo t >>.gitignore

	git add .
	git commit -m .

	run uech.default -keep -git example.com t
	assert_failure

	assert_output_contains "ignored executable" 1
}

@test "Copy dynamically created files in both ways" {
	exe.create a/aa/aaa <<-'EOF'
		case $1 in
		LOCAL-)
			touch "created_at_local-"
			;;
		REMOTE)
			touch "created_at_remote"
			;;
		LOCAL+)
			touch "created_at_local+"
			;;
		esac
	EOF

	run uech.default -keep -git example.com a/aa/aaa
	assert_success

	run test -f "a/aa/created_at_local-"
	assert_success

	run test.remote -f "$UECH_BUFFER/a/aa/created_at_local-"
	assert_success

	run test.remote -f "$UECH_BUFFER/a/aa/created_at_remote"
	assert_success

	run test -f "a/aa/created_at_remote"
	assert_success

	run test.remote -f "$UECH_BUFFER/a/aa/created_at_local+"
	assert_failure

	run test -f "a/aa/created_at_local+"
	assert_success
}
