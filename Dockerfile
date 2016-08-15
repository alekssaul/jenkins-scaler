FROM		alpine:latest
RUN			apk update && apk upgrade && \
			apk add curl bash
RUN 		curl -O https://storage.googleapis.com/kubernetes-release/release/v1.3.4/bin/linux/amd64/kubectl && \
			mv kubectl /usr/local/bin/kubectl && \
			chmod +x /usr/local/bin/kubectl 
