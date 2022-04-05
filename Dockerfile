ARG BASE_IMAGE=debian:11.2-slim@sha256:4c25ffa6ef572cf0d57da8c634769a08ae94529f7de5be5587ec8ce7b9b50f9c
ARG BASE_BUILDER_IMAGE=node:lts-buster-slim

# -----------------------------------------------------------------------------
# Stage: builder
# -----------------------------------------------------------------------------

FROM ${BASE_BUILDER_IMAGE} AS builder

# Set Shell to use for RUN commands in builder step.

ENV REFRESHED_AT=2022-03-21

LABEL Name="senzing/xterm-builder" \
      Maintainer="support@senzing.com" \
      Version="1.2.5"

# Run as "root" for system installation.

USER root

# Set working directory.

WORKDIR /app

# Add `/app/node_modules/.bin` to $PATH

ENV PATH /app/node_modules/.bin:$PATH

# Install and cache app dependencies.

COPY package.json      /app/package.json
COPY package-lock.json /app/package-lock.json

# Build js packages.

RUN npm config set loglevel warn \
 && npm install

# Install packages via apt for building fio.

RUN apt-get update \
 && apt-get -y install \
      gcc \
      make \
      pkg-config \
      unzip \
      wget

# Work around until Debian repos catch up to modern versions of fio.

RUN mkdir /tmp/fio \
 && cd /tmp/fio \
 && wget https://github.com/axboe/fio/archive/refs/tags/fio-3.27.zip \
 && unzip fio-3.27.zip \
 && cd fio-fio-3.27/ \
 && ./configure \
 && make \
 && make install \
 && fio --version \
 && cd \
 && rm -rf /tmp/fio

# -----------------------------------------------------------------------------
# Stage: Final
# -----------------------------------------------------------------------------

# Create the runtime image.

FROM ${BASE_IMAGE} AS runner

ENV REFRESHED_AT=2022-03-21

LABEL Name="senzing/xterm" \
      Maintainer="support@senzing.com" \
      Version="1.2.5"

# Define health check.

HEALTHCHECK CMD ["/app/healthcheck.sh"]

# Run as "root" for system installation.

USER root

# Re-enable man pages

RUN sed -i '/path-exclude \/usr\/share\/man/d' /etc/dpkg/dpkg.cfg.d/docker \
 && sed -i '/path-exclude \/usr\/share\/groff/d' /etc/dpkg/dpkg.cfg.d/docker

# Install packages via apt.

RUN apt-get update \
 && apt-get install --reinstall \
      bash \
      coreutils \
 && apt-get -y install \
      curl \
      elvis-tiny \
      htop \
      iotop \
      jq \
      less \
      libpq-dev \
      libssl1.1 \
      manpages \
      man-db \
      nano \
      net-tools \
      odbcinst \
      openssh-server \
      postgresql-client \
      procps \
      python3-dev \
      python3-pip \
      sqlite3 \
      strace \
      tree \
      unixodbc-dev \
      unzip \
      wget \
      zip \
 && apt-get clean

# Install packages via pip.

COPY requirements.txt .
RUN pip3 install --upgrade pip \
 && pip3 install -r requirements.txt \
 && rm /requirements.txt

# Copy files from repository.

COPY ./rootfs /

# Copy files from prior stages.

COPY --from=builder "/app/node_modules/socket.io-client/dist/socket.io.js"     "/app/static/js/"
COPY --from=builder "/app/node_modules/socket.io-client/dist/socket.io.js.map" "/app/static/js/"
COPY --from=builder "/app/node_modules/xterm-addon-attach/lib/*"               "/app/static/js/"
COPY --from=builder "/app/node_modules/xterm-addon-fit/lib/*"                  "/app/static/js/"
COPY --from=builder "/app/node_modules/xterm-addon-search/lib/*"               "/app/static/js/"
COPY --from=builder "/app/node_modules/xterm-addon-web-links/lib/*"            "/app/static/js/"
COPY --from=builder "/app/node_modules/xterm/css/xterm.css"                    "/app/static/css/"
COPY --from=builder "/app/node_modules/xterm/lib/*"                            "/app/static/js/"
COPY --from=builder "/usr/local/bin/fio"                                       "/usr/local/bin/fio"

# Add test user

RUN useradd -m test-user \
 && echo "cd ~" > /home/test-user/.bash_login \
 && mkdir -p \
     /home/test-user/bin \
     /home/test-user/.local/bin

# The port for the Flask is 5000.

EXPOSE 5000

# Make non-root container.

USER test-user

# Runtime environment variables.

ENV LANGUAGE=C
ENV LC_ALL=C
ENV LD_LIBRARY_PATH=/opt/senzing/g2/lib:/opt/senzing/g2/lib/debian:/opt/IBM/db2/clidriver/lib
ENV ODBCSYSINI=/etc/opt/senzing
ENV PATH=${PATH}:/opt/senzing/g2/python:/opt/IBM/db2/clidriver/adm:/opt/IBM/db2/clidriver/bin
ENV PYTHONPATH=/opt/senzing/g2/python
ENV PYTHONUNBUFFERED=1
ENV SENZING_DOCKER_LAUNCHED=true
ENV SENZING_ETC_PATH=/etc/opt/senzing
ENV TERM=xterm

# Runtime execution.

WORKDIR /
CMD gunicorn --bind 0.0.0.0:${PORT:-5000} --worker-class eventlet -w 1 app.app:app
