#!/usr/bin/env bash
set -eo pipefail

# Test an exercise

# which exercise are we testing right now?
# if we were passed an argument, that should be the
# exercise directory. Otherwise, assume we're in
# it currently.
if [ $# -ge 1 ]; then
    exercise=$1
    # if this script is called with arguments, it will pass through
    # any beyond the first to cargo. Note that we can only get a
    # free default argument if no arguments at all were passed,
    # so if you are in the exercise directory and want to pass any
    # arguments to cargo, you need to include the local path first.
    # I.e. to test in release mode:
    # $ test_exercise.sh . --release
    shift 1
else
    exercise='.'
fi

# what cargo command will we use?
if [ -n "$BENCHMARK" ]; then
    command="bench"
else
    command="test"
fi

declare -a preserve_files=("src/lib.rs" "Cargo.toml" "Cargo.lock")
declare -a preserve_dirs=("tests")

# reset instructions
reset () {
    for file in "${preserve_files[@]}"; do
        if [ -f "$exercise/$file.orig" ]; then
            mv -f "$exercise/$file.orig" "$exercise/$file"
        fi
    done
    for dir in "${preserve_dirs[@]}"; do
        if [ -d "$exercise/$dir.orig" ]; then
            rm -rf "${exercise:?}/$dir"
            mv "$exercise/$dir.orig" "$exercise/$dir"
        fi
    done
}

# cause the reset to execute when the script exits normally or is killed
trap reset EXIT INT TERM

# preserve the files and directories we care about
for file in "${preserve_files[@]}"; do
    if [ -f "$exercise/$file" ]; then
        cp "$exercise/$file" "$exercise/$file.orig"
    fi
done
for dir in "${preserve_dirs[@]}"; do
    if [ -d "$exercise/$dir" ]; then
        cp -r "$exercise/$dir" "$exercise/$dir.orig"
    fi
done

# Move example files to where Cargo expects them
if [ -f "$exercise/.meta/example.rs" ]; then
    example="$exercise/.meta/example.rs"
elif [ -f "$exercise/.meta/exemplar.rs" ]; then
    example="$exercise/.meta/exemplar.rs"
else
    echo "Could not locate example implementation for $exercise"
    exit 1
fi

cp -f "$example" "$exercise/src/lib.rs"
if [ -f "$exercise/.meta/Cargo-example.toml" ]; then
    cp -f "$exercise/.meta/Cargo-example.toml" "$exercise/Cargo.toml"
fi

# If deny warnings, insert a deny warnings compiler directive in the header
if [ -n "$DENYWARNINGS" ]; then
    sed -i -e '1i #![deny(warnings)]' "$exercise/src/lib.rs"
fi

# eliminate #[ignore] lines from tests
for test in "$exercise/"tests/*.rs; do
    sed -i -e '/#\[ignore\]/{
        s/#\[ignore\]\s*//
        /^\s*$/d
    }' "$test"
done

# run tests from within exercise directory
# (use subshell so we auto-reset to current pwd after)
(
cd "$exercise"
    if [ -n "$CLIPPY" ]; then
        # Consider any Clippy to be an error in tests only.
        # For now, not the example solutions since they have many Clippy warnings,
        # and are not shown to students anyway.
        sed -i -e '1i #![deny(clippy::all)]' tests/*.rs
        if ! cargo clippy --tests --color always "$@" 2>clippy.log; then
            cat clippy.log
            exit 1
        else
            # Just to show progress
            echo "clippy $exercise OK"
        fi
    else
        # this is the last command; its exit code is what's passed on
        time cargo $command "$@"
    fi
)
