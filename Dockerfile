FROM ubuntu

RUN apt-get update

# Clone rust as soon as possible to avoid long waits
RUN apt-get install -y --no-install-recommends git ca-certificates
RUN git clone https://github.com/rust-lang/rust && \
    cd rust && git submodule update --init --recursive
# Try really hard to keep all changes below here when iterating

# Install remaining stuff
RUN apt-get install -y --no-install-recommends \
    # For rust
    build-essential curl ca-certificates \
    # For gcloud / gsutil
    apt-transport-https ca-certificates gnupg python3.8

# Setup rust tools
ENV RUSTUP_HOME=/rustup
ENV CARGO_HOME=/cargo
ENV PATH=/cargo/bin:/rustup/bin:$PATH

RUN curl https://sh.rustup.rs -sSf | sh -s -- -y --no-modify-path --default-toolchain none

# Install gsutil w/ crc32c
RUN echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
RUN curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -
RUN apt-get update && apt-get install -y --no-install-recommends google-cloud-sdk
COPY gcloud_keyfile.json gcloud_keyfile.json
RUN gcloud auth activate-service-account --key-file ./gcloud_keyfile.json && rm ./gcloud_keyfile.json

RUN apt-get -y --no-install-recommends install gcc python-dev python-setuptools python-pip
RUN pip install --no-cache-dir -U crcmod

# Copy our stuff
COPY mkdocs.sh mkdocs.sh
RUN chmod 550 ./mkdocs.sh

# Final git sync
RUN cd rust && git checkout master && git pull && git submodule update --init --recursive

# Cleanup
RUN apt-get clean
RUN rm -rf /var/lib/apt/lists/*

CMD ./mkdocs.sh
