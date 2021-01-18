#!/bin/sh

step="kubesphere"
printf "Starting to run ${step}\n"

. /etc/sysconfig/heat-params

trap "exit 0" EXIT
if [ "$(echo $KUBESPHERE_ENABLED | tr '[:upper:]' '[:lower:]')" == "true" ]; then
    until [ "openebs-hostpath" = "$(kubectl get sc |grep hostpath |awk '{print $1}')" ] && kubectl apply -f "${KUBESPHERE_URL_PREFIX:-https://openebs.github.io/charts/}openebs-operator-1.5.0.yaml"  
    do
        echo "Trying to install kubesphere when openebs is ready."
        sleep 5s
    done
    kubectl patch storageclass openebs-hostpath -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
    kubectl patch storageclass openebs-hostpath -p '{"metadata": {"annotations":{"storageclass.beta.kubernetes.io/is-default-class":"true"}}}'
    sleep 5s
    kubectl apply -f "${KUBESPHERE_URL_PREFIX:-https://github.com/kubesphere/ks-installer/releases/download/v3.0.0/}kubesphere-installer.yaml"
    sleep 5s
    kubectl apply -f "${KUBESPHERE_URL_PREFIX:-https://github.com/kubesphere/ks-installer/releases/download/v3.0.0/}cluster-configuration.yaml"
    echo "Kubectl apply kubesphere successfully."
fi
printf "Finished running ${step}\n"
