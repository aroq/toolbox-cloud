ARG TERRAFORM_VERSION=0.12.10
ARG GCLOUD_VERSION=266.0.0-alpine
ARG CHAMBER_VERSION=2.7.2
ARG CLOUDPOSSE_GEODESIC_VERSION=0.123.0
ARG KUBECTL_VERSION=v1.16.2
ARG KUBE_PROMPT_VERSION=1.0.9
ARG KUBE_PS1_VERSION=0.7.0

FROM google/cloud-sdk:$GCLOUD_VERSION as google-cloud-sdk
FROM hashicorp/terraform:$TERRAFORM_VERSION as terraform
FROM segment/chamber:$CHAMBER_VERSION as chamber
FROM cloudposse/geodesic:$CLOUDPOSSE_GEODESIC_VERSION as geodesic
FROM lachlanevenson/k8s-kubectl:$KUBECTL_VERSION as kubectl

FROM aroq/toolbox

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

COPY --from=kubectl /usr/local/bin/kubectl /usr/local/bin/kubectl

COPY --from=terraform /bin/terraform /usr/bin

COPY --from=chamber /chamber /usr/bin

COPY --from=geodesic /usr/bin/aws-vault /usr/bin

COPY Dockerfile.pip.requirements.txt /Dockerfile.pip.requirements.txt
#RUN pip install -r /requirements.txt --install-option="--prefix=/dist" --no-build-isolation
RUN pip install -r /Dockerfile.pip.requirements.txt

# Install kube-prompt
RUN wget https://github.com/c-bata/kube-prompt/releases/download/v$KUBE_PROMPT_VERSION/kube-prompt_$KUBE_PROMPT_VERSION_linux_amd64.zip && \
    unzip kube-prompt_$KUBE_PROMPT_VERSION_linux_amd64.zip && \
    chmod +x kube-prompt && \
    sudo mv ./kube-prompt /usr/local/bin/kube-prompt && \
    rm kube-prompt_$KUBE_PROMPT_VERSION_linux_amd64.zip

# Install kube-ps1
COPY k8s-cli-ps1.sh /root/k8s-prompt/
RUN curl -L https://github.com/jonmosco/kube-ps1/archive/v$KUBE_PS1_VERSION.tar.gz | tar xz \
    && cd ./kube-ps1-$KUBE_PS1_VERSION \
    && mv kube-ps1.sh ~/k8s-prompt/ \
    && chmod +x ~/k8s-prompt/*.sh \
    && rm -fr ./kube-ps1-$KUBE_PS1_VERSION \
    && echo "source ~/k8s-prompt/kube-ps1.sh" >> ~/.bashrc \
    && echo "source ~/k8s-prompt/k8s-cli-ps1.sh" >> ~/.bashrc \
    && echo "PROMPT_COMMAND=\"_kube_ps1_update_cache && k8s_cli_ps1\"" >> ~/.bashrc 

RUN rm -fr /tmp/install-utils \
    && echo "alias k=kubectl" >> ~/.bashrc \
    && echo "complete -o default -F __start_kubectl k" >> ~/.bashrc
