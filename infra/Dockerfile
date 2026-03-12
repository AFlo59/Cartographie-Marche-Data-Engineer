FROM debian:bookworm-slim

ARG TERRAFORM_VERSION=1.9.8
ARG OPENTOFU_VERSION=1.8.3
ARG TARGETOS=linux
ARG TARGETARCH=amd64

RUN apt-get update \
        && apt-get install -y --no-install-recommends \
            bash curl unzip git jq ca-certificates gnupg apt-transport-https python3 python3-pip \
        && mkdir -p /etc/apt/keyrings \
        && curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
            | gpg --dearmor -o /etc/apt/keyrings/google-cloud.gpg \
        && echo "deb [signed-by=/etc/apt/keyrings/google-cloud.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
            > /etc/apt/sources.list.d/google-cloud-sdk.list \
        && apt-get update \
        && apt-get install -y --no-install-recommends google-cloud-cli \
        && python3 -m pip install --no-cache-dir --upgrade pip setuptools wheel --break-system-packages \
        && rm -rf /var/lib/apt/lists/* \
        && case "${TARGETARCH}" in \
            amd64|arm64) ARCH="${TARGETARCH}" ;; \
            *) echo "Unsupported TARGETARCH: ${TARGETARCH}"; exit 1 ;; \
           esac \
        && TERRAFORM_ZIP="terraform_${TERRAFORM_VERSION}_${TARGETOS}_${ARCH}.zip" \
        && curl -fsSL -o "/tmp/${TERRAFORM_ZIP}" "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/${TERRAFORM_ZIP}" \
        && curl -fsSL -o /tmp/terraform_SHA256SUMS "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_SHA256SUMS" \
        && grep " ${TERRAFORM_ZIP}$" /tmp/terraform_SHA256SUMS > /tmp/terraform_SHA256SUM \
        && (cd /tmp && sha256sum -c terraform_SHA256SUM) \
    && unzip "/tmp/${TERRAFORM_ZIP}" -d /usr/local/bin \
    && chmod +x /usr/local/bin/terraform \
    && rm -f "/tmp/${TERRAFORM_ZIP}" /tmp/terraform_SHA256SUMS /tmp/terraform_SHA256SUM \
    && TOFU_TAR="tofu_${OPENTOFU_VERSION}_${TARGETOS}_${ARCH}.tar.gz" \
    && curl -fsSL -o "/tmp/${TOFU_TAR}" "https://github.com/opentofu/opentofu/releases/download/v${OPENTOFU_VERSION}/${TOFU_TAR}" \
    && curl -fsSL -o /tmp/tofu_SHA256SUMS "https://github.com/opentofu/opentofu/releases/download/v${OPENTOFU_VERSION}/tofu_${OPENTOFU_VERSION}_SHA256SUMS" \
    && grep " ${TOFU_TAR}$" /tmp/tofu_SHA256SUMS > /tmp/tofu_SHA256SUM \
    && (cd /tmp && sha256sum -c tofu_SHA256SUM) \
    && tar -xzf "/tmp/${TOFU_TAR}" -C /usr/local/bin tofu \
    && chmod +x /usr/local/bin/tofu \
    && rm -f "/tmp/${TOFU_TAR}" /tmp/tofu_SHA256SUMS /tmp/tofu_SHA256SUM

WORKDIR /workspace/infra

COPY infra/scripts/entrypoint.sh /entrypoint.sh
RUN sed -i '1s/^\xEF\xBB\xBF//' /entrypoint.sh \
    && sed -i 's/\r$//' /entrypoint.sh \
    && chmod +x /entrypoint.sh

ENTRYPOINT ["sh", "/entrypoint.sh"]
CMD ["terraform", "version"]
