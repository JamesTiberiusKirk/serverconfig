#!/bin/sh

HELP_MSG=$(cat << EOF
This is a basic bash script meant to manage env variables for each and every docker-compose stack.
Refer to the example.env file to see env variables which are needed for the script to work correctly and runs a specified stack.
This is meant to make all the docker services easily portable across systems.

Example usage:
    ./run.sh all 
    ./run.sh stack1 stack2 stack3

Any parameters and flags can be ran in any order.

--help
    Print this message

--debug
    Print debug messages

--dry-run
    Do not do any write type actions

tear-down
    Tear down docker-compose

all
    Run on all stacks

vars-only
    Using vars-only does not run any command and allows you to run
        your own command with the computed env vars.
    Bear in mind, any vars which are actually in the command need to be surrounded by single quotes.
    ./run.sh [stacks...] vars-only -- echo '\$STACK_STORAGE_SSD' 

get-vars
    This checks the vars used by a stack then checks to see if they exist in the .env file.
    If they dont exist then it will write the missing vars to the file.
EOF
)

# LOAD .env file
ENV_FILE=./.env
set -a; [ -f $ENV_FILE ] && . $ENV_FILE; set +a

BASE_STORAGE_HDD=$STACK_HDD_STORAGE
BASE_STORAGE_SSD=$STACK_SSD_STORAGE
TARGET_DIRECTORY=$COMPOSE_DIRECTORY

F_DEBUG=false
F_DRY_RUN=false
P_SERVICE_LIST=""
P_ALL=false
P_TEAR_DOWN=false
P_VARS_ONLY=false
P_GET_VARS=false
while [ $# -gt 0 ]; do
    case "$1" in
        --help)
            echo "$HELP_MSG"
            exit 0
            ;;
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
        get-vars)
            P_GET_VARS=true
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

get_vars_in_file() {
    local FILE=$1

    # For some reason uniq doesnt now always work
    # local ENV_VARS_IN_FILE=$(grep -Eo '\$\{[a-zA-Z_][a-zA-Z0-9_]*\}' $FILE | sed 's/^\${\(.*\)}$/\1/' | tr -d '\r' | uniq -i)
    local ENV_VARS_IN_FILE=$(grep -Eo '\$\{[a-zA-Z_][a-zA-Z0-9_]*\}' $FILE |
        sed 's/^\${\(.*\)}$/\1/' |
        tr -d '\r' |
        awk '!seen[$0]++')

    echo $ENV_VARS_IN_FILE
}

validate_env_vars() {
    local ENV_VARS_IN_FILE=$(grep -Eo '\$\{[a-zA-Z_][a-zA-Z0-9_]*\}' $1 | sed 's/^\${\(.*\)}$/\1/')

    local EXIT_CODE=0

    # Read each variable name and check if it exists
    # while IFS= read -r var_name; do
    #     # Skip empty lines
    #     [ -z "$var_name" ] && continue
    #     
    #     if [ ! -n "${!var_name+x}" ]; then
    #         EXIT_CODE=1
    #     fi
    # done <<< "$ENV_VARS_IN_FILE"
    echo "$ENV_VARS_IN_FILE" | while IFS= read -r var_name; do
        # Skip empty lines
        [ -z "$var_name" ] && continue
        
        if [ ! -n "${!var_name+x}" ]; then
            EXIT_CODE=1
        fi
    done

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

    export STACK_STORAGE_HDD=$BASE_STORAGE_HDD$DIR
    export STACK_STORAGE_SSD=$BASE_STORAGE_SSD$DIR
    export DCFP=$DOCKER_COMPOSE_FILE_PATH

    if [ $P_GET_VARS == true ]; then
        [ $F_DEBUG == true ] && echo [DEBUG]: $DIR: getting vars
        ENV_VARS_IN_FILE=$(get_vars_in_file $DOCKER_COMPOSE_FILE_PATH)
        MISSING=""

        [ $F_DEBUG == true ] && echo [DEBUG]: $DIR: vars in file $ENV_VARS_IN_FILE

        for var_name in $ENV_VARS_IN_FILE; do
            # Skip empty lines
            [ -z "$var_name" ] && continue
            [ $var_name == "STACK_STORAGE_SSD" ] && continue
            [ $var_name == "STACK_STORAGE_HDD" ] && continue

            # [ $F_DEBUG == true ] && echo [DEBUG]: $DIR: Checking $var_name

            # TODO: this for some reason does not work
            if ! check_substring $ENV_FILE "$var_name"; then
                # [ $F_DEBUG == true ] && echo [DEBUG]: $DIR: found missing var $var_name
                MISSING+="$var_name=\n"
            fi
        done

        # Removing training \n
        MISSING="${MISSING%\\n}"
        # [ $F_DEBUG == true ] && echo [DEBUG]: $DIR: about to write $MISSING

        if  [ $F_DRY_RUN == false ] && [ ! -z "$MISSING" ]; then 
            if ! check_substring $ENV_FILE "$DIR VARS"; then
                echo "" >> $ENV_FILE
                echo \#\#\#\#\#\#\#\#\#\#\#\#\# $DIR VARS >> $ENV_FILE
                echo -e "$MISSING" >> $ENV_FILE
                echo \#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\# >> $ENV_FILE
            else
                awk -i inplace -v missing="$MISSING" -v dir="$DIR VARS" '
                $0 ~ dir {found=1}
                found && /^#*$/ {print missing; found=0}
                {print}
                ' $ENV_FILE 
            fi
        fi
        return 0
    fi

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

if [ $F_DRY_RUN == false ] && [ $P_GET_VARS == false ]; then 
    create_dir_if_not_exist $BASE_STORAGE_HDD
    create_dir_if_not_exist $BASE_STORAGE_SSD
fi

for S in $P_SERVICE_LIST; do
    echo Stack: $S
    run_docker_compose $S
done
