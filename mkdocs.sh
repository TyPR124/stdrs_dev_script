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
	
	pushd $rust
	COMMIT_HASH=`git rev-parse HEAD`
	popd
	pushd $3/$2
	echo "<!doctype html><html><body><p>Updated: `date -u`</p><p>Hash: ${COMMIT_HASH}</p></body></html>" > meta.html
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

rustup target add x86_64-pc-windows-gnu
rustup target add x86_64-unknown-linux-gnu

doc rust x86_64-pc-windows-gnu docs/nightly
doc rust x86_64-unknown-linux-gnu docs/nightly

gsutil rsync -m -r -d docs/nightly/x86_64-pc-windows-gnu gs://stdrs-dev-docs/nightly/x86_64-pc-windows-gnu
gsutil rsync -m -r -d docs/nightly/x86_64-unknown-linux-gnu gs://stdrs-dev-docs/nightly/x86_64-unknown-linux-gnu
