#!/usr/bin/env bash

set -e

ONEUPTIME_SECRET=$(openssl rand -hex 12)
export ONEUPTIME_SECRET=$ONEUPTIME_SECRET

DATABASE_PASSWORD=$(openssl rand -hex 12)
export DATABASE_PASSWORD=$DATABASE_PASSWORD

CLICKHOUSE_PASSWORD=$(openssl rand -hex 12)
export CLICKHOUSE_PASSWORD=$CLICKHOUSE_PASSWORD

REDIS_PASSWORD=$(openssl rand -hex 12)
export REDIS_PASSWORD=$REDIS_PASSWORD

ENCRYPTION_SECRET=$(openssl rand -hex 12)
export ENCRYPTION_SECRET=$ENCRYPTION_SECRET

INTERNAL_SMTP_PASSWORD=$(openssl rand -hex 12)
export INTERNAL_SMTP_PASSWORD=$INTERNAL_SMTP_PASSWORD

GLOBAL_PROBE_KEY=$(openssl rand -hex 12)
export GLOBAL_PROBE_KEY=$GLOBAL_PROBE_KEY


# Talk to the user
echo "Welcome to the OneUptime 🟢 Runner"
echo ""
echo ""
echo ""

echo "Please enter your sudo password now:"
sudo echo ""
echo "Thanks! 🙏"
echo ""
echo "Ok! We'll take it from here 🚀"

echo "Making sure any stack that might exist is stopped"


# If Mac
if [[ "$OSTYPE" == "darwin"* ]]; then
    if [[ ! $(which brew) ]]; then
        echo "Homebrew not installed. Please install homebrew and restart installer"
        exit
    fi
fi

# If linux
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "Grabbing latest apt caches"
    sudo apt update
fi

# clone oneuptime
echo "Installing OneUptime 🟢"
if [[ ! $(which git) ]]; then
    if [[ "$OSTYPE" != "darwin"* ]]; then
        sudo apt install -y git
    fi
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install git
    fi
fi


if [[ $IS_DOCKER == "true" ]]
then
    echo "This script should run in the docker container."
else
    GIT_REPO_URL=$(git config --get remote.origin.url)

    if [[ $GIT_REPO_URL != *oneuptime* ]] # * is used for pattern matching
    then
        git clone https://github.com/OneUptime/oneuptime.git || true
        cd oneuptime
    fi
fi



# if this script is not running in CI/CD
if [ -z "$CI_PIPELINE_ID" ]
then
    if [[ $IS_DOCKER == "true" ]]
    then
        echo "Running in docker container. Skipping git pull."
    else
        git pull
    fi
fi

cd ..

if [[ ! $(which node) && ! $(node --version) ]]; then
    if [[ "$OSTYPE" != "darwin"* ]]; then
        echo "Setting up NodeJS"
        sudo curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.3/install.sh | bash
        export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" # This loads nvm
        nvm install lts/*
        nvm use lts/*
        sudo ln -s "$NVM_DIR/versions/node/$(nvm version)/bin/node" "/usr/local/bin/node"
        sudo ln -s "$NVM_DIR/versions/node/$(nvm version)/bin/npm" "/usr/local/bin/npm"
    fi

    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install nodejs
    fi
fi


if [[ ! $(which npm) && ! $(npm --version) ]]; then
    if [[ "$OSTYPE" != "darwin"* ]]; then
        echo "Setting up NPM"
        sudo apt-get install -y npm
    fi
fi

if [[ ! $(which docker) && ! $(docker --version) ]]; then
  echo "Setting up Docker"
  sudo curl -sSL https://get.docker.com/ | sh  
fi


# If docker still fails to install, then quit. 
if [[ ! $(which docker) && ! $(docker --version) ]]; then
  echo -e "Failed to install docker. Please install Docker manually here: https://docs.docker.com/install."
  echo -e "Exiting the OneUptime installer."
  exit
fi


# enable docker without sudo
sudo usermod -aG docker "${USER}" || true

if [[ ! $(which docker-compose) && ! $(docker compose --version) ]]; then
mkdir -p /usr/local/lib/docker/cli-plugins
sudo curl -SL https://github.com/docker/compose/releases/download/v2.12.2/docker-compose-$(uname -s)-$(uname -m) -o /usr/local/lib/docker/cli-plugins/docker-compose
sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
docker compose version
fi

if [[ ! $(which gomplate) ]]; then
    ARCHITECTURE=$(uname -m)

    if [[ $ARCHITECTURE == "aarch64" ]]; then
        ARCHITECTURE="arm64"
    fi

    if [[ $ARCHITECTURE == "x86_64" ]]; then
        ARCHITECTURE="amd64"
    fi

    echo "ARCHITECTURE:"
    echo "$(uname -s) $(uname -m)"

    sudo curl -o /usr/local/bin/gomplate -sSL https://github.com/hairyhenderson/gomplate/releases/download/v3.11.3/gomplate_$(uname -s)-$ARCHITECTURE
    sudo chmod 755 /usr/local/bin/gomplate
fi



if [[ ! $(which ts-node) ]]; then
    sudo npm install -g ts-node
fi

cd oneuptime

# Generate Self Signed SSL certificate. 

CERT=./Certs/ServerCerts/Cert.crt
if test -f "$CERT"; then
    echo "SSL Certificate exists. Skipping generating a new one."
else
    echo "SSL Certificate not found. Generating a new certificate."
    openssl req -new -x509 -nodes -subj "/C=GB/ST=London/L=London/O=Global Security/OU=IT Department/CN=example.com" -out ./Certs/ServerCerts/Cert.crt -keyout ./Certs/ServerCerts/Key.key -days 99999
fi

# Create .env file if it does not exist. 
touch config.env

# Reload terminal with newly installed packages.
source ~/.bashrc

#Run a scirpt to merge config.env.tpl to config.env
ts-node-esm ./Scripts/Install/MergeEnvTemplate.ts


# Load env values from config.env
source config.env

# Write env vars in config files. 


for directory_name in $(find . -maxdepth 1 -type d) ; do
    if [ -f "$directory_name/Dockerfile.tpl" ]; then
        cat $directory_name/Dockerfile.tpl | gomplate > $directory_name/Dockerfile
    fi
done