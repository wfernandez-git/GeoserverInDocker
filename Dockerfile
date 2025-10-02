FROM tomcat:9-jdk11

# Set GeoServer version
ENV GEOSERVER_VERSION=2.24.5
ENV GEOSERVER_BRANCH=2.24.x
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

# Download and install AuthKey extension
RUN wget --progress=dot:mega https://build.geoserver.org/geoserver/${GEOSERVER_BRANCH}/ext-latest/geoserver-2.24-SNAPSHOT-authkey-plugin.zip -O authkey.zip && \
    unzip -o -q authkey.zip -d /usr/local/tomcat/webapps/geoserver/WEB-INF/lib/ && \
    rm authkey.zip

# Download and install JDBC Store community module (for user/role management)
RUN wget --progress=dot:mega https://build.geoserver.org/geoserver/${GEOSERVER_BRANCH}/community-latest/geoserver-2.24-SNAPSHOT-jdbcstore-plugin.zip -O jdbcstore.zip && \
    unzip -o -q jdbcstore.zip -d /usr/local/tomcat/webapps/geoserver/WEB-INF/lib/ && \
    rm jdbcstore.zip

# Create data directory
RUN mkdir -p ${GEOSERVER_DATA_DIR}

# Copy startup script
COPY entrypoint.sh /opt/entrypoint.sh
RUN chmod +x /opt/entrypoint.sh

# Expose GeoServer port
EXPOSE 8080

# Set entrypoint
ENTRYPOINT ["/opt/entrypoint.sh"]
