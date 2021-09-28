FROM ubuntu:latest
RUN apt update\
    && apt install -y  curl unzip git wget \
    && curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
    &&   unzip awscliv2.zip \
    &&   ./aws/install \
    && curl -o /usr/local/bin/aws-iam-authenticator https://amazon-eks.s3.us-west-2.amazonaws.com/1.21.2/2021-07-05/bin/linux/amd64/aws-iam-authenticator \
    && chmod +x /usr/local/bin/aws-iam-authenticator \
    && curl -L -s https://github.com/derailed/k9s/releases/download/v0.24.15/k9s_Linux_x86_64.tar.gz | tar xz -C /usr/local/bin \
    && curl -s --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /usr/local/bin


COPY --from=hashicorp/terraform:1.0.7 /bin/terraform /usr/local/bin/terraform
COPY --from=bitnami/kubectl:latest /opt/bitnami/kubectl/bin/kubectl /usr/local/bin/kubectl
COPY --from=alpine/helm:3.6.3 /usr/bin/helm /usr/local/bin/helm
RUN helm repo add bitnami https://charts.bitnami.com/bitnami
WORKDIR /opt
