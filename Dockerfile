#This file is Created by Viraj Kushwaha
# Jenkins LTS with corporate SSL trust preconfigured (no plugins preinstalled)
FROM jenkins/jenkins:lts-jdk17

USER root

# Tools we need to fetch and install certificates and to test TLS connectivity
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates ca-certificates-java openssl curl \
    && rm -rf /var/lib/apt/lists/*

# Build-arg: hosts to fetch full cert chains from (edit if needed)

# These are the Albony endpoints you used earlier
ARG CERT_HOSTS="mirror.bom2.albony.in:443 mirror.del.albony.in:443"

# Location for our combined corporate CA bundle inside the image
ENV SSL_CORP_BUNDLE=/usr/local/share/ca-certificates/corp-bundle.crt

# --- Fetch certs from the given hosts, dedupe, and trust them system-wide and in Java ---
RUN set -eux; \
    : > "$SSL_CORP_BUNDLE"; \
    for h in $CERT_HOSTS; do \
      echo ">>> Fetching cert chain from $h"; \
      # grab full chain and append all PEM blocks
      openssl s_client -showcerts -connect "$h" </dev/null 2>/dev/null \
        | awk '/BEGIN CERTIFICATE/{flag=1} flag; /END CERTIFICATE/{print; flag=0}' \
        >> "$SSL_CORP_BUNDLE" || true; \
    done; \
    # Deduplicate identical PEM blocks (best effort)
    awk 'BEGIN{RS="";FS="\n"}{if(!seen[$0]++){print $0"\n"}}' ORS="" "$SSL_CORP_BUNDLE" > "${SSL_CORP_BUNDLE}.tmp" || true; \
    mv "${SSL_CORP_BUNDLE}.tmp" "$SSL_CORP_BUNDLE"; \
    if [ -s "$SSL_CORP_BUNDLE" ]; then \
      chmod 0644 "$SSL_CORP_BUNDLE"; \
      echo ">>> Updating system trust"; \
      update-ca-certificates || true; \
      echo ">>> Syncing Java truststore"; \
      /var/lib/dpkg/info/ca-certificates-java.postinst configure || true; \
      CACERTS="$(/bin/bash -lc 'readlink -f $(dirname $(readlink -f $(which java)))/../lib/security/cacerts')" || true; \
      if [ -f "${CACERTS:-}" ]; then \
        keytool -importcert -trustcacerts \
          -keystore "$CACERTS" -storepass changeit -noprompt \
          -alias corp-bundle -file "$SSL_CORP_BUNDLE" || true; \
      fi; \
    else \
      echo "WARNING: No certificates captured from CERT_HOSTS. Proceeding without custom CA."; \
    fi

# Make Jenkins use the Java truststore we just updated
ENV JAVA_OPTS="-Djavax.net.ssl.trustStore=/etc/ssl/certs/java/cacerts -Djavax.net.ssl.trustStorePassword=changeit -Dhttps.protocols=TLSv1.2,TLSv1.3"

# Keep Jenkins update centers on HTTPS
ENV JENKINS_UC="https://updates.jenkins.io" \
    JENKINS_UC_DOWNLOAD="https://updates.jenkins.io/download"

# (Optional) quick TLS smoke-test during build (commented out to avoid failing builds in restricted nets)
# RUN curl -fsSI https://updates.jenkins.io/update-center.json >/dev/null


#This File is created by Viraj Kushwaha



# No plugin preinstallation here. The setup wizard stays ON by default.
USER jenkins

