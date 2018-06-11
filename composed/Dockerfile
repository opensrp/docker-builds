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

RUN apt-get update && \
apt-get install -y mysql-client && \
rm -rf /var/lib/apt/lists/*

# Get Tomcat
RUN wget --quiet --no-cookies https://archive.apache.org/dist/tomcat/tomcat-7/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz -O /tmp/tomcat.tgz && \
tar xzvf /tmp/tomcat.tgz -C /opt && \
mv /opt/apache-tomcat-${TOMCAT_VERSION} /opt/tomcat && \
rm /tmp/tomcat.tgz && \
rm -rf /opt/tomcat/webapps/examples && \
rm -rf /opt/tomcat/webapps/docs && \
rm -rf /opt/tomcat/webapps/ROOT

#COPY opensrp war file to tomcat
ADD webapps/opensrp.war /opt/tomcat/webapps/

# Download openmrs war and modules
RUN curl -O http://liquidtelecom.dl.sourceforge.net/project/openmrs/releases/OpenMRS_Platform_1.11.5/openmrs.war && \
mv openmrs.war /opt/tomcat/webapps && \
mkdir /root/.OpenMRS 

COPY files/openmrs_modules/*.omod /root/.OpenMRS/modules/

ENV CATALINA_HOME /opt/tomcat

ENV PATH $PATH:$CATALINA_HOME/bin

EXPOSE 8080

#Download and configure opensrp server

#Install Maven  
RUN apt-get update && apt-get install -y maven 

#Build arguments
ARG opensrp_server_tag

#openmrs settings
ARG openmrs_url="http:\/\/localhost:8080\/openmrs\/"
ARG openmrs_username=admin
ARG openmrs_password=Admin123

#couchdb settings
ARG couchdb_username=rootuser
ARG couchdb_password=adminpass
ARG couchdb_opensrp_db=opensrp
ARG couchdb_form_db=opensrp-form
ARG couchdb_atomfeed_db=atomfeed
ARG couchdb_mcts_db=opensrp-mcts
ARG couchdb_motech_db=motech-scheduletracking-api
ARG couchdb_error_db=opensrp-errortrace
ENV COUCHDB_USER $couchdb_username
ENV COUCHDB_PASSWORD $couchdb_password

#mysql settings
ARG mysql_opensrp_user=opensrp
ARG mysql_opensrp_password=opensrp
ARG mysql_opensrp_database=opensrp
ARG mysql_openmrs_user=openmrs
ARG mysql_openmrs_password=openmrs
ARG mysql_openmrs_database=openmrs
ARG mysql_motech_database=motechquartz
ARG mysql_reporting_database=report
ARG mysql_anm_database=anm_report
ARG mysql_opensrp_jdbc="jdbc:mysql:\/\/mysql:3306\/${mysql_opensrp_database}?createDatabaseIfNotExist=true"
ARG mysql_opensrp_jdbc_wo="jdbc:mysql:\/\/mysql:3306"
ARG mysql_motech_jdbc="jdbc:mysql:\/\/mysql:3306\/${mysql_motech_database}"
ENV MYSQL_OPENSRP_USER $mysql_opensrp_password
ENV MYSQL_OPENSRP_PASSWORD $mysql_opensrp_user
ENV MYSQL_OPENSRP_DATABASE $mysql_opensrp_database
ENV MYSQL_OPENMRS_DATABASE $mysql_openmrs_database
ENV MYSQL_MOTECH_DATABASE $mysql_motech_database
ENV MYSQL_REPORTING_DATABASE $mysql_reporting_database
ENV MYSQL_ANM_DATABASE $mysql_anm_database
ENV MYSQL_OPENMRS_USER $mysql_openmrs_user
ENV MYSQL_OPENMRS_PASSWORD $mysql_openmrs_password


#redis settings
ARG redis_password=Red1SP@S5
ENV REDIS_PASSWORD $redis_password

#postgres settings
ARG postgres_opensrp_user=opensrp_admin
ARG postgres_opensrp_password=admin
ARG postgres_opensrp_database=opensrp
ARG postgres_opensrp_jdbc="jdbc:postgresql:\/\/postgres:5432\/${postgres_opensrp_database}"
ENV POSTGRES_OPENSRP_DATABASE $postgres_opensrp_database
ENV POSTGRES_OPENSRP_USER $postgres_opensrp_user
ENV POSTGRES_OPENSRP_PASSWORD $postgres_opensrp_password

RUN wget --quiet --no-cookies https://github.com/OpenSRP/opensrp-server/archive/${opensrp_server_tag}.tar.gz -O /tmp/${opensrp_server_tag}.tar.gz 

RUN tar -xf /tmp/${opensrp_server_tag}.tar.gz -C /tmp

#Update property files 
RUN sed -i -e "/openmrs.url\s*=/ s/=.*/=${openmrs_url}/" -e "/openmrs.username\s*=/ s/=.*/=${openmrs_username}/" -e "/openmrs.password\s*=/ s/=.*/=${openmrs_password}/" /tmp/opensrp-server-${opensrp_server_tag}/assets/config/opensrp.properties 

RUN sed -i -e "/couchdb.server\s*=/ s/=.*/=couchdb/" -e "/couchdb.port\s*=/ s/=.*/=5984/" -e "/couchdb.username\s*=/ s/=.*/=${couchdb_username}/" -e "/couchdb.password\s*=/ s/=.*/=${couchdb_password}/" /tmp/opensrp-server-${opensrp_server_tag}/assets/config/opensrp.properties 

RUN sed -i -e "/jdbc.username\s*=/ s/=.*/=${mysql_opensrp_user}/" -e "/jdbc.password\s*=/ s/=.*/=${mysql_opensrp_password}/" -e "/jdbc.url\s*=/ s/=.*/=${mysql_opensrp_jdbc}/" -e "/jdbc.url-wo-db\s*=/ s/=.*/=${mysql_opensrp_jdbc_wo}/" /tmp/opensrp-server-${opensrp_server_tag}/assets/config/opensrp.properties 

RUN sed -i -e "/redis.host\s*=/ s/=.*/=redis/" -e "/redis.port\s*=/ s/=.*/=6379/" -e "/redis.password\s*=/ s/=.*/=${redis_password}/" /tmp/opensrp-server-${opensrp_server_tag}/assets/config/opensrp.properties 

RUN sed -i -e "/host\s*=/ s/=.*/=couchdb/" -e "/port\s*=/ s/=.*/=5984/" -e "/username\s*=/ s/=.*/=${couchdb_username}/" -e "/password\s*=/ s/=.*/=${couchdb_password}/" /tmp/opensrp-server-${opensrp_server_tag}/assets/config/couchdb.properties 

RUN sed -i -e "/org.quartz.dataSource.motechDS.URL\s*=/ s/=.*/=${mysql_motech_jdbc}/" -e "/org.quartz.dataSource.motechDS.user\s*=/ s/=.*/=${mysql_opensrp_user}/" -e "/org.quartz.dataSource.motechDS.password\s*=/ s/=.*/=${mysql_opensrp_password}/" /tmp/opensrp-server-${opensrp_server_tag}/opensrp-web/src/main/resources/quartz.properties 

RUN sed -i -e "/couchdb.db.opensrp\s*=/ s/=.*/=${couchdb_opensrp_db}/" -e "/couchdb.db.form\s*=/ s/=.*/=${couchdb_form_db}/" -e "/couchdb.db.atomfeed\s*=/ s/=.*/=${couchdb_atomfeed_db}/"   /tmp/opensrp-server-${opensrp_server_tag}/build/maven.properties 
RUN sed -i -e "/couchdb.db.mcts\s*=/ s/=.*/=${couchdb_mcts_db}/"  -e "/couchdb.db.motech-scheduletracking\s*=/ s/=.*/=${couchdb_motech_db}/" -e "/couchdb.db.error\s*=/ s/=.*/=${couchdb_error_db}/"   /tmp/opensrp-server-${opensrp_server_tag}/build/maven.properties 

RUN sed -i -e "/db.quartz\s*=/ s/=.*/=${mysql_motech_database}/"  -e "/db.reporting\s*=/ s/=.*/=${mysql_opensrp_database}/" -e "/db.reporting.report\s*=/ s/=.*/=${mysql_reporting_database}/" -e "/db.reporting.anm\s*=/ s/=.*/=${mysql_anm_database}/"   /tmp/opensrp-server-${opensrp_server_tag}/build/maven.properties 

RUN sed -i -e "/username\s*=/ s/=.*/=\"${postgres_opensrp_user}\"/"  -e "/password\s*=/ s/=.*/=\"${postgres_opensrp_password}\"/" -e "/url\s*=/ s/=.*/=\"${postgres_opensrp_jdbc}\"/"  /tmp/opensrp-server-${opensrp_server_tag}/opensrp-web/src/main/webapp/META-INF/context.xml

#compile opensrp war
RUN mvn clean package -Dmaven.test.skip=true -P postgres -f /tmp/opensrp-server-${opensrp_server_tag}/pom.xml && \
cp /tmp/opensrp-server-${opensrp_server_tag}/opensrp-web/target/opensrp.war /opt/tomcat/webapps/

# Copying files
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

COPY sql /opt/sql

COPY sh/*.sh /usr/local/bin/

ENTRYPOINT ["/usr/local/bin/start.sh"]
