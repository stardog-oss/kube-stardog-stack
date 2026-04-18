
function wait_for_start {
    HOST=${1}
    PORT=${2}
    PROTOCOL=${3}
    # Wait for Stardog to be running
    COUNT=0
    set +e
    while true; do
      if [[ ${COUNT} -gt 600 ]]; then
          echo "Timeout waiting for Stardog to start."
          return 1
      fi
      if curl -s --head  --request GET ${PROTOCOL}://${HOST}:${PORT}/admin/healthcheck | grep "200 OK" > /dev/null; then
          echo "Stardog is up and running."
          break
      else
          COUNT=$((COUNT+1))
          sleep 1
      fi
    done
    # Give it a second to finish starting up
    sleep 10
    return 0
}

function change_pw {
    (
    set +e
    HOST=${1}
    PORT=${2}
    PROTOCOL=${3}

    echo "/opt/stardog/bin/stardog-admin --server ${PROTOCOL}://${HOST}:${PORT} user passwd -N xxxxxxxxxxxxxx"
    NEW_PW=$(cat /etc/stardog-password/adminpw)
    /opt/stardog/bin/stardog-admin --server ${PROTOCOL}://${HOST}:${PORT} user passwd -N ${NEW_PW}
    if [[ $? -eq 0 ]];
    then
	    echo "Password successfully changed"
	    return 0
    else
    	curl --fail -u admin:${NEW_PW} ${PROTOCOL}://${HOST}:${PORT}/admin/status
    	RC=$?
    	if [[ $RC -eq 0 ]];
      then
        echo "Default password was already changed"
        return 0
      elif [[ $RC -eq 22 ]]
      then
        echo "HTTP 4xx error"
        return $RC
      else
        echo "Something else went wrong"
        return $RC
      fi
    fi
    )
}

function backup_credentials {
    (
    set +e
    HOST=${1}
    USERNAME=${2}
    PASSWORD=${3}

    /opt/stardog/bin/stardog-admin --server ${HOST} user permission -- ${USERNAME}
    if [[ $? -eq 0 ]];
    then
      echo "Backup role and user already exist"
	    return 0
    else
      echo "Creating Backup Role: /opt/stardog/bin/stardog-admin  --server ${HOST} role add backup"
      /opt/stardog/bin/stardog-admin  --server ${HOST} role add backup
      echo "Adding Backup Role permissions:/opt/stardog/bin/stardog-admin  --server ${HOST} role grant backup execute -o 'dbms-admin:backup-all'"  
      /opt/stardog/bin/stardog-admin  --server ${HOST} role grant backup -a execute -o "dbms-admin:backup-all" 
      echo "Creating Backup User: /opt/stardog/bin/stardog-admin  --server ${HOST} user add ${USERNAME} -N ${PASSWORD}" 
      /opt/stardog/bin/stardog-admin  --server ${HOST} user add ${USERNAME} -N ${PASSWORD}
      echo "Adding Backup Role to Backup User:/opt/stardog/bin/stardog-admin  --server ${HOST} user addrole -R backup ${USERNAME}"
      /opt/stardog/bin/stardog-admin  --server ${HOST} user addrole -R backup ${USERNAME}  
      echo "Backup role and user successfully created"
      return 0
    fi
    )
}

function txlog_credentials {
    (
    set +e
    HOST=${1}
    USERNAME=${2}
    PASSWORD=${3}

    /opt/stardog/bin/stardog-admin --server ${HOST} user permission -- ${USERNAME}
    if [[ $? -eq 0 ]];
    then
      echo "Txlog role and user already exist"
	    return 0
    else
      echo "Creating Txlog Role: /opt/stardog/bin/stardog-admin  --server ${HOST} role add txlog"
      /opt/stardog/bin/stardog-admin  --server ${HOST} role add txlog
      # 'execute on admin:*' authorizes `stardog-admin tx log`.
      # 'read on db:*' is required for /admin/databases to return the list of databases
      echo "Adding Txlog Role permissions: /opt/stardog/bin/stardog-admin --server ${HOST} role grant txlog -a execute -o 'admin:*'"
      /opt/stardog/bin/stardog-admin  --server ${HOST} role grant txlog -a execute -o "admin:*"
      echo "Adding Txlog Role permissions: /opt/stardog/bin/stardog-admin --server ${HOST} role grant txlog -a read -o 'db:*'"
      /opt/stardog/bin/stardog-admin  --server ${HOST} role grant txlog -a read -o "db:*"
      echo "Creating Txlog User: /opt/stardog/bin/stardog-admin  --server ${HOST} user add ${USERNAME} -N ${PASSWORD}"
      /opt/stardog/bin/stardog-admin  --server ${HOST} user add ${USERNAME} -N ${PASSWORD}
      echo "Adding Txlog Role to Txlog User: /opt/stardog/bin/stardog-admin --server ${HOST} user addrole -R txlog ${USERNAME}"
      /opt/stardog/bin/stardog-admin  --server ${HOST} user addrole -R txlog ${USERNAME}
      echo "Txlog role and user successfully created"
      return 0
    fi
    )
}

function add_roles {
    (
    set +e
    HOST=${1}
    PORT=${2}
    PROTOCOL=${3}
    ROLE=${4}
    

    echo "/opt/stardog/bin/stardog-admin --server ${PROTOCOL}://${HOST}:${PORT} user passwd -N xxxxxxxxxxxxxx"
    NEW_PW=$(cat /etc/stardog-password/adminpw)
    /opt/stardog/bin/stardog-admin --server ${PROTOCOL}://${HOST}:${PORT} user passwd -N ${NEW_PW}
    if [[ $? -eq 0 ]];
    then
	    echo "Role ${ROLE} successfully Add"
	    return 0
    else
    	curl --fail -u admin:${NEW_PW} ${PROTOCOL}://${HOST}:${PORT}/admin/status
    	RC=$?
    	if [[ $RC -eq 0 ]];
      then
        echo "Default password was already changed"
        return 0
      elif [[ $RC -eq 22 ]]
      then
        echo "HTTP 4xx error"
        return $RC
      else
        echo "Something else went wrong"
        return $RC
      fi
    fi
    )
}

function make_temp {
    (
    set +e
    TEMP_PATH=${1}

    if [ ! -d "$TEMP_PATH" ]; then
      mkdir -p $TEMP_PATH
      if [ $? -ne 0 ]; then
        echo "Could not create stardog tmp directory ${TEMP_PATH}" >&2
        return 1
      fi
    fi
    )
}

function get_license {
    (
    set +e
    LICENSE_SERVER_ENABLED="${1}"
    LICENSE_SERVER=${2}
    LICENSE_TYPE=${3}
    LICENSE_NAME=${4}
    LICENSE_PATH=${5}
    MOUNTED_LICENSE_PATH="/etc/stardog-license/stardog-license-key.bin"

    if [ $LICENSE_SERVER_ENABLED != "true" ]; then
      if [ -f "${LICENSE_PATH}" ]; then
        echo "License server not enabled, using pre-exiting license"
        return 0
      fi

      if [ -f "${MOUNTED_LICENSE_PATH}" ]; then
        cp $MOUNTED_LICENSE_PATH $LICENSE_PATH
        RC=$?
        if [[ $RC -eq 0 ]]; then
          echo "Found a mounted license secret at ${MOUNTED_LICENSE_PATH} and moved it into place at ${LICENSE_PATH}"
          return 0
        else
          echo "Found a mounted license secret at ${MOUNTED_LICENSE_PATH} but could not copy it. Can't start stardog"
          return $RC
        fi
      fi

      echo "No license server provided and no pre-existing license exists. Can't start stardog."
      return 1
    fi

    # make sure we have network
    sleep 5

    PAYLOAD="{\"name\":\"${LICENSE_NAME}\", \"email\":\"ops@stardog.com\", \"company\": \"Stardog Union\", \"version\": \"8\", \"expiresIn\": \"365\", \"clusterSize\": 3, \"flavor\": \"${LICENSE_TYPE}\"}"
    curl --fail -X POST -H 'Content-Type: application/json' -v "${LICENSE_SERVER}" -d "${PAYLOAD}" --output "${LICENSE_PATH}"
    RC=$?

    if [[ $RC -eq 0 ]]; then
      echo "License successfully obtained from ${LICENSE_SERVER} of type ${LICENSE_TYPE}"
    elif [ -f "${LICENSE_PATH}" ]; then
      echo "Could not obtain license from license server ${LICENSE_SERVER}, failing back to using pre-existing license"
      return 0
    else
      echo "Could not obtain license from license server ${LICENSE_SERVER} and no pre-existing license to fall back on. Can't start stardog"
    fi
    return $RC
    )
}
