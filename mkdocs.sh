#!/bin/bash

# Don't ignore errors
set -e

doc() {
	# Args
	rust=$1
	target=$2
	docs=$3

	pushd $rust/src/libstd
	set +e
	RUSTDOCFLAGS='-Z unstable-options --document-hidden-items --document-private-items' cargo +nightly doc --target $target
	status=$?
	set -e
	popd
	if [ $status -ne 0 ]; then
		return $status
	fi
	
	set +e
	rm -rf $docs/$target
	set -e
	
	mv $rust/target/$target/doc $docs/$target
	
	pushd $3/$2
	echo `date -u` > created
	popd
}

# Update rustc
rustup toolchain install nightly --profile minimal -c cargo -c rustc -c rust-docs

NIGHTLY_HASH="$(rustc +nightly --version --verbose | grep commit-hash | sed -r -e 's/commit-hash: ([0-9a-z]+)/\1/')"

# Ignore errors here (likely that rust is already cloned)
set +e
git clone https://github.com/rust-lang/rust
set -e

pushd rust
git checkout master
git pull
git checkout $NIGHTLY_HASH
git submodule update --init --recursive
popd

# Make sure docs dir exists
set +e
mkdir docs
set -e
pushd docs
set +e
mkdir nightly
set -e
popd
pushd docs/nightly
popd

rustup target add x86_64-pc-windows-msvc
rustup target add x86_64-unknown-linux-gnu

doc rust x86_64-pc-windows-msvc docs/nightly
doc rust x86_64-unknown-linux-gnu docs/nightly

gsutil rsync -r -d docs/nightly gs://stdrs-dev-docs/nightly
