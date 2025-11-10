#!/bin/sh

HELP_MSG=$(cat << EOF
This is a basic bash script meant to manage env variables for each and every docker-compose stack.
Refer to the example.env file to see env variables which are needed for the script to work correctly and runs a specified stack.
This is meant to make all the docker services easily portable across systems.

Example usage:
    ./run.sh all 
    ./run.sh stack1 stack2 stack3

Any parameters and flags can be ran in any order.

-h --help
    Print this message

-D --debug
    Print debug messages

--dry-run
    Do not do any write type actions

tear-down
    Tear down docker-compose

update
    Pull latest images and restart stacks

backup
    Backup stack configs and volumes to timestamped directory

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
set -a; [ -f $ENV_FILE ] && . "$ENV_FILE"; set +a

BASE_STORAGE_HDD=$STACK_HDD_STORAGE
BASE_STORAGE_SSD=$STACK_SSD_STORAGE
TARGET_DIRECTORY=$COMPOSE_DIRECTORY

F_DEBUG=false
F_DRY_RUN=false
P_SERVICE_LIST=""
P_ALL=false
P_TEAR_DOWN=false
P_UPDATE=false
P_BACKUP=false
P_VARS_ONLY=false
P_GET_VARS=false
while [ $# -gt 0 ]; do
    case "$1" in
        -h)
            echo "$HELP_MSG"
            exit 0
            ;;
        --help)
            echo "$HELP_MSG"
            exit 0
            ;;
        -D)
            F_DEBUG=true
            shift
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
        update)
            P_UPDATE=true
            shift
            ;;
        backup)
            P_BACKUP=true
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
            P_VARS_ONLY=true
            shift
            break
            ;;
        *)
            [ $P_ALL = true ] && shift && continue
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

        P_SERVICE_LIST="$P_SERVICE_LIST $(basename "$DIR")"
    done
fi 


if [ $F_DEBUG = true ]; then
    echo "[DEBUG]: env file: $ENV_FILE"
    echo "[DEBUG]: dry run: $F_DRY_RUN"
    echo "[DEBUG]: service list: $P_SERVICE_LIST"
    echo "[DEBUG]: all services: $P_ALL"
    echo "[DEBUG]: tear down: $P_TEAR_DOWN"
    echo "[DEBUG]: update: $P_UPDATE"
    echo "[DEBUG]: backup: $P_BACKUP"
    echo "[DEBUG]: vars only: $P_VARS_ONLY"
fi

get_vars_in_file() {
    FILE=$1

    LOCAL_ENV_VARS_IN_FILE=""
    LOCAL_ENV_VARS_IN_FILE=$(grep -Po '(^|[^\$])\K\$\{[a-zA-Z_][a-zA-Z0-9_]*\}' "$FILE" |
        sed 's/^\${\(.*\)}$/\1/' |
        tr -d '\r' |
        awk '!seen[$0]++')

    echo "$LOCAL_ENV_VARS_IN_FILE"
}

validate_env_vars() {
    ENV_VARS_IN_FILE=""
    EXIT_CODE=0

    ENV_VARS_IN_FILE=$(grep -Po '(^|[^\$])\K\$\{[a-zA-Z_][a-zA-Z0-9_]*\}' "$1" | sed 's/^\${\(.*\)}$/\1/')

    OLD_IFS=$IFS
    IFS='
'
    for var_name in $ENV_VARS_IN_FILE; do
        IFS=$OLD_IFS
        # Skip empty lines
        [ -z "$var_name" ] && continue
        
        eval "value=\${$var_name-}"
        if [ -z "$value" ]; then
            EXIT_CODE=1
            printf "Error: Environment variable %s is not set\n" "$var_name" >&2
        fi
    done
    IFS=$OLD_IFS

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
    DIR=$1

    if [ ! -d "$DIR" ]; then
        mkdir -p "$DIR"
    fi
}

backup_stack() {
    DIR="$1"
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    BACKUP_PATH="$BACKUP_DIR/$TIMESTAMP/$DIR"
    CONFIG_PATH="$TARGET_DIRECTORY/$DIR"

    [ $F_DEBUG = true ] && echo "[DEBUG]: Backing up stack $DIR"

    # Create backup directory
    if [ $F_DRY_RUN = false ]; then
        mkdir -p "$BACKUP_PATH"
        echo "Creating backup at: $BACKUP_PATH"
    else
        echo "[DRY RUN] Would create backup at: $BACKUP_PATH"
    fi

    # Backup config directory if it exists
    if [ -d "$CONFIG_PATH/config" ]; then
        [ $F_DEBUG = true ] && echo "[DEBUG]: $DIR: Backing up config directory"
        if [ $F_DRY_RUN = false ]; then
            cp -r "$CONFIG_PATH/config" "$BACKUP_PATH/config"
            echo "  ✓ Backed up config directory"
        else
            echo "  [DRY RUN] Would backup: $CONFIG_PATH/config -> $BACKUP_PATH/config"
        fi
    fi

    # Backup dashboards directory if it exists (for monitoring stack)
    if [ -d "$CONFIG_PATH/dashboards" ]; then
        [ $F_DEBUG = true ] && echo "[DEBUG]: $DIR: Backing up dashboards directory"
        if [ $F_DRY_RUN = false ]; then
            cp -r "$CONFIG_PATH/dashboards" "$BACKUP_PATH/dashboards"
            echo "  ✓ Backed up dashboards directory"
        else
            echo "  [DRY RUN] Would backup: $CONFIG_PATH/dashboards -> $BACKUP_PATH/dashboards"
        fi
    fi

    # Backup dynamic directory if it exists (for traefik stack)
    if [ -d "$CONFIG_PATH/dynamic" ]; then
        [ $F_DEBUG = true ] && echo "[DEBUG]: $DIR: Backing up dynamic directory"
        if [ $F_DRY_RUN = false ]; then
            cp -r "$CONFIG_PATH/dynamic" "$BACKUP_PATH/dynamic"
            echo "  ✓ Backed up dynamic directory"
        else
            echo "  [DRY RUN] Would backup: $CONFIG_PATH/dynamic -> $BACKUP_PATH/dynamic"
        fi
    fi

    # Backup HDD volume data if it exists
    if [ -d "$BASE_STORAGE_HDD/$DIR" ]; then
        [ $F_DEBUG = true ] && echo "[DEBUG]: $DIR: Backing up HDD volume data"
        if [ $F_DRY_RUN = false ]; then
            cp -r "$BASE_STORAGE_HDD/$DIR" "$BACKUP_PATH/volume_hdd"
            echo "  ✓ Backed up HDD volume data"
        else
            echo "  [DRY RUN] Would backup: $BASE_STORAGE_HDD/$DIR -> $BACKUP_PATH/volume_hdd"
        fi
    fi

    # Backup SSD volume data if it exists
    if [ -d "$BASE_STORAGE_SSD/$DIR" ]; then
        [ $F_DEBUG = true ] && echo "[DEBUG]: $DIR: Backing up SSD volume data"
        if [ $F_DRY_RUN = false ]; then
            cp -r "$BASE_STORAGE_SSD/$DIR" "$BACKUP_PATH/volume_ssd"
            echo "  ✓ Backed up SSD volume data"
        else
            echo "  [DRY RUN] Would backup: $BASE_STORAGE_SSD/$DIR -> $BACKUP_PATH/volume_ssd"
        fi
    fi

    if [ $F_DRY_RUN = false ]; then
        echo "Backup completed for $DIR"
    fi
}

run_docker_compose() {
    DIR="$1"
    CONFIG_PATH="$TARGET_DIRECTORY/$DIR"
    DOCKER_COMPOSE_FILE_PATH="$CONFIG_PATH/docker-compose.yml"
    
    [ $F_DEBUG = true ] && echo "[DEBUG]: Running service $DIR"

    export STACK_STORAGE_HDD="$BASE_STORAGE_HDD/$DIR"
    export STACK_STORAGE_SSD="$BASE_STORAGE_SSD/$DIR"
    export DCFP="$DOCKER_COMPOSE_FILE_PATH"

    if [ $P_GET_VARS = true ]; then
        [ $F_DEBUG = true ] && echo "[DEBUG]: $DIR: getting vars"
        ENV_VARS_IN_FILE=$(get_vars_in_file "$DOCKER_COMPOSE_FILE_PATH")
        MISSING=""

        [ $F_DEBUG = true ] && echo "[DEBUG]: $DIR: vars in file $ENV_VARS_IN_FILE"

        for var_name in $ENV_VARS_IN_FILE; do
            # Skip empty lines
            [ -z "$var_name" ] && continue
            [ "$var_name" = "STACK_STORAGE_SSD" ] && continue
            [ "$var_name" = "STACK_STORAGE_HDD" ] && continue

            # [ $F_DEBUG == true ] && echo [DEBUG]: $DIR: Checking $var_name

            # TODO: this for some reason does not work
            if ! check_substring "$ENV_FILE" "$var_name"; then
                # [ $F_DEBUG == true ] && echo [DEBUG]: $DIR: found missing var $var_name
                MISSING="$MISSING$var_name=\n"
            fi
        done

        # Removing training \n
        MISSING="${MISSING%\\n}"
        # [ $F_DEBUG == true ] && echo [DEBUG]: $DIR: about to write $MISSING

        if  [ $F_DRY_RUN = false ] && [ -n "$MISSING" ]; then
            [ $F_DEBUG = true ] && echo "[DEBUG]: $DIR: Writing missing vars to $ENV_FILE"
            if ! check_substring "$ENV_FILE" "$DIR VARS"; then
                {
                    printf '\n'
                    printf '############### %s VARS\n' "$DIR"
                    printf  $MISSING
                    printf  '\n'
                    printf '#####################\n'
                } >> "$ENV_FILE"
            else
                [ $F_DEBUG = true ] && echo "[DEBUG]: $DIR: Updating existing vars section in $ENV_FILE"
                awk -i inplace -v missing="$MISSING" -v dir="$DIR VARS" '
                $0 ~ dir {found=1}
                found && /^#*$/ {print missing; found=0}
                {print}
                ' "$ENV_FILE"
            fi
        fi
        return 0
    fi

    if ! validate_env_vars "$DOCKER_COMPOSE_FILE_PATH" ; then 
        echo "Env variables not configured properly"
        exit 1
    fi

    [ $F_DEBUG = true ] && echo "[DEBUG]: $DIR: Validated env vars"

    if check_substring "$DOCKER_COMPOSE_FILE_PATH" "\${STORAGE_HDD}"; then
        create_dir_if_not_exist "$STORAGE_HDD"
    fi

    [ $F_DEBUG = true ] && echo "[DEBUG]: $DIR: Validated HDD storage"

    if check_substring "$DOCKER_COMPOSE_FILE_PATH" "\${STORAGE_SSD}"; then
        create_dir_if_not_exist "$STORAGE_SSD" 
    fi

    [ $F_DEBUG = true ] && echo "[DEBUG]: $DIR: Validated SSD storage"

    if [ "$F_DRY_RUN" = true ]; then
        echo "$STORAGE_HDD"
        echo "$STORAGE_SSD"
        echo "$DOCKER_COMPOSE_FILE_PATH" 
        docker compose --file "$DOCKER_COMPOSE_FILE_PATH" config
    else 
        if [ $P_VARS_ONLY = true ]; then
            # exec $SHELL -c "$REST"
            eval "$REST"
            return
        fi

        if [ $P_TEAR_DOWN = true ]; then
            [ $F_DEBUG = true ] && echo "[DEBUG]: $DIR: Tearing stack down"
            docker compose --file "$DOCKER_COMPOSE_FILE_PATH" down
        else
            # check if the stack is down
            # if its not down, then bring it down

            RUNNING_SERVICES=$(docker compose --file "$DOCKER_COMPOSE_FILE_PATH" ps -a --services --filter "status=running")
            SERVICES=$(docker compose --file "$DOCKER_COMPOSE_FILE_PATH" ps -a --services)

            [ $F_DEBUG = true ] && echo "[DEBUG]: $DIR: Running services $RUNNING_SERVICES"
            [ $F_DEBUG = true ] && echo "[DEBUG]: $DIR: Services $SERVICES"

            if [ "$RUNNING_SERVICES" = "$SERVICES" ]; then
                [ $F_DEBUG = true ] && echo "[DEBUG]: $DIR: Restarting stack (tear down first)"
                docker compose --file "$DOCKER_COMPOSE_FILE_PATH" down
            fi

            if [ $P_UPDATE = true ]; then
                [ $F_DEBUG = true ] && echo "[DEBUG]: $DIR: Pulling latest images"
                docker compose --file "$DOCKER_COMPOSE_FILE_PATH" pull
            fi
            [ $F_DEBUG = true ] && echo "[DEBUG]: $DIR: Bringing stack up"
            docker compose --file "$DOCKER_COMPOSE_FILE_PATH" up -d
        fi
    fi
}

if [ $P_BACKUP = true ]; then
    if [ -z "$BACKUP_DIR" ]; then
        echo "Error: BACKUP_DIR not set in .env file"
        exit 1
    fi
    [ $F_DEBUG = true ] && echo "[DEBUG]: Backup directory: $BACKUP_DIR"
fi

if [ $F_DRY_RUN = false ] && [ $P_GET_VARS = false ]; then
    create_dir_if_not_exist "$BASE_STORAGE_HDD"
    create_dir_if_not_exist "$BASE_STORAGE_SSD"
fi

for S in $P_SERVICE_LIST; do
    echo "Stack: $S"
    if [ $P_BACKUP = true ]; then
        backup_stack "$S"
    else
        run_docker_compose "$S"
    fi
done
