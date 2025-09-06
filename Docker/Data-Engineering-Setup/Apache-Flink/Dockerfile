FROM flink:1.20.1-scala_2.12-java17

# Install OpenJDK, Build Tools, and Python
RUN apt-get update && \
    apt-get install -y openjdk-17-jdk build-essential gcc g++ make python3 python3-dev curl vim git && \
    rm -rf /var/lib/apt/lists/*

# Install pip
RUN curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py && \
    python3 get-pip.py && \
    ln -sf /usr/bin/python3 /usr/bin/python && \
    python --version

# Install Apache Flink Python API and other dependencies
RUN python -m pip install --no-cache-dir apache-flink python-dotenv psycopg2-binary python-decouple
ENV FLINK_CONF_DIR=/opt/flink/custom_conf
RUN mkdir -p /opt/flink/custom_conf && \
    cp -r /opt/flink/conf/* /opt/flink/custom_conf/ && \
    rm -f /opt/flink/custom_conf/config.yaml
ADD flink-conf.yaml /opt/flink/custom_conf/config.yaml
RUN chmod 444 /opt/flink/custom_conf/config.yaml
ENV FLINK_PROPERTIES="jobmanager.rpc.address: jobmanager"
# RUN /opt/flink/bin/migrate-config-file.sh
# Download Flink connectors (Kafka, PostgreSQL)
RUN rm -f /opt/flink/connector && mkdir -p /opt/flink/connector && cd /opt/flink/connector && \
curl -LO https://repo.maven.apache.org/maven2/org/apache/flink/flink-sql-connector-kafka/3.3.0-1.20/flink-sql-connector-kafka-3.3.0-1.20.jar && \
curl -LO https://jdbc.postgresql.org/download/postgresql-42.7.4.jar && \
curl -LO https://repo.maven.apache.org/maven2/org/apache/flink/flink-connector-jdbc/3.2.0-1.19/flink-connector-jdbc-3.2.0-1.19.jar


RUN mkdir -p /opt/flink/statebackend
RUN chmod 777 /opt/flink/statebackend
RUN mkdir -p /opt/flink/checkpoints
RUN chmod 777 /opt/flink/checkpoints

