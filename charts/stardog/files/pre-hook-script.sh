#!/bin/bash

# Function to check the readiness of Zookeeper
# Usage: checkZKReadiness "<host:port[,host:port]>" [max_attempts]
checkZKReadiness() {
  local zk_service=$1
  local zk_max_attempts=${2:-120}
  local attempt=1

  if [ -z "$zk_service" ]; then
    echo "ZK service not provided; skipping readiness check."
    return 0
  fi

  local endpoints
  endpoints=$(echo "$zk_service" | tr ',' ' ')

  while [ $attempt -le $zk_max_attempts ]; do
    echo "Attempt $attempt: Checking for ZK readiness"
    for endpoint in $endpoints; do
      local host="${endpoint%%:*}"
      local port="${endpoint##*:}"
      if [ "$host" = "$port" ]; then
        port="2181"
      fi
      local response
      response=$(timeout 2 bash -c "exec 3<>/dev/tcp/$host/$port; printf 'ruok' >&3; head -c 4 <&3; exec 3>&- 3<&-" 2>/dev/null | tr -d '\r\n')
      if [ "$response" = "imok" ]; then
        echo "ZK reports ready at ${host}:${port}"
        return 0
      fi
    done
    sleep 1
    attempt=$((attempt + 1))
  done
  echo "ZK readiness check timed out after $zk_max_attempts attempts."
  return 1
}

waitForTlsSecret() {
  local cert_path=$1
  local key_path=$2
  local max_attempts=${3:-300}
  local attempt=1

  while [ $attempt -le $max_attempts ]; do
    if [ -s "$cert_path" ] && [ -s "$key_path" ]; then
      echo "TLS secret files available."
      return 0
    fi
    echo "Waiting for TLS secret files... ($attempt/$max_attempts)"
    sleep 1
    attempt=$((attempt + 1))
  done

  echo "TLS secret files not ready after ${max_attempts} seconds."
  return 1
}

generateKeystore() {
    # Receive parameters
    # Set default values if parameters are not provided
    KEYSTORE_NAME="${1:-keystore.p12}"
    KEYSTORE_PASS="${2:-changeit}"
    
    
    KEYSTORE_PATH="/var/opt/stardog/keystore"
    CERT_PATH="/var/opt/stardog/ssl"

    echo '{
        "KEYSTORE_NAME": "'"$KEYSTORE_NAME"'",
        "KEYSTORE_PASS": "'"$KEYSTORE_PASS"'"
    }'

    export KEYSTORE_PASS=$KEYSTORE_PASS


     mkdir -p "$KEYSTORE_PATH"

    # Export the certificate and key to a PKCS12 file
    echo "Export the certificate and key to a PKCS12 file"
    openssl pkcs12 -export -in $CERT_PATH/tls.crt -inkey $CERT_PATH/tls.key -out $KEYSTORE_PATH/pkcs.p12 -passout "env:KEYSTORE_PASS"
  
  # Import the PKCS12 file into a Java KeyStore
    keytool -importkeystore -destkeystore $KEYSTORE_PATH/$KEYSTORE_NAME -deststoretype PKCS12 -deststorepass $KEYSTORE_PASS -destkeypass $KEYSTORE_PASS -srckeystore $KEYSTORE_PATH/pkcs.p12 -srcstoretype PKCS12 -srcstorepass $KEYSTORE_PASS -noprompt
    
    echo "Keystore generated at: ${KEYSTORE_PATH}/${KEYSTORE_NAME}"
    
    #remove this line
    #keytool -v -list -keystore $KEYSTORE_PATH/$KEYSTORE_NAME  -storepass $KEYSTORE_PASS

}

findDefaultCacerts() {
  local candidates=()
  if [ -n "${JAVA_HOME:-}" ]; then
    candidates+=("${JAVA_HOME}/lib/security/cacerts")
    candidates+=("${JAVA_HOME}/jre/lib/security/cacerts")
  fi
  candidates+=("/etc/ssl/certs/java/cacerts")
  candidates+=("/usr/lib/jvm/default-jvm/lib/security/cacerts")
  candidates+=("/usr/lib/jvm/default-jvm/jre/lib/security/cacerts")
  candidates+=("/usr/lib/jvm/java-*/lib/security/cacerts")
  candidates+=("/usr/lib/jvm/java-*/jre/lib/security/cacerts")

  for path in "${candidates[@]}"; do
    for candidate in $path; do
      if [ -f "$candidate" ]; then
        echo "$candidate"
        return 0
      fi
    done
  done
  return 1
}

generateTruststore() {
  TRUSTSTORE_NAME="${1:-stardog-truststore.p12}"
  TRUSTSTORE_PASS="${2:-changeit}"
  TRUSTSTORE_SOURCE_PASS="${3:-changeit}"
  TRUSTSTORE_CA_PATH="${4:-}"

  KEYSTORE_PATH="/var/opt/stardog/keystore"
  mkdir -p "$KEYSTORE_PATH"
  TRUSTSTORE_PATH="${KEYSTORE_PATH}/${TRUSTSTORE_NAME}"

  local cacerts_path=""
  cacerts_path=$(findDefaultCacerts || true)
  if [ -n "$cacerts_path" ]; then
    if keytool -list -storetype PKCS12 -keystore "$cacerts_path" -storepass "$TRUSTSTORE_SOURCE_PASS" >/dev/null 2>&1; then
      keytool -importkeystore \
        -srckeystore "$cacerts_path" -srcstoretype PKCS12 -srcstorepass "$TRUSTSTORE_SOURCE_PASS" \
        -destkeystore "$TRUSTSTORE_PATH" -deststoretype PKCS12 -deststorepass "$TRUSTSTORE_PASS" \
        -noprompt
    else
      keytool -importkeystore \
        -srckeystore "$cacerts_path" -srcstoretype JKS -srcstorepass "$TRUSTSTORE_SOURCE_PASS" \
        -destkeystore "$TRUSTSTORE_PATH" -deststoretype PKCS12 -deststorepass "$TRUSTSTORE_PASS" \
        -noprompt
    fi
  else
    echo "Default Java cacerts not found; creating empty truststore at ${TRUSTSTORE_PATH}"
    keytool -genkeypair -alias __temp__ -keystore "$TRUSTSTORE_PATH" -storetype PKCS12 \
      -storepass "$TRUSTSTORE_PASS" -dname "CN=placeholder" -keyalg RSA -keysize 2048 -validity 1 >/dev/null 2>&1 || true
    keytool -delete -alias __temp__ -keystore "$TRUSTSTORE_PATH" -storepass "$TRUSTSTORE_PASS" >/dev/null 2>&1 || true
  fi

  if [ -n "$TRUSTSTORE_CA_PATH" ] && [ -s "$TRUSTSTORE_CA_PATH" ]; then
    local tmp_dir
    tmp_dir="$(mktemp -d)"
    awk 'BEGIN{c=0}/-----BEGIN CERTIFICATE-----/{c++;f=sprintf("%s/ca-%03d.pem",d,c)}{if(f){print > f}}' d="$tmp_dir" "$TRUSTSTORE_CA_PATH"
    for cert in "$tmp_dir"/ca-*.pem; do
      [ -s "$cert" ] || continue
      local alias="extra-ca-$(basename "$cert" .pem)"
      keytool -importcert -alias "$alias" -file "$cert" -keystore "$TRUSTSTORE_PATH" -storepass "$TRUSTSTORE_PASS" -noprompt >/dev/null 2>&1 || true
    done
    rm -rf "$tmp_dir"
  fi

  echo "Truststore generated at: ${TRUSTSTORE_PATH}"
}



########Need to clean up below here ###########
# Call the function with default parameters
#checkZKReadiness $RELEASE_NAME $RELEASE_NAMESPACE

# Or call the function with custom parameters
# checkZKReadiness 40 2

# Function to generate certificates

generateCertificates() {
    # Receive parameters
    # Set default values if parameters are not provided
    KEYSTORE_NAME="${1:-keystore.p12}"
    KEYSTORE_PASS="${2:-changeit}"
    COUNTRY="${3:-US}"
    STATE="${4:-New York}"
    LOCATION="${5:-New York}"
    ORGANIZATION="${6:-Stardog}"
    ORGANIZATION_UNIT="${7:-SA}"
    COMMON_NAME="${8:-helm.stardog.com}"
    EMAIL_ADDRESS="${9:-admin@example.com}"
    DNS_NAME="${10:-DNS:stardog-cluster}"
    
    KEYSTORE_PATH="/var/opt/stardog/keystore"
    CERT_PATH="/var/opt/stardog/ssl"

    echo '{
        "KEYSTORE_PASS": "'"$KEYSTORE_PASS"'",
        "KEYSTORE_NAME": "'"$KEYSTORE_NAME"'",
        "COUNTRY": "'"$COUNTRY"'",
        "STATE": "'"$STATE"'",
        "LOCATION": "'"$LOCATION"'",
        "ORGANIZATION": "'"$ORGANIZATION"'",
        "ORGANIZATION_UNIT": "'"$ORGANIZATION_UNIT"'",
        "COMMON_NAME": "'"$COMMON_NAME"'",
        "EMAIL_ADDRESS": "'"$EMAIL_ADDRESS"'",
        "DNS_NAME": "'"$DNS_NAME"'"
    }'

    export KEYSTORE_PASS=$KEYSTORE_PASS
    
    # # Ensure the CERT_PATH directory exists
    # if [ ! -d "$CERT_PATH" ]; then
    #     echo "Creating directory $CERT_PATH"
    #     mkdir -p "$CERT_PATH"
    # fi

     mkdir -p "$KEYSTORE_PATH"
    # Check if key.pem and myCert.crt already exist in the specified path
    if [ -f "$CERT_PATH/tls.crt" ] && [ -f "$CERT_PATH/tls.key" ]; then
        echo "Certificates already exist in the specified path"
    else
        # Generate a new self-signed certificate
        openssl req -x509 -newkey rsa:4096 \
            -keyout "$CERT_PATH/tls.key" \
            -out "$CERT_PATH/tls.crt" \
            -days 365 -nodes \
            -subj "/C=$COUNTRY/ST=$STATE/L=$LOCATION/O=$ORGANIZATION/OU=$ORGANIZATION_UNIT/CN=$COMMON_NAME/emailAddress=$EMAIL_ADDRESS" \
            -addext "subjectAltName=$DNS_NAME"
    fi
    # Export the certificate and key to a PKCS12 file
    echo "Export the certificate and key to a PKCS12 file"
    openssl pkcs12 -export -in $CERT_PATH/tls.crt -inkey $CERT_PATH/tls.key -out $KEYSTORE_PATH/pkcs.p12 -passout "env:KEYSTORE_PASS"
  
  # Import the PKCS12 file into a Java KeyStore
    keytool -importkeystore -destkeystore $KEYSTORE_PATH/$KEYSTORE_NAME -deststoretype PKCS12 -deststorepass $KEYSTORE_PASS -destkeypass $KEYSTORE_PASS -srckeystore $KEYSTORE_PATH/pkcs.p12 -srcstoretype PKCS12 -srcstorepass $KEYSTORE_PASS -noprompt
    
    echo "Keystore generated at: ${KEYSTORE_PATH}/${KEYSTORE_NAME}"
    
    #remove this line
    keytool -v -list -keystore $KEYSTORE_PATH/$KEYSTORE_NAME  -storepass $KEYSTORE_PASS
}
  

# Call the function
#generateCertificates


# KEYSTORE_PASS="changeit"
# KEYSTORE_NAME="keystore.p12"
# COUNTRY="US"
# STATE="New York"
# LOCATION="Stardog"
# ORGANIZATION="SA"
# ORGANIZATION_UNIT="www.example.com"
# COMMON_NAME="admin@example.com"
# EMAIL_ADDRESS="admin@example.com"
# DNS_NAME="DNS:stardog-cluster1"

# generateCertificates "$KEYSTORE_NAME" "$KEYSTORE_PASS" "$COUNTRY" "$STATE" "$LOCATION" "$ORGANIZATION" "$ORGANIZATION_UNIT" "$COMMON_NAME" "$EMAIL_ADDRESS" "$DNS_NAME"
