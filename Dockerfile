FROM tomcat:9-jdk11

# Set GeoServer version
ENV GEOSERVER_VERSION=2.25.0
ENV GEOSERVER_BRANCH=2.25.x
ENV GEOSERVER_DATA_DIR=/opt/geoserver/data_dir

# Install required packages
RUN apt-get update && \
    apt-get install -y wget unzip curl postgresql-client && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Remove default Tomcat webapps
RUN rm -rf /usr/local/tomcat/webapps/*

# Download and install GeoServer
RUN wget -q https://sourceforge.net/projects/geoserver/files/GeoServer/${GEOSERVER_VERSION}/geoserver-${GEOSERVER_VERSION}-war.zip && \
    unzip -q geoserver-${GEOSERVER_VERSION}-war.zip && \
    unzip -q geoserver.war -d /usr/local/tomcat/webapps/geoserver && \
    rm geoserver-${GEOSERVER_VERSION}-war.zip geoserver.war

# Download and install extensions (stable releases from SourceForge)
RUN wget --progress=dot:mega https://sourceforge.net/projects/geoserver/files/GeoServer/${GEOSERVER_VERSION}/extensions/geoserver-${GEOSERVER_VERSION}-authkey-plugin.zip -O authkey.zip && \
    unzip -o -q authkey.zip -d /usr/local/tomcat/webapps/geoserver/WEB-INF/lib/ && \
    rm authkey.zip

RUN wget --progress=dot:mega https://sourceforge.net/projects/geoserver/files/GeoServer/${GEOSERVER_VERSION}/extensions/geoserver-${GEOSERVER_VERSION}-css-plugin.zip -O css.zip && \
    unzip -o -q css.zip -d /usr/local/tomcat/webapps/geoserver/WEB-INF/lib/ && \
    rm css.zip

RUN wget --progress=dot:mega https://sourceforge.net/projects/geoserver/files/GeoServer/${GEOSERVER_VERSION}/extensions/geoserver-${GEOSERVER_VERSION}-control-flow-plugin.zip -O control-flow.zip && \
    unzip -o -q control-flow.zip -d /usr/local/tomcat/webapps/geoserver/WEB-INF/lib/ && \
    rm control-flow.zip

RUN wget --progress=dot:mega https://sourceforge.net/projects/geoserver/files/GeoServer/${GEOSERVER_VERSION}/extensions/geoserver-${GEOSERVER_VERSION}-csw-plugin.zip -O csw.zip && \
    unzip -o -q csw.zip -d /usr/local/tomcat/webapps/geoserver/WEB-INF/lib/ && \
    rm csw.zip

RUN wget --progress=dot:mega https://sourceforge.net/projects/geoserver/files/GeoServer/${GEOSERVER_VERSION}/extensions/geoserver-${GEOSERVER_VERSION}-wps-plugin.zip -O wps.zip && \
    unzip -o -q wps.zip -d /usr/local/tomcat/webapps/geoserver/WEB-INF/lib/ && \
    rm wps.zip

RUN wget --progress=dot:mega https://sourceforge.net/projects/geoserver/files/GeoServer/${GEOSERVER_VERSION}/extensions/geoserver-${GEOSERVER_VERSION}-libjpeg-turbo-plugin.zip -O libjpeg-turbo.zip && \
    unzip -o -q libjpeg-turbo.zip -d /usr/local/tomcat/webapps/geoserver/WEB-INF/lib/ && \
    rm libjpeg-turbo.zip

RUN wget --progress=dot:mega https://sourceforge.net/projects/geoserver/files/GeoServer/${GEOSERVER_VERSION}/extensions/geoserver-${GEOSERVER_VERSION}-inspire-plugin.zip -O inspire.zip && \
    unzip -o -q inspire.zip -d /usr/local/tomcat/webapps/geoserver/WEB-INF/lib/ && \
    rm inspire.zip

RUN wget --progress=dot:mega https://sourceforge.net/projects/geoserver/files/GeoServer/${GEOSERVER_VERSION}/extensions/geoserver-${GEOSERVER_VERSION}-monitor-plugin.zip -O monitor.zip && \
    unzip -o -q monitor.zip -d /usr/local/tomcat/webapps/geoserver/WEB-INF/lib/ && \
    rm monitor.zip

RUN wget --progress=dot:mega https://sourceforge.net/projects/geoserver/files/GeoServer/${GEOSERVER_VERSION}/extensions/geoserver-${GEOSERVER_VERSION}-sqlserver-plugin.zip -O sqlserver.zip && \
    unzip -o -q sqlserver.zip -d /usr/local/tomcat/webapps/geoserver/WEB-INF/lib/ && \
    rm sqlserver.zip

RUN wget --progress=dot:mega https://sourceforge.net/projects/geoserver/files/GeoServer/${GEOSERVER_VERSION}/extensions/geoserver-${GEOSERVER_VERSION}-vectortiles-plugin.zip -O vectortiles.zip && \
    unzip -o -q vectortiles.zip -d /usr/local/tomcat/webapps/geoserver/WEB-INF/lib/ && \
    rm vectortiles.zip

# Note: ImagePyramid is included in GeoServer core as of 2.25.0

# Download and install Elasticsearch community module
RUN wget --progress=dot:mega https://build.geoserver.org/geoserver/${GEOSERVER_BRANCH}/community-latest/geoserver-2.25-SNAPSHOT-elasticsearch-plugin.zip -O elasticsearch.zip && \
    unzip -o -q elasticsearch.zip -d /usr/local/tomcat/webapps/geoserver/WEB-INF/lib/ && \
    rm elasticsearch.zip

# Download and install JDBC Store community module (for user/role management)
# DISABLED: Causes conflicts with import mode, keep security in XML for now
# RUN wget --progress=dot:mega https://build.geoserver.org/geoserver/${GEOSERVER_BRANCH}/community-latest/geoserver-2.25-SNAPSHOT-jdbcstore-plugin.zip -O jdbcstore.zip && \
#     unzip -o -q jdbcstore.zip -d /usr/local/tomcat/webapps/geoserver/WEB-INF/lib/ && \
#     rm jdbcstore.zip

# Download and install JDBCConfig community module (for catalog storage in database)
# Note: JDBCConfig is a community module and only available as SNAPSHOT build
RUN wget --progress=dot:mega https://build.geoserver.org/geoserver/${GEOSERVER_BRANCH}/community-latest/geoserver-2.25-SNAPSHOT-jdbcconfig-plugin.zip -O jdbcconfig.zip && \
    unzip -o -q jdbcconfig.zip -d /usr/local/tomcat/webapps/geoserver/WEB-INF/lib/ && \
    rm jdbcconfig.zip

# Create data directory and subdirectories
RUN mkdir -p ${GEOSERVER_DATA_DIR} && \
    mkdir -p ${GEOSERVER_DATA_DIR}/jdbcconfig && \
    mkdir -p ${GEOSERVER_DATA_DIR}/jdbcconfig/scripts

# Extract init scripts from JDBCConfig JAR to data directory
RUN cd /tmp && \
    jar xf /usr/local/tomcat/webapps/geoserver/WEB-INF/lib/gs-jdbcconfig-*.jar && \
    find . -name "initdb*.sql" -exec cp {} ${GEOSERVER_DATA_DIR}/jdbcconfig/scripts/ \; && \
    cd - && rm -rf /tmp/*

# Copy JDBC module configurations
COPY jdbcconfig.properties ${GEOSERVER_DATA_DIR}/jdbcconfig/jdbcconfig.properties

# Copy startup script
COPY entrypoint.sh /opt/entrypoint.sh
RUN chmod +x /opt/entrypoint.sh

# Expose GeoServer port
EXPOSE 8080

# Set entrypoint
ENTRYPOINT ["/opt/entrypoint.sh"]
