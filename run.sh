#!/bin/sh

# LOAD .env file
ENV_FILE=./.env
set -a; [ -f $ENV_FILE ] && . $ENV_FILE; set +a

BASE_STORAGE_HDD=$POD_HDD_STORAGE
BASE_STORAGE_SSD=$POD_SSD_STORAGE
TARGET_DIRECTORY=$COMPOSE_DIRECTORY

F_DEBUG=false
F_DRY_RUN=false
P_SERVICE_LIST=""
P_ALL=false
P_TEAR_DOWN=false
P_VARS_ONLY=false
while [ $# -gt 0 ]; do
    case "$1" in
        --debug)
            F_DEBUG=true
            shift
            ;;
        --dry-run)
            F_DRY_RUN=true
            shift
            ;;
        all)
            P_ALL=true
            shift
            ;;
        tear-down)
            P_TEAR_DOWN=true
            shift
            ;;
        vars-only)
            P_VARS_ONLY=true
            shift
            ;;
        "--")
            shift
            break
            ;;
        *)
            [ P_ALL = true ] && continue
            if [ -d "$TARGET_DIRECTORY/$1" ]; then 
                P_SERVICE_LIST="$P_SERVICE_LIST $1"
            else
                echo "[ERROR]: Unknown args"
                exit 1
            fi
            shift
            ;;
    esac
done

REST=$*

if [ $P_ALL = true ]; then 
    P_SERVICE_LIST=""
    for DIR in "$TARGET_DIRECTORY"/*; do
        if [ ! -d "$DIR" ]; then
            continue
        fi

        if [ ! -f "$DIR/docker-compose.yml" ]; then
            continue
        fi

        P_SERVICE_LIST="$P_SERVICE_LIST $(basename $DIR)"
    done
fi 

if [ $F_DEBUG = true ]; then 
    echo [DEBUG]: dry run: $F_DRY_RUN
    echo [DEBUG]: service list: $P_SERVICE_LIST
    echo [DEBUG]: all services: $P_ALL
    echo [DEBUG]: tear down: $P_TEAR_DOWN
    echo [DEBUG]: vars only: $P_VARS_ONLY
fi

validate_env_vars() {
    local ENV_VARS_IN_FILE=$(grep -Eo '\$\{[a-zA-Z_][a-zA-Z0-9_]*\}' $1 | sed 's/^\${\(.*\)}$/\1/')

    local EXIT_CODE=0

    # Read each variable name and check if it exists
    while IFS= read -r var_name; do
        # Skip empty lines
        [ -z "$var_name" ] && continue
        
        if [ ! -n "${!var_name+x}" ]; then
            EXIT_CODE=1
        fi
    done <<< "$ENV_VARS_IN_FILE"

    return $EXIT_CODE 
}

check_substring() {
    if grep -q "$2" "$1"; then
        return 0
    else
        return 1
    fi
}

create_dir_if_not_exist() {
    local DIR=$1

    if [ ! -d "$DIR" ]; then
        mkdir -p $DIR
    fi
}

run_docker_compose() {
    local DIR="$1"
    local CONFIG_PATH="$TARGET_DIRECTORY/$DIR"
    local DOCKER_COMPOSE_FILE_PATH=$CONFIG_PATH/docker-compose.yml
    
    [ $F_DEBUG == true ] && echo [DEBUG]: Running service $DIR

    export POD_STORAGE_HDD=$BASE_STORAGE_HDD$DIR
    export POD_STORAGE_SSD=$BASE_STORAGE_SSD$DIR
    export DCFP=$DOCKER_COMPOSE_FILE_PATH

    if ! validate_env_vars $DOCKER_COMPOSE_FILE_PATH; then 
        echo Env variables not configured properly
        exit 1
    fi
    [ $F_DEBUG == true ] && echo [DEBUG]: $DIR: Validated env vars

    if check_substring $DOCKER_COMPOSE_FILE_PATH "\${STORAGE_HDD}"; then
        create_dir_if_not_exist $STORAGE_HDD
    fi

    [ $F_DEBUG == true ] && echo [DEBUG]: $DIR: Validated HDD storage 

    if check_substring $DOCKER_COMPOSE_FILE_PATH "\${STORAGE_SSD}"; then
        create_dir_if_not_exist $STORAGE_SSD
    fi

    [ $F_DEBUG == true ] && echo [DEBUG]: $DIR: Validated SSD storage 

    if [ "$F_DRY_RUN" == true ]; then
        echo $STORAGE_HDD
        echo $STORAGE_SSD
        echo $DOCKER_COMPOSE_FILE_PATH
        docker-compose --file $DOCKER_COMPOSE_FILE_PATH config
    else 
        if [ $P_VARS_ONLY == true ]; then
            exec $SHELL -c "$REST"
            exit 0
        fi

        # check if the stack is down 
        # if its not down, then bring it down
        
        RUNNING_SERVICES=$(docker-compose --file $DOCKER_COMPOSE_FILE_PATH ps -a --services --filter "status=running")
        SERVICES=$(docker-compose --file $DOCKER_COMPOSE_FILE_PATH ps -a --services)


        [ $F_DEBUG == true ] && echo [DEBUG]: $DIR: Running services $RUNNING_SERVICES
        [ $F_DEBUG == true ] && echo [DEBUG]: $DIR: Services $SERVICES

        if [ "$RUNNING_SERVICES" == "$SERVICES" ]; then 
            [ $F_DEBUG == true ] && echo [DEBUG]: $DIR: Tearning stack down
            docker-compose --file $DOCKER_COMPOSE_FILE_PATH down
        fi

        if [ $P_TEAR_DOWN == false ]; then 
            [ $F_DEBUG == true ] && echo [DEBUG]: $DIR: Bringing stack up
            docker-compose --file $DOCKER_COMPOSE_FILE_PATH up -d
        fi
    fi
}

create_dir_if_not_exist $BASE_STORAGE_HDD
create_dir_if_not_exist $BASE_STORAGE_SSD

for S in $P_SERVICE_LIST; do
    echo Running commands on stack: $S
    run_docker_compose $S
done
