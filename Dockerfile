FROM		SCRATCH
RUN			mkdir /app && \
			pushd /app && \
			curl -O https://storage.googleapis.com/kubernetes-release/release/v1.3.4/bin/linux/amd64/kubectl