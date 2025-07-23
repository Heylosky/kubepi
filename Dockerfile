FROM node:18.10.0-alpine AS stage-web-build
ENV HTTP_PROXY=http://192.168.1.5:7890/
ENV HTTPS_PROXY=http://192.168.1.5:7890/
RUN apk add --no-cache make
ARG NPM_REGISTRY="https://registry.npmmirror.com"
ENV NPM_REGISTY=$NPM_REGISTRY

LABEL stage=stage-web-build
RUN set -ex \
    && npm config set registry ${NPM_REGISTRY}

WORKDIR /build/kubepi/web

COPY . .

RUN make build_web

RUN rm -fr web

FROM golang:1.22 AS stage-bin-build

ENV GOPROXY="https://goproxy.cn,direct"

ENV CGO_ENABLED=0

ENV GO111MODULE=on

LABEL stage=stage-bin-build

WORKDIR /build/kubepi/bin

COPY --from=stage-web-build /build/kubepi/web .

ENV HTTP_PROXY=http://192.168.1.5:7890/
ENV HTTPS_PROXY=http://192.168.1.5:7890/
RUN go mod download

RUN make build_gotty
RUN make build_bin

FROM alpine:3.16

WORKDIR /
ENV HTTP_PROXY="http://192.168.1.5:7890/"
ENV HTTPS_PROXY="http://192.168.1.5:7890/"
COPY --from=stage-bin-build /build/kubepi/bin/dist/usr /usr
COPY tools/kubectl /usr/bin/kubectl
COPY tools/kubectl-aliases.tar.gz /opt/kubectl-aliases.tar.gz
COPY tools/fzf.tar.gz /opt/fzf.tar.gz
COPY tools/k9s_Linux_amd64.tar.gz /tmp/k9s_Linux_amd64.tar.gz
COPY tools/kubens_v0.9.4_linux_amd64.tar.gz /tmp/kubens_v0.9.4_linux_amd64.tar.gz
COPY tools/kubectx_v0.9.4_linux_amd64.tar.gz /tmp/kubectx_v0.9.4_linux_amd64.tar.gz
COPY tools/helm-v3.10.2-linux-amd64.tar.gz /tmp/helm-v3.10.2-linux-amd64.tar.gz

RUN ARCH=$(uname -m) \
    && case $ARCH in aarch64) ARCH="arm64";; x86_64) ARCH="amd64";; esac \
    && echo "ARCH: " $ARCH \
    && apk add --update --no-cache bash bash-completion curl wget openssl iputils busybox-extras vim tini \
    && sed -i "s/nobody:\//nobody:\/nonexistent/g" /etc/passwd \
    && chmod +x /usr/bin/kubectl \
    && cd /opt/ \
    && tar zxvf kubectl-aliases.tar.gz \
    && rm -rf kubectl-aliases.tar.gz \
    && chmod -R 755 kubectl-aliases \
    && tar zxvf fzf.tar.gz \
    && rm -rf fzf.tar.gz \
    && chmod -R 755 fzf \
    && yes | fzf/install \
    && ln -s fzf/bin/fzf /usr/local/bin/fzf \
    && cd /tmp/ \
    && tar -xvf k9s_Linux_${ARCH}.tar.gz \
    && chmod +x k9s \
    && mv k9s /usr/bin \
    && KUBECTX_VERSION=v0.9.4 \
    && tar -xvf kubens_${KUBECTX_VERSION}_linux_${ARCH}.tar.gz \
    && chmod +x kubens \
    && mv kubens /usr/bin \
    && tar -xvf kubectx_${KUBECTX_VERSION}_linux_${ARCH}.tar.gz \
    && chmod +x kubectx \
    && mv kubectx /usr/bin \
    && HELM_VERSION=v3.10.2 \
    && tar -xvf helm-${HELM_VERSION}-linux-${ARCH}.tar.gz \
    && mv linux-${ARCH}/helm /usr/local/bin \
    && chmod +x /usr/local/bin/helm \
    && chmod +x /usr/local/bin/gotty \
    && chmod 555 /bin/busybox \
    && rm -rf /tmp/* /var/tmp/* /var/cache/apk/* \
    && chmod -R 755 /tmp \
    && mkdir -p /opt/webkubectl

RUN apk add tzdata && cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
    && echo "Asia/Shanghai" > /etc/timezone \
    && apk del tzdata

COPY conf/app.yml /etc/kubepi/app.yml

COPY vimrc.local /etc/vim

EXPOSE 80

USER root

ENV HTTP_PROXY=""
ENV HTTPS_PROXY=""
ENTRYPOINT ["tini", "-g", "--"]
CMD ["kubepi-server","-c", "/etc/kubepi" ,"--server-bind-host","0.0.0.0","--server-bind-port","80"]