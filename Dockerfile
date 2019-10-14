ARG TERRAFORM_VERSION=0.12.10
ARG GCLOUD_VERSION=266.0.0-alpine
ARG CHAMBER_VERSION=2.7.2

FROM google/cloud-sdk:$GCLOUD_VERSION as google-cloud-sdk
FROM hashicorp/terraform:$TERRAFORM_VERSION as terraform
FROM segment/chamber:$CHAMBER_VERSION as chamber

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
RUN gcloud components install kubectl

COPY --from=terraform /bin/terraform /bin

COPY --from=chamber /chamber /bin

COPY Dockerfile.pip.requirements.txt /Dockerfile.pip.requirements.txt
#RUN pip install -r /requirements.txt --install-option="--prefix=/dist" --no-build-isolation
RUN pip install -r /Dockerfile.pip.requirements.txt
