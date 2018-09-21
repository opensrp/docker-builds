FROM ubuntu:xenial

MAINTAINER Ephraim Muhia (emuhia@ona.io)


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

# Install netcat client
RUN apt-get update && apt-get install -y netcat

# Install tomcat
ENV TOMCAT_VERSION 7.0.72

# Install dependencies
RUN apt-get update && \
apt-get install -y  build-essential curl wget software-properties-common vim telnet unzip tar

#Create tomcat user
RUN groupadd tomcat && useradd -s /bin/false -g tomcat -d /opt/tomcat tomcat

# Get Tomcat
RUN wget --quiet --no-cookies https://archive.apache.org/dist/tomcat/tomcat-7/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz -O /tmp/tomcat.tgz && \
tar xzvf /tmp/tomcat.tgz -C /opt && \
mv /opt/apache-tomcat-${TOMCAT_VERSION} /opt/tomcat && \
rm /tmp/tomcat.tgz && \
rm -rf /opt/tomcat/webapps/examples && \
rm -rf /opt/tomcat/webapps/docs && \
rm -rf /opt/tomcat/webapps/ROOT

#split opensrp and openmrs tomcat instances
RUN mkdir -p /opt/tomcat/instances/opensrp/bin && mkdir -p /opt/tomcat/instances/opensrp/conf && \
mkdir -p /opt/tomcat/instances/opensrp/webapps && mkdir -p /opt/tomcat/instances/opensrp/logs && \
mkdir -p /opt/tomcat/instances/opensrp/temp && \
cp -R /opt/tomcat/conf /opt/tomcat/instances/opensrp &&  \
cp -R /opt/tomcat/webapps /opt/tomcat/instances/opensrp && \
cp /opt/tomcat/bin/catalina.sh /opt/tomcat/instances/opensrp/bin && \
cp /opt/tomcat/bin/startup.sh /opt/tomcat/instances/opensrp/bin && \
cp /opt/tomcat/bin/shutdown.sh /opt/tomcat/instances/opensrp/bin && \
mkdir -p /opt/tomcat/instances/openmrs && \
cp -R /opt/tomcat/instances/opensrp/* /opt/tomcat/instances/openmrs

RUN touch /opt/tomcat/instances/opensrp/bin/start_opensrp.sh  &&  touch /opt/tomcat/instances/openmrs/bin/start_openmrs.sh && \
chmod +x /opt/tomcat/instances/opensrp/bin/start_opensrp.sh  &&  chmod +x /opt/tomcat/instances/openmrs/bin/start_openmrs.sh 

ARG catalina_opts="-server -Xms512m -Xmx1024m" 
ENV CATALINA_OPTS $catalina_opts

RUN echo '#!/bin/sh\n\
CATALINA_HOME=/opt/tomcat\n\
CATALINA_BASE=/opt/tomcat/instances/opensrp\n\
export CATALINA_HOME CATALINA_BASE CATALINA_OPTS\n\
$CATALINA_HOME/bin/catalina.sh run'\
> /opt/tomcat/instances/opensrp/bin/start_opensrp.sh

RUN echo '#!/bin/sh\n\
CATALINA_HOME=/opt/tomcat\n\
CATALINA_BASE=/opt/tomcat/instances/openmrs\n\
export CATALINA_HOME CATALINA_BASE CATALINA_OPTS\n\
$CATALINA_HOME/bin/catalina.sh run'\
> /opt/tomcat/instances/openmrs/bin/start_openmrs.sh

#change ports for openmrs tomcat
RUN sed -i -e "s/8005/8006/g" -e "s/8180/8181/g" -e "s/8443/8444/g" -e "s/8009/8010/g" /opt/tomcat/instances/openmrs/conf/server.xml 

ENV CATALINA_HOME /opt/tomcat

ENV PATH $PATH:$CATALINA_HOME/bin

EXPOSE 8180 8181

#update tomcat permissions
RUN chown -R tomcat:tomcat /opt/tomcat

# Copying files
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

COPY sh/*.sh /usr/local/bin/  

ENTRYPOINT ["/usr/local/bin/start.sh"]
