#!/bin/bash

# Exit immediately on errors (by default)
set -e

trap 'pre_exit $? $LINENO $BASH_COMMAND' EXIT

pre_exit() {
	#Args
	local code=$1
	local last_line=$2
	local last_cmd=$3

	if [ $code -ne 0 ]; then
		echo "Ended with error ${code} on line ${last_line}: '${last_cmd}'"
	fi
}

update_docs() {
	# Args:
	# rust directory
	local rust=$1
	# target triple
	local target=$2
	# gs://my-bucket/base/dir
	local gs_base=$3

	# Get last Hash: value from $docs/$target/meta.txt
	set +e # meta.txt might not exist
	# local LAST_HASH="$(grep Hash: < $docs/$target/meta.txt | sed -r -e 's/Hash: ([0-9A-Za-z]+)/\1/')"
	local LAST_HASH="$(gsutil cat ${gs_base}/meta.txt | grep Hash: | sed -r -e 's/Hash: ([0-9A-Za-z]+)/\1/')"
	set -e
	echo "Last hash was ${LAST_HASH}"

	pushd $rust
	COMMIT_HASH="$(git rev-parse HEAD)"
	popd
	echo "Current hash is ${COMMIT_HASH}"
	
	if [ "$LAST_HASH" == "$COMMIT_HASH" ]; then
		echo "Hash not changed, skipping ${target}"
		return 0
	fi

	pushd $rust/src/libstd
	set +e
	RUSTDOCFLAGS='-Z unstable-options --document-hidden-items --document-private-items' cargo +nightly doc --target $target
	local status=$?
	set -e
	popd
	if [ $status -ne 0 ]; then
		return $status
	fi
	
	# set +e
	# rm -rf $docs/$target
	# set -e
	
	# mv $rust/target/$target/doc $docs/$target
	
	# pushd $docs/$target
	# local NOW=`date -u`
	# printf "<!doctype html><html><body><p>Updated: ${NOW}</p><p>Hash: ${COMMIT_HASH}</p></body></html>" > meta.html
	# printf "Updated: ${NOW}\nHash: ${COMMIT_HASH}" > meta.txt
	# popd

	set +e
	gsutil -m rsync -r -d $rust/target/$target/doc $gs_base/$target
	local status=$?
	set -e
	if [ $status -ne 0 ]; then
		return $status
	fi

	printf "Updated: ${NOW}\nHash: ${COMMIT_HASH}" | gsutil cp -I $gs_base/meta.txt
}

# Update self
SELF_DIR="$( cd "$(dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
pushd $SELF_DIR
SELF_HASH="$(git rev-parse HEAD)"
git pull
SELF_UPDATE_HASH="$(git rev-parse HEAD)"
# echo "Current script rev: ${SELF_HASH}"
# echo "Updated script rev: ${SELF_UPDATE_HASH}"
popd
if [ "$SELF_HASH" != "$SELF_UPDATE_HASH" ]; then
	echo "Current script rev: ${SELF_HASH}"
	echo "Updated script rev: ${SELF_UPDATE_HASH}"
	echo "Restarting with updated script"
	set +e
	"${BASH_SOURCE[0]}"
	exit $?
	set -e # unreachable, but I like the set +/- symmetry
fi

echo "Passed script update, running rev: ${SELF_HASH}"

# Check for rustup
set +e
rustup help > /dev/null
status=$?
set -e
if [ $status -ne 0 ]; then
	curl -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain nightly --profile minimal
	source ~/.profile
fi

# Update rustc (also maybe install missing components, requiring profile reload)
rustup toolchain install nightly --profile minimal -c cargo -c rustc -c rust-docs
source ~/.profile

NIGHTLY_HASH="$(rustc +nightly --version --verbose | grep commit-hash: | sed -r -e 's/commit-hash: ([0-9a-z]+)/\1/')"
echo "Nightly hash is ${NIGHTLY_HASH}"

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
mkdir docs/nightly
set -e
pushd docs/nightly
popd

rustup target add x86_64-pc-windows-gnu
rustup target add x86_64-unknown-linux-gnu

doc rust x86_64-pc-windows-gnu gs://stdrs-dev-docs/nightly
# doc rust x86_64-unknown-linux-gnu gs://stdrs-dev-docs/nightly

#gsutil -m rsync -r -d docs/nightly/x86_64-pc-windows-gnu gs://stdrs-dev-docs/nightly/x86_64-pc-windows-gnu
#gsutil -m rsync -r -d docs/nightly/x86_64-unknown-linux-gnu gs://stdrs-dev-docs/nightly/x86_64-unknown-linux-gnu
