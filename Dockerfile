FROM ubuntu:xenial

MAINTAINER Ephraim Muhia (emuhia@ona.io)

#Install Postgres

RUN set -ex; \
  if ! command -v gpg > /dev/null; then \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      gnupg \
      dirmngr \
    ; \
    rm -rf /var/lib/apt/lists/*; \
  fi

# explicitly set user/group IDs
RUN groupadd -r postgres --gid=999 && useradd -r -g postgres --uid=999 postgres

# add gosu for easy step-down from root
ENV GOSU_VERSION 1.7
RUN set -x \
  && apt-get update && apt-get install -y --no-install-recommends ca-certificates wget && rm -rf /var/lib/apt/lists/* \
  && wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$(dpkg --print-architecture)" \
  && wget -O /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$(dpkg --print-architecture).asc" \
  && export GNUPGHOME="$(mktemp -d)" \
  && gpg --keyserver ha.pool.sks-keyservers.net --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4 \
  && gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu \
  && rm -r "$GNUPGHOME" /usr/local/bin/gosu.asc \
  && chmod +x /usr/local/bin/gosu \
  && gosu nobody true \
  && apt-get purge -y --auto-remove ca-certificates

RUN mkdir /docker-entrypoint-initdb.d
# make the "en_US.UTF-8" locale so postgres will be utf-8 enabled by default
RUN set -eux; \
  if [ -f /etc/dpkg/dpkg.cfg.d/docker ]; then \
# if this file exists, we're likely in "debian:xxx-slim", and locales are thus being excluded so we need to remove that exclusion (since we need locales)
    grep -q '/usr/share/locale' /etc/dpkg/dpkg.cfg.d/docker; \
    sed -ri '/\/usr\/share\/locale/d' /etc/dpkg/dpkg.cfg.d/docker; \
    ! grep -q '/usr/share/locale' /etc/dpkg/dpkg.cfg.d/docker; \
  fi; \
  apt-get update; apt-get install -y locales; rm -rf /var/lib/apt/lists/*; \
  localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8
ENV LANG en_US.utf8


#RUN apt-get update; apt-get install -y software-properties-common; add-apt-repository 'deb http://archive.ubuntu.com/ubuntu xenial universe' ; apt-get update

# install "nss_wrapper" in case we need to fake "/etc/passwd" and "/etc/group" (especially for OpenShift)
# https://github.com/docker-library/postgres/issues/359
# https://cwrap.org/nss_wrapper.html
#RUN set -eux; \
#  apt-get update; \
#  apt-get install -y --no-install-recommends libnss-wrapper; \
#  rm -rf /var/lib/apt/lists/*

RUN set -ex; \
# pub   4096R/ACCC4CF8 2011-10-13 [expires: 2019-07-02]
#       Key fingerprint = B97B 0AFC AA1A 47F0 44F2  44A0 7FCC 7D46 ACCC 4CF8
# uid                  PostgreSQL Debian Repository
  key='B97B0AFCAA1A47F044F244A07FCC7D46ACCC4CF8'; \
  export GNUPGHOME="$(mktemp -d)"; \
  gpg --keyserver ha.pool.sks-keyservers.net --recv-keys "$key"; \
  gpg --export "$key" > /etc/apt/trusted.gpg.d/postgres.gpg; \
  rm -rf "$GNUPGHOME"; \
  apt-key list

ENV PG_VERSION 10

RUN set -ex; \
  \
  dpkgArch="$(dpkg --print-architecture)"; \
  case "$dpkgArch" in \
    amd64|i386|ppc64el) \
# arches officialy built by upstream
      echo "deb http://apt.postgresql.org/pub/repos/apt/ xenial-pgdg main $PG_VERSION" > /etc/apt/sources.list.d/pgdg.list; \
      apt-get update; \
      ;; \
    *) \
# we're on an architecture upstream doesn't officially build for
# let's build binaries from their published source packages
      echo "deb-src http://apt.postgresql.org/pub/repos/apt/ xenial-pgdg main $PG_VERSION" > /etc/apt/sources.list.d/pgdg.list; \
      \
      tempDir="$(mktemp -d)"; \
      cd "$tempDir"; \
      \
      savedAptMark="$(apt-mark showmanual)"; \
      \
# build .deb files from upstream's source packages (which are verified by apt-get)
      apt-get update; \
      apt-get build-dep -y \
        postgresql-common pgdg-keyring \
        "postgresql-$PG_VERSION" \
      ; \
      DEB_BUILD_OPTIONS="nocheck parallel=$(nproc)" \
        apt-get source --compile \
          postgresql-common pgdg-keyring \
          "postgresql-$PG_VERSION" \
      ; \
# we don't remove APT lists here because they get re-downloaded and removed later
      \
# reset apt-mark's "manual" list so that "purge --auto-remove" will remove all build dependencies
# (which is done after we install the built packages so we don't have to redownload any overlapping dependencies)
      apt-mark showmanual | xargs apt-mark auto > /dev/null; \
      apt-mark manual $savedAptMark; \
      \
# create a temporary local APT repo to install from (so that dependency resolution can be handled by APT, as it should be)
      ls -lAFh; \
      dpkg-scanpackages . > Packages; \
      grep '^Package: ' Packages; \
      echo "deb [ trusted=yes ] file://$tempDir ./" > /etc/apt/sources.list.d/temp.list; \
# work around the following APT issue by using "Acquire::GzipIndexes=false" (overriding "/etc/apt/apt.conf.d/docker-gzip-indexes")
#   Could not open file /var/lib/apt/lists/partial/_tmp_tmp.ODWljpQfkE_._Packages - open (13: Permission denied)
#   ...
#   E: Failed to fetch store:/var/lib/apt/lists/partial/_tmp_tmp.ODWljpQfkE_._Packages  Could not open file /var/lib/apt/lists/partial/_tmp_tmp.ODWljpQfkE_._Packages - open (13: Permission denied)
      apt-get -o Acquire::GzipIndexes=false update; \
      ;; \
  esac; \
  \
  apt-get install -y postgresql-common; \
  sed -ri 's/#(create_main_cluster) .*$/\1 = false/' /etc/postgresql-common/createcluster.conf; \
  apt-get install -y \
    "postgresql-$PG_VERSION" \
  ; \
  \
  rm -rf /var/lib/apt/lists/*; \
  \
  if [ -n "$tempDir" ]; then \
# if we have leftovers from building, let's purge them (including extra, unnecessary build deps)
    apt-get purge -y --auto-remove; \
    rm -rf "$tempDir" /etc/apt/sources.list.d/temp.list; \
  fi

# make the sample config easier to munge (and "correct by default")
RUN mv -v "/usr/share/postgresql/$PG_VERSION/postgresql.conf.sample" /usr/share/postgresql/ \
  && ln -sv ../postgresql.conf.sample "/usr/share/postgresql/$PG_VERSION/" \
  && sed -ri "s!^#?(listen_addresses)\s*=\s*\S+.*!\1 = '*'!" /usr/share/postgresql/postgresql.conf.sample

RUN mkdir -p /var/run/postgresql && chown -R postgres:postgres /var/run/postgresql && chmod 2777 /var/run/postgresql

ENV PATH $PATH:/usr/lib/postgresql/$PG_VERSION/bin
ENV PGDATA /var/lib/postgresql/data
RUN mkdir -p "$PGDATA" && chown -R postgres:postgres "$PGDATA" && chmod 777 "$PGDATA" # this 777 will be replaced by 700 at runtime (allows semi-arbitrary "--user" values)
VOLUME /var/lib/postgresql/data

EXPOSE 5432

# Install mysql

# add our user and group first to make sure their IDs get assigned consistently, regardless of whatever dependencies get added
RUN groupadd -r mysql && useradd -r -g mysql mysql

# FATAL ERROR: please install the following Perl modules before executing /usr/local/mysql/scripts/mysql_install_db:
# File::Basename
# File::Copy
# Sys::Hostname
# Data::Dumper
RUN apt-get update && apt-get install -y perl pwgen --no-install-recommends && rm -rf /var/lib/apt/lists/*

# gpg: key 5072E1F5: public key "MySQL Release Engineering <mysql-build@oss.oracle.com>" imported
RUN apt-key adv --keyserver ha.pool.sks-keyservers.net --recv-keys A4A9406876FCBD3C456770C88C718D3B5072E1F5

#RUN apt-get update; apt-get install -y software-properties-common; add-apt-repository 'deb http://archive.ubuntu.com/ubuntu xenial universe' ; apt-get update
RUN dpkg -l | grep mysql | awk '{print $2}' | xargs -n1 apt-get purge -y

RUN apt-get update; apt-get install -y software-properties-common; add-apt-repository 'deb http://archive.ubuntu.com/ubuntu trusty universe'; apt-get update

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server-5.6 \
 && rm -rf /var/lib/apt/lists/* \
	&& rm -rf /var/lib/mysql && mkdir -p /var/lib/mysql /var/run/mysqld \
	&& chown -R mysql:mysql /var/lib/mysql /var/run/mysqld 

# comment out a few problematic configuration values
# don't reverse lookup hostnames, they are usually another container
RUN sed -Ei 's/^(bind-address|log)/#&/' /etc/mysql/my.cnf \
	&& echo 'skip-host-cache\nskip-name-resolve' | awk '{ print } $1 == "[mysqld]" && c == 0 { c = 1; system("cat") }' /etc/mysql/my.cnf > /tmp/my.cnf \
	&& mv /tmp/my.cnf /etc/mysql/my.cnf

RUN cp /etc/mysql/my.cnf /usr/share/mysql/my-default.cnf

ENV MSDATA /var/lib/mysql

VOLUME /var/lib/mysql

EXPOSE 3306

# Installing supervisord
RUN apt-get update && apt-get install -y supervisor

RUN mkdir -p /var/log/supervisor

# Install Java.
RUN \
  apt-get update && \
  apt-get install -y openjdk-8-jdk && \
  apt-get install -y ant && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/* && \
  rm -rf /var/cache/oracle-jdk8-installer;

# Fix certificate issues, found as of 
# https://bugs.launchpad.net/ubuntu/+source/ca-certificates-java/+bug/983302
RUN apt-get update && \
  apt-get install -y ca-certificates-java && \
  apt-get clean && \
  update-ca-certificates -f && \
  rm -rf /var/lib/apt/lists/* && \
  rm -rf /var/cache/oracle-jdk8-installer;

# Define commonly used JAVA_HOME variable
ENV JAVA_HOME /usr/lib/jvm/java-8-openjdk-amd64

# Installing couchdb

# Install instructions from https://cwiki.apache.org/confluence/display/COUCHDB/Debian

RUN groupadd -r couchdb && useradd -d /var/lib/couchdb -g couchdb couchdb

RUN apt-get update -y && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    erlang-nox \
    libicu55 \
    libmozjs185-1.0 \
    libnspr4 \
    libnspr4-0d \
  && rm -rf /var/lib/apt/lists/*

# https://www.apache.org/dist/couchdb/KEYS
ENV GPG_KEYS \
  15DD4F3B8AACA54740EB78C7B7B7C53943ECCEE1 \
  1CFBFA43C19B6DF4A0CA3934669C02FFDF3CEBA3 \
  25BBBAC113C1BFD5AA594A4C9F96B92930380381 \
  5D680346FAA3E51B29DBCB681015F68F9DA248BC \
  7BCCEB868313DDA925DF1805ECA5BCB7BB9656B0 \
  C3F4DFAEAD621E1C94523AEEC376457E61D50B88 \
  D2B17F9DA23C0A10991AF2E3D9EE01E47852AEE4 \
  E0AF0A194D55C84E4A19A801CDB0C0F904F4EE9B
RUN set -xe \
  && for key in $GPG_KEYS; do \
    gpg --keyserver ha.pool.sks-keyservers.net --recv-keys "$key"; \
  done

ENV COUCHDB_VERSION 1.7.1

# download dependencies, compile and install couchdb,
# set correct permissions, expose couchdb to the outside and disable logging to disk
RUN buildDeps=' \
    gcc \
    g++ \
    erlang-dev \
    libcurl4-openssl-dev \
    libicu-dev \
    libmozjs185-dev \
    libnspr4-dev \
    make \
  ' \
  && apt-get update && apt-get install -y --no-install-recommends $buildDeps \
  && curl -fSL http://apache.osuosl.org/couchdb/source/$COUCHDB_VERSION/apache-couchdb-$COUCHDB_VERSION.tar.gz -o couchdb.tar.gz \
  && curl -fSL https://www.apache.org/dist/couchdb/source/$COUCHDB_VERSION/apache-couchdb-$COUCHDB_VERSION.tar.gz.asc -o couchdb.tar.gz.asc \
  && gpg --verify couchdb.tar.gz.asc \
  && mkdir -p /usr/src/couchdb \
  && tar -xzf couchdb.tar.gz -C /usr/src/couchdb --strip-components=1 \
  && cd /usr/src/couchdb \
  && ./configure --with-js-lib=/usr/lib --with-js-include=/usr/include/mozjs \
  && make && make install \
  && apt-get purge -y --auto-remove $buildDeps \
  && rm -rf /var/lib/apt/lists/* /usr/src/couchdb /couchdb.tar.gz* \
  && chown -R couchdb:couchdb \
    /usr/local/lib/couchdb /usr/local/etc/couchdb \
    /usr/local/var/lib/couchdb /usr/local/var/log/couchdb /usr/local/var/run/couchdb \
  && chmod -R g+rw \
    /usr/local/lib/couchdb /usr/local/etc/couchdb \
    /usr/local/var/lib/couchdb /usr/local/var/log/couchdb /usr/local/var/run/couchdb \
  && mkdir -p /var/lib/couchdb \
  && sed -e 's/^bind_address = .*$/bind_address = 0.0.0.0/' -i /usr/local/etc/couchdb/default.ini \
  && sed -e 's!/usr/local/var/log/couchdb/couch.log$!/dev/null!' -i /usr/local/etc/couchdb/default.ini

# Define mountable directories.
VOLUME ["/usr/local/var/lib/couchdb"]

EXPOSE 5984

# Installing CouchDB lucene
ENV COUCHDB_LUCENE_VERSION 1.1.0

RUN apt-get update \
  && apt-get install -y maven \
  && apt-get install -y unzip \
  && cd /usr/src \
  && curl -L https://github.com/rnewson/couchdb-lucene/archive/v$COUCHDB_LUCENE_VERSION.tar.gz | tar -xz \
  && cd couchdb-lucene-$COUCHDB_LUCENE_VERSION \
  && mvn \
  && cd /usr/src/couchdb-lucene-$COUCHDB_LUCENE_VERSION/target \
  && unzip couchdb-lucene-$COUCHDB_LUCENE_VERSION-dist.zip \
  && mv couchdb-lucene-$COUCHDB_LUCENE_VERSION /opt/couchdb-lucene \
  && rm -rf /usr/src/couchdb-lucene-* \
  && apt-get remove --auto-remove -y maven \
  && rm -rf /var/lib/apt/lists/* \
  && sed -e 's/^host=localhost$/host=0.0.0.0/' -i /opt/couchdb-lucene/conf/couchdb-lucene.ini \
  && sed -e 's/localhost:5984/127.0.0.1:5984/' -i /opt/couchdb-lucene/conf/couchdb-lucene.ini \
  && chown -R couchdb:couchdb /opt/couchdb-lucene

# Link with lucene with couchdb
RUN sed -i -e '$a [couchdb]' /usr/local/etc/couchdb/local.ini
RUN sed -i -e '$a os_process_timeout=60000 ; increase the timeout from 5 seconds. ' /usr/local/etc/couchdb/local.ini
RUN sed -i -e '$a [external]' /usr/local/etc/couchdb/local.ini
RUN sed -i -e '$a fti=/usr/bin/python /opt/couchdb-lucene/tools/couchdb-external-hook.py' /usr/local/etc/couchdb/local.ini
RUN sed -i -e '$a [httpd_db_handlers]' /usr/local/etc/couchdb/local.ini
RUN sed -i -e '$a _fti = {couch_httpd_external, handle_external_req, <<"fti">>}' /usr/local/etc/couchdb/local.ini
RUN sed -i -e '$a [httpd_global_handlers]' /usr/local/etc/couchdb/local.ini
RUN sed -i -e '$a _fti = {couch_httpd_proxy, handle_proxy_req, <<"http:\/\/127.0.0.1:5985">>}' /usr/local/etc/couchdb/local.ini

VOLUME ["/opt/couchdb-lucene/indexes"]

EXPOSE 5985

#Installing activemQ
ENV ACTIVEMQ_VERSION 5.11.1
ENV ACTIVEMQ apache-activemq-$ACTIVEMQ_VERSION

ENV ACTIVEMQ_HOME /opt/activemq
ENV ACTIVEMQ_CONF=${ACTIVEMQ_HOME}/conf
ENV ACTIVEMQ_DATA=${ACTIVEMQ_HOME}/data

RUN \
    curl -O http://archive.apache.org/dist/activemq/$ACTIVEMQ_VERSION/$ACTIVEMQ-bin.tar.gz && \
    mkdir -p /opt && \
    tar xf $ACTIVEMQ-bin.tar.gz -C /opt/ && \
    rm $ACTIVEMQ-bin.tar.gz && \
    ln -s /opt/$ACTIVEMQ $ACTIVEMQ_HOME && \
    useradd -r -M -d $ACTIVEMQ_HOME activemq && \
    chown activemq:activemq /opt/$ACTIVEMQ -R

VOLUME ["${ACTIVEMQ_CONF}", "${ACTIVEMQ_DATA}"]

EXPOSE 61616 8161

# Install tomcat
ENV TOMCAT_VERSION 7.0.72
# Get Tomcat
RUN wget --quiet --no-cookies https://archive.apache.org/dist/tomcat/tomcat-7/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz -O /tmp/tomcat.tgz && \
tar xzvf /tmp/tomcat.tgz -C /opt && \
mv /opt/apache-tomcat-${TOMCAT_VERSION} /opt/tomcat && \
rm /tmp/tomcat.tgz && \
rm -rf /opt/tomcat/webapps/examples && \
rm -rf /opt/tomcat/webapps/docs && \
rm -rf /opt/tomcat/webapps/ROOT

# Download openmrs war and modules
RUN curl -O http://liquidtelecom.dl.sourceforge.net/project/openmrs/releases/OpenMRS_Platform_1.11.5/openmrs.war && \
mv openmrs.war /opt/tomcat/webapps && \
mkdir /root/.OpenMRS && \
curl -O http://netcologne.dl.sourceforge.net/project/keymane/opensrp/opensrp_openmrs_modules.tar.gz && \
tar xzvf opensrp_openmrs_modules.tar.gz  -C /root/.OpenMRS

ENV CATALINA_HOME /opt/tomcat

ENV PATH $PATH:$CATALINA_HOME/bin

VOLUME "/opt/tomcat/webapps"

EXPOSE 8080

# Add mybatis migrations
RUN wget --quiet --no-cookies https://github.com/mybatis/migrations/releases/download/mybatis-migrations-3.3.4/mybatis-migrations-3.3.4-bundle.zip -O /opt/mybatis-migrations-3.3.4.zip

# Unpack the distribution
RUN unzip /opt/mybatis-migrations-3.3.4.zip -d /opt/
RUN rm -f /opt/mybatis-migrations-3.3.4.zip
RUN chmod +x /opt/mybatis-migrations-3.3.4/bin/migrate

# Install Redis
# add our user and group first to make sure their IDs get assigned consistently, regardless of whatever dependencies get added
RUN groupadd -r redis && useradd -r -g redis redis

ENV REDIS_VERSION 4.0.9
ENV REDIS_DOWNLOAD_URL http://download.redis.io/releases/redis-4.0.9.tar.gz
ENV REDIS_DOWNLOAD_SHA df4f73bc318e2f9ffb2d169a922dec57ec7c73dd07bccf875695dbeecd5ec510

# for redis-sentinel see: http://redis.io/topics/sentinel
RUN set -ex; \
  \
  buildDeps=' \
    wget \
    \
    gcc \
    libc6-dev \
    make \
  '; \
  apt-get update; \
  apt-get install -y $buildDeps --no-install-recommends; \
  rm -rf /var/lib/apt/lists/*; \
  \
  wget -O redis.tar.gz "$REDIS_DOWNLOAD_URL"; \
  echo "$REDIS_DOWNLOAD_SHA *redis.tar.gz" | sha256sum -c -; \
  mkdir -p /usr/src/redis; \
  tar -xzf redis.tar.gz -C /usr/src/redis --strip-components=1; \
  rm redis.tar.gz; \
  \
# disable Redis protected mode [1] as it is unnecessary in context of Docker
# (ports are not automatically exposed when running inside Docker, but rather explicitly by specifying -p / -P)
# [1]: https://github.com/antirez/redis/commit/edd4d555df57dc84265fdfb4ef59a4678832f6da
  grep -q '^#define CONFIG_DEFAULT_PROTECTED_MODE 1$' /usr/src/redis/src/server.h; \
  sed -ri 's!^(#define CONFIG_DEFAULT_PROTECTED_MODE) 1$!\1 0!' /usr/src/redis/src/server.h; \
  grep -q '^#define CONFIG_DEFAULT_PROTECTED_MODE 0$' /usr/src/redis/src/server.h; \
# for future reference, we modify this directly in the source instead of just supplying a default configuration flag because apparently "if you specify any argument to redis-server, [it assumes] you are going to specify everything"
# see also https://github.com/docker-library/redis/issues/4#issuecomment-50780840
# (more exactly, this makes sure the default behavior of "save on SIGTERM" stays functional by default)
  \
  make -C /usr/src/redis -j "$(nproc)"; \
  make -C /usr/src/redis install; \
  \
  rm -r /usr/src/redis; \
  \
  apt-get purge -y --auto-remove $buildDeps

RUN mkdir /data && chown redis:redis /data
VOLUME /data

#Download opensrp server
ARG  opensrp_server_tag 
ENV  OPENSRP_TAG $opensrp_server_tag
RUN wget https://github.com/OpenSRP/opensrp-server/archive/${OPENSRP_TAG}.tar.gz -O /tmp/${OPENSRP_TAG}.tar.gz && \
mkdir /migrate && tar -xf /tmp/${OPENSRP_TAG}.tar.gz && cp -R /tmp/opensrp-server-${OPENSRP_TAG}/assets/migrations /migrate 

#Update properties file here

#Install Maven and compile opensrp warfile
RUN apt-get update && apt-get install maven && \
mvn clean install -Dmaven.test.skip=true -P postgres -f /tmp/opensrp-server-${OPENSRP_TAG}/pom.xml &&
cp /tmp/opensrp-server-${OPENSRP_TAG}/opensrp-web/target/opensrp.war /opt/tomcat/webapps/

# Copying files
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

COPY composed/sql /opt/sql

COPY sh/*.sh /usr/local/bin/

ENTRYPOINT ["/usr/local/bin/start.sh"]
