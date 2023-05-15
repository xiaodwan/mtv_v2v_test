#!/usr/bin/bash

set -exa

readonly SCRIPT_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
readonly TOP_DIR=$(cd "${SCRIPT_DIR}"; git rev-parse --show-toplevel)

source "${TOP_DIR}"/vars.sh

export PATH="${TOP_DIR}/bin":${PATH}

yaml_dir=mtv_yamls
options=(--name --id)

if ! echo "${options[@]}" | grep -Fqw -- "$1"; then
   printf "Please set --name/--id for a vm" 
   exit 1
fi

cmd_option="$1"
shift
target_migration_vms="$@"

THUMBPRINT=$(openssl s_client -connect ${GOVMOMI_URL}:443 < /dev/null 2>/dev/null \
        | openssl x509 -fingerprint -noout -in /dev/stdin \
        | cut -d '=' -f 2)

if [[ ! -d "mtv_yamls" ]]; then
    mkdir mtv_yamls
fi

rm -f mtv_yamls/*.yaml
cp "${TOP_DIR}"/templates/*.yaml mtv_yamls

for var in ${REPLACE_VARS[@]}
do
    #eval tmp_var='$'$(echo ${var}| sed -E s/^__\(.*\)__$/\\1/g)
    eval tmp_var='$'${var:2:-2}
    sed -i -e s/${var}/${tmp_var}/g mtv_yamls/*.yaml
done

datastores=$(mtv_v2v_assister datastore | tail -n +2 | awk -F: '{print $2}')
for datastore in ${datastores}
do
cat << __EOF__ >> ${yaml_dir}/storagemap.yaml
  - destination:
      storageClass: ${STORAGE_CLASS}
    source:
      id: ${datastore}
__EOF__
done

networks=$(mtv_v2v_assister network | tail -n +2 | awk -F: '{print $2}')
for network in ${networks}
do
cat << __EOF__ >> ${yaml_dir}/netmap.yaml
  - destination:
      type: pod
    source:
      id: ${network}
__EOF__
done

for vm in ${target_migration_vms}
do
if [[ ${cmd_option} == "--name" ]]; then
    migrationvm=$(mtv_v2v_assister vm -name ${vm} | tail -n +2 | awk -F: '{print $2}')
else
    migrationvm=${vm}
fi
    cat << __EOF__ >> ${yaml_dir}/migplan.yaml
    # ${vm}
    id: ${migrationvm}
__EOF__
done

