#!/bin/bash
##
# Variables
##
directory=${HOME}/runners
name=
group=Default
project=
repository=
token=
working_directory=_work
enable_service=false

##
# Function
##
function usage(){
    cat <<EOF
This script installs a gitlab runner.
  
Options:
  -d, --directory            Defines the install directory of a github action runner. Default value is ${HOME}/runners.
  -n, --name                 Defines name of a runner.
  -g, --group                Defines group of a runner.
  -w, --working-directory    Defines working directory of a runner.
  -r, --repository           Defines url of a repository.
  -t, --token                Defines registration token for repository.
  -s, --service              Installs a runner as a service.
  -h, --help                 Shows this message.
  
Examples:
  $(dirname $0)/install.sh --name NAME --group GROUP --repository REPO --token TOKEN
  $(dirname $0)/install.sh -n NAME -r REPO -t TOKEN
EOF
}

function parse_cmd_args() {
    args=$(getopt --options d:n:g:r:t:w:sh \
                  --longoptions directory:,name:,group:,repository:,token:,working-directory:,service,help -- "$@")
    
    if [[ $? -ne 0 ]]; then
        echo "Failed to parse arguments!" && usage
        exit 1;
    fi

    while test $# -ge 1 ; do
        case "$1" in
            -h | --help) usage && exit 0 ;;
            -d | --directory) directory="$(eval echo $2)" ; shift 1 ;;
            -n | --name) name="$(eval echo $2)" ; shift 1 ;;
            -g | --group) group="$(eval echo $2)" ; shift 1 ;;
            -w | --working-directory) working_directory="$(eval echo $2)" ; shift 1 ;;
            -r | --repository) repository="$(eval echo $2)" ; shift 1 ;;
            -s | --service) enable_service=true ;;
            -t | --token) token="$(eval echo $2)" ; shift 1 ;;
            --) ;;
             *) ;;
        esac
        shift 1
    done 
}

function command_exists() {
    if ! command -v $1 2>&1 >/dev/null ; then
        echo "Please, install $1 via your package manager."
        exit 1
    fi
}

function detect_os() {
    os="LINUX"
    case "$(uname -s)" in
        "Darwin") os="MacOS" ;;
    esac
    echo ${os}
}

function get_log_level() {
    case $1 in
        ERROR) echo 1 ;;
        WARN) echo 2 ;;
        INFO) echo 3 ;;
        DEBUG) echo 4 ;;
    esac
}

function log() {
    log_level=${1}
    log_message=$2
    if [[ $(get_log_level ${LOG_LEVEL:-INFO}) -ge $(get_log_level $log_level) ]] ; then
        if [[ "$(detect_os)" == "MacOS" ]] ; then
            echo -e "$(date +"%Y-%m-%d %H:%M:%S") ${log_level}\t $log_message"
        else
            echo -e "$(date +"%Y-%m-%d %H:%M:%S.%3N") ${log_level}\t $log_message"
        fi
    fi
}

##
# Main
##
{

    parse_cmd_args "$@"

    command_exists curl
    command_exists python3

    version_praser=$(cat <<EOF
import sys
import json
import platform

if __name__ == "__main__":
    json_object = json.load(sys.stdin)
    if isinstance(json_object, list):
        print(json_object[0]["name"])
    else:
        raise Exception(json_object.get("message", "Something went wrong"))
EOF
)

    package_name_parser=$(cat <<EOF
import sys
import json
import platform

def normalize_package_name():
    os_name = platform.system()
    if os_name == "Darwin":
        os_name = "darwin"
    elif os_name == "Linux":
        os_name = "linux"
    elif os_name == "Windows":
        os_name = "windows"
    else:
        raise Exception("OS {} is not supported yet.".format(os_name))
    arch = platform.machine().lower()
    if arch == "x86_64":
        arch = "amd64"
    if arch == "x86":
        arch = "amd"
    elif arch == "aarch64":
        arch = "arm64"
    elif arch == "aarch":
        arch = "arm"
    return  "gitlab-runner-{}-{}".format(os_name, arch)

if __name__ == "__main__":
    package_name = normalize_package_name()
    print(package_name)
EOF
)

    if [[ "${name}" == "" ]] ; then
        echo "Please, define a name via --name NAME"
        exit 1
    fi
    
    if [[ "${repository}" == "" ]] ; then
        echo "Please, define an URL of a repository via --repository REPO"
        exit 1
    fi

    if [[ "${token}" == "" ]] ; then
        echo "Please, define a token via --token TOKEN"
        exit 1
    fi

    if [[ "${group}" == "" ]] ; then
        echo "Please, define a group via --group GROUP"
        exit 1
    fi

    runner_directory=${directory}/${name}
    if ! [ -d ${runner_directory} ] ; then
        mkdir -p ${runner_directory}
    fi
    package_name=$(python3 -c "${package_name_parser}")
    runner_version=$(curl -s https://gitlab.com/api/v4/projects/gitlab-org%2Fgitlab-runner/repository/tags | python3 -c "${version_praser}")
    download_url="https://s3.dualstack.us-east-1.amazonaws.com/gitlab-runner-downloads/${runner_version}/binaries/${package_name}"
    binary_path=${runner_directory}/gitlab-runner
    log INFO "Starting to download file from ${download_url}"
    curl -s -L ${download_url} --output ${binary_path}
    log INFO "Changing permission of ${binary_path} to 744"
    chmod 744 ${binary_path}
    cd ${runner_directory}
    ./gitlab-runner register \
        --non-interactive \
        --url ${repository} \
        --token "$token" \
        --executor "shell" \
        --description "${name}"
    if [ ${enable_service} == "true" ] && [ -d /etc/systemd/system ] && [[ $(whoami) == "root" ]] ; then
        systemctl daemon-reload
        systemctl start gitlab-runner-${name}.service
        systemctl enable gitlab-runner-${name}.service
    fi
}
