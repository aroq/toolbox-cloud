# Define arguments & default values
ARG TERRAFORM_VERSION=0.12.10
ARG GCLOUD_VERSION=266.0.0-alpine
ARG CHAMBER_VERSION=2.7.2
ARG CLOUDPOSSE_GEODESIC_VERSION=0.123.0

FROM google/cloud-sdk:$GCLOUD_VERSION as google-cloud-sdk
FROM hashicorp/terraform:$TERRAFORM_VERSION as terraform
FROM segment/chamber:$CHAMBER_VERSION as chamber

# Builder stage
FROM golang:1-alpine as builder

# Define arguments & default values for builder stage
ARG KUBE_PROMPT_VERSION=v1.0.9
COPY Dockerfile.packages.builder.txt /etc/apk/packages.txt
RUN apk add --no-cache --update $(grep -v '^#' /etc/apk/packages.txt)

RUN git clone --depth 1 --single-branch -b $KUBE_PROMPT_VERSION https://github.com/c-bata/kube-prompt.git kube-prompt && \
  cd kube-prompt/ && \
  GO111MODULE=on go build . && \
  cp kube-prompt /usr/bin

# Main stage
FROM aroq/toolbox

# Define arguments & default values for main stage
ARG KUBECTL_VERSION=v1.16.2
ENV KUBE_PS1_VERSION 0.7.0
ENV KUBECTX_VERSION 0.7.1

COPY Dockerfile.packages.txt /etc/apk/packages.txt
RUN apk add --no-cache --update $(grep -v '^#' /etc/apk/packages.txt)

ENV CLOUDSDK_CONFIG=/localhost/.config/gcloud/
COPY --from=google-cloud-sdk /google-cloud-sdk/ /usr/local/google-cloud-sdk/
RUN ln -s /usr/local/google-cloud-sdk/bin/gcloud /usr/local/bin/ && \
    ln -s /usr/local/google-cloud-sdk/bin/gsutil /usr/local/bin/ && \
    ln -s /usr/local/google-cloud-sdk/bin/bq /usr/local/bin/ && \
    gcloud config set core/disable_usage_reporting true --installation && \
    gcloud config set component_manager/disable_update_check true --installation && \
    gcloud config set metrics/environment github_docker_image --installation

COPY --from=terraform /bin/terraform /usr/bin
COPY --from=chamber /chamber /usr/bin
COPY --from=builder /usr/bin/kube-prompt /usr/bin

COPY Dockerfile.pip.requirements.txt /Dockerfile.pip.requirements.txt
RUN pip install -r /Dockerfile.pip.requirements.txt

# Install kubectl
RUN curl -LO https://storage.googleapis.com/kubernetes-release/release/$KUBECTL_VERSION/bin/linux/amd64/kubectl && \
    chmod +x ./kubectl && \
    mv ./kubectl /usr/local/bin/kubectl && \
    mkdir -p ~/completions && \
    kubectl completion bash > ~/completions/kubectl.bash && \
    echo "source ~/completions/kubectl.bash" >> /etc/profile

# Install kube-ps1
COPY k8s-cli-ps1.sh /root/k8s-prompt/
RUN curl -L https://github.com/jonmosco/kube-ps1/archive/v${KUBE_PS1_VERSION}.tar.gz | tar xz && \
    cd ./kube-ps1-${KUBE_PS1_VERSION} && \
    mv kube-ps1.sh ~/k8s-prompt/ && \
    chmod +x ~/k8s-prompt/*.sh && \
    rm -fr ./kube-ps1-${KUBE_PS1_VERSION} && \
    echo "source ~/k8s-prompt/kube-ps1.sh" >> /etc/profile && \
    echo "source ~/k8s-prompt/k8s-cli-ps1.sh" >> /etc/profile && \
    echo "PROMPT_COMMAND=\"_kube_ps1_update_cache && k8s_cli_ps1\"" >> /etc/profile

# Setup kubectl aliases
RUN rm -fr /tmp/install-utils && \
    echo "alias k=kubectl" >> /etc/profile && \
    echo "alias kns=kubens" >> /etc/profile && \
    echo "complete -o default -F __start_kubectl k" >> /etc/profile

# Install kubectx/kubens
RUN curl -L https://github.com/ahmetb/kubectx/archive/v$KUBECTX_VERSION.tar.gz | \
    tar xz && \
    cd ./kubectx-$KUBECTX_VERSION && \
    mv kubectx kubens /usr/local/bin/ && \
    chmod +x /usr/local/bin/kubectx && \
    chmod +x /usr/local/bin/kubens && \
    cp completion/kubectx.bash ~/completions/ && \
    cp completion/kubens.bash  ~/completions/ && \
    echo "source ~/completions/kubectx.bash" >> /etc/profile && \
    echo "source ~/completions/kubens.bash" >> /etc/profile && \
    cd ../ && \
    rm -fr ./kubectx-$KUBECTX_VERSION
