FROM alpine:3.20

ARG TERRAFORM_VERSION=1.9.8
ARG OPENTOFU_VERSION=1.8.3

RUN apk add --no-cache bash curl unzip git jq ca-certificates \
    && update-ca-certificates \
    && curl -fsSL -o /tmp/terraform.zip "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" \
    && unzip /tmp/terraform.zip -d /usr/local/bin \
    && chmod +x /usr/local/bin/terraform \
    && rm -f /tmp/terraform.zip \
    && curl -fsSL -o /tmp/tofu.tar.gz "https://github.com/opentofu/opentofu/releases/download/v${OPENTOFU_VERSION}/tofu_${OPENTOFU_VERSION}_linux_amd64.tar.gz" \
    && tar -xzf /tmp/tofu.tar.gz -C /usr/local/bin tofu \
    && chmod +x /usr/local/bin/tofu \
    && rm -f /tmp/tofu.tar.gz

WORKDIR /workspace/infra

COPY infra/scripts/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["terraform", "version"]
