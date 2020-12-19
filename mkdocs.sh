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

	if [[ -n $SHUTDOWN_VM_ZONE && -n $SHUTDOWN_VM_NAME ]]; then
		gcloud compute instances stop $SHUTDOWN_VM_NAME --async --zone $SHUTDOWN_VM_ZONE
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
	local LAST_HASH="$(gsutil cat ${gs_base}/${target}/meta.txt | grep Hash: | sed -r -e 's/Hash: ([0-9A-Za-z]+)/\1/')"
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
	SELF_DIR="$( cd "$(dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

	echo "Began documenting ${target} at `date -u`"
	RDF_UNSTABLE="-Z unstable-options --document-hidden-items"
	# Note: SELF_DIR is expected to be assigned before update_docs() is called
	RDF_STABLE="--document-private-items --crate-version ${COMMIT_HASH:0:7} --html-in-header ${SELF_DIR}/in-head.html"
	export RUSTDOCFLAGS="${RDF_STABLE} ${RDF_UNSTABLE}"
	cargo +nightly doc --target $target --manifest-path $rust/library/std/Cargo.toml
	echo "Finished documenting ${target} at `date -u`"

	echo "Beginning sync docs for ${target}"
	echo "This can take some time..."
	gsutil -q -m rsync -r -d -C $rust/target/$target/doc $gs_base/$target
	echo "Finished sync docs for ${target} at `date -u`"

	# Update meta.txt last
	local NOW=`date -u`
	printf "Updated: ${NOW}\nHash: ${COMMIT_HASH}" > meta.txt
	gsutil cp meta.txt $gs_base/$target/meta.txt
	echo "Updated meta.txt for ${target}"
}

# Update self
SELF_DIR="$( cd "$(dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
pushd $SELF_DIR
SELF_HASH="$(git rev-parse HEAD)"
git pull
SELF_UPDATE_HASH="$(git rev-parse HEAD)"
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

# Check for or install rustup
# Assumes that if rustup exists, cargo and rustc exist as well
set +e
rustup help > /dev/null
status=$?
set -e
if [ $status -ne 0 ]; then
	export RUSTUP_HOME=/rustup
	export CARGO_HOME=/cargo
	export PATH=/cargo/bin:/rustup/bin:$PATH
	set +e
	rustup help > /dev/null
	status=$?
	set -e
	if [ $status -ne 0 ]; then
		curl -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain nightly --profile minimal
	fi
fi

# Update rustc, install necessary components and toolchains
rustup toolchain install nightly --profile minimal -c cargo -c rustc -c rust-docs
rustup target add x86_64-pc-windows-gnu
rustup target add x86_64-unknown-linux-gnu
rustup target add x86_64-apple-darwin

# Determine the commit-hash of this nightly rustc
NIGHTLY_HASH="$(rustc +nightly --version --verbose | grep commit-hash: | sed -r -e 's/commit-hash: ([0-9a-z]+)/\1/')"
echo "Nightly hash is ${NIGHTLY_HASH}"

# Get rust repo, find commit where this rustc was built
# Ignore clone errors, possibly already cloned
set +e
git clone https://github.com/rust-lang/rust
set -e

pushd rust
git fetch --all
git reset --hard $NIGHTLY_HASH
git submodule update --init --recursive --force
popd

# Sync static root content (NOTE: do NOT enable -r with -d)
gsutil -q rsync -d -C static_root/ gs://stdrs-dev-docs

update_docs rust x86_64-unknown-linux-gnu	gs://stdrs-dev-docs/nightly
update_docs rust x86_64-pc-windows-gnu		gs://stdrs-dev-docs/nightly
update_docs rust x86_64-apple-darwin		gs://stdrs-dev-docs/nightly
