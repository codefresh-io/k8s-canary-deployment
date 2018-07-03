#!/bin/bash


healthcheck(){
    echo "Starting Heathcheck"
    h=true
    #Start custom healthcheck
    output=$(kubectl get pods -l app="$CANARY_HOST_NAME" -n canary --no-headers)
    s=($(echo "$output" | awk '{s+=$4}END{print s}'))
    c=($(echo "$output" | wc -l))

    if [ "$s" -gt "2" ]; then
        h=false
    fi
    #End custom healthcheck
    if [ ! $h == true ]; then
        cancel
        echo "Exit failed"
    else
        echo "Service healthy."
    fi
}

cancel(){
    echo "Cancelling rollout"
    
    echo "Restoring original deployment to $PROD_DEPLOYMENT"
    kubectl apply -f $WORKING_VOLUME/original_deployment.yaml -n $NAMESPACE
    kubectl rollout status deployment/$PROD_DEPLOYMENT

    #we could also just scale to 0.
    echo "Removing canary"
    kubectl delete deployment CANARY_DEPLOYMENT

    exit 1
}

incrementservice(){
    percent=$1
    starting_replicas=$2
    
    #debug 
    #echo "Increasing canaries to $percent percent, max replicas is $starting_replicas"

    prod_replicas=$(kubectl get deployment $PROD_DEPLOYMENT -n $NAMESPACE -o=jsonpath='{.spec.replicas}')
    canary_replicas=$(kubectl get deployment $CANARY_DEPLOYMENT -n $NAMESPACE -o=jsonpath='{.spec.replicas}')
    echo "[CANARY] Production has now $prod_replicas, canary has $canary_replicas"

    # This gets the floor for pods, 2.69 will equal 2
    let increment="($percent*$starting_replicas*100)/(100-$percent)/100"

    echo "[CANARY] We will increment canary and decrease production for $increment replicas"

    let new_prod_replicas="$prod_replicas-$increment"
    #Sanity check
    if [ "$new_prod_replicas" -lt "0" ]; then
            new_prod_replicas=0
    fi

    let new_canary_replicas="$canary_replicas+$increment"
    #Sanity check
    if [ "$new_canary_replicas" -gt "$starting_replicas" ]; then
            new_canary_replicas=$starting_replicas
    fi

    echo "[CANARY] Setting canary replicas to $new_canary_replicas"
    kubectl scale --replicas=$new_canary_replicas deploy/$CANARY_DEPLOYMENT 

    echo "[CANARY] Setting production replicas to $new_prod_replicas"
    kubectl scale --replicas=$new_prod_replicas deploy/$PROD_DEPLOYMENT 


    #Wait a bit until production instances are down. This should always succeed
    kubectl rollout status deployment/$PROD_DEPLOYMENT

    #Calulate increments. N = the number of starting pods, I = Increment value, X = how many pods to add
    # x / (N + x) = I 
    # Starting pods N = 5
    # Desired increment I = 0.35
    # Solve for X
    # X / (5+X)= 0.35
    # X = .35(5+x)
    # X = 1.75 + .35x
    # X-.35X=1.75
    # .65X = 1.75
    # X = 35/13
    # X = 2.69
    # X = 3
    # 5+3 = 8 #3/8 = 37.5%
    # Round		A 	B
    # 1			5	3
    # 2			2	6
    # 3			0	5

}

mainloop(){
    #Copy old deployment with new image, set replicas to 1
    echo "kubectl get deployment $PROD_DEPLOYMENT -n $NAMESPACE -o=yaml > $WORKING_VOLUME/canary_deployment.yaml"
    kubectl get deployment $PROD_DEPLOYMENT -n $NAMESPACE -o=yaml > $WORKING_VOLUME/canary_deployment.yaml
    
    echo "keeping a backup of original deployment"
    cp $WORKING_VOLUME/canary_deployment.yaml $WORKING_VOLUME/original_deployment.yaml

    NAME=$(kubectl get deployment $PROD_DEPLOYMENT -n $NAMESPACE -o=jsonpath='{.metadata.name}')
    echo "[CANARY] Reading current docker image"
    IMAGE=$(kubectl get deployment $PROD_DEPLOYMENT -n $NAMESPACE -o=yaml | grep image: | sed -E 's/.*image: (.*)/\1/')
    echo "[CANARY] found image $IMAGE"
    echo "[CANARY] Finding current replicas"
    STARTING_REPLICAS=$(kubectl get deployment $PROD_DEPLOYMENT -n $NAMESPACE --no-headers | awk '{print $2}')
    echo "[CANARY] Found replicas $STARTING_REPLICAS"

    #Replace old name with new
    sed -Ei -- "s/name\: $PROD_DEPLOYMENT/name: $CANARY_DEPLOYMENT/g" $WORKING_VOLUME/canary_deployment.yaml
    echo "[CANARY] Replaced deployment name"

    #Replace image
    sed -Ei -- "s#image: $IMAGE#image: $CANARY_IMAGE#g" $WORKING_VOLUME/canary_deployment.yaml
    echo "[CANARY] Replaced image name"

    #Start with one replica
    sed -Ei -- "s#replicas: $STARTING_REPLICAS#replicas: 1#g" $WORKING_VOLUME/canary_deployment.yaml
    echo "[CANARY] Launching 1 pod with canary"

    #Apply new deployment
    kubectl apply -f $WORKING_VOLUME/canary_deployment.yaml -n $NAMESPACE


    #healthcheck

    while [ $TRAFFIC_INCREMENT -lt 100 ]
    do
        p=$((p + $TRAFFIC_INCREMENT))
        if [ "$p" -gt "100" ]; then
            p=100
        fi
        echo "[CANARY] Rollout is at $p percent"
        
        incrementservice $TRAFFIC_INCREMENT $STARTING_REPLICAS

        if [ "$p" == "100" ]; then
            echo "[CANARY] Done"
            exit 0
        fi
        sleep 5s
    # 	healthcheck
    done
}

if [ "$1" != "" ] && [ "$2" != "" ] && [ "$3" != "" ] && [ "$4" != "" ] && [ "$5" != "" ]; then
    WORKING_VOLUME=${1%/}
    PROD_DEPLOYMENT=$2
    CANARY_DEPLOYMENT=$3
    TRAFFIC_INCREMENT=$4
    NAMESPACE=$5
    CANARY_IMAGE=$6
else
    
    echo "USAGE\n rollout.sh [WORKING_VOLUME] [CURRENT_HOST_NAME] [CANARY_HOST_NAME] [TRAFFIC_INCREMENT]"
    echo "\t [WORKING_VOLUME] - This should be set with \${{CF_VOLUME_PATH}}"
    echo "\t [PROD_DEPLOYMENT] - The name of the service currently receiving traffic from the Istio gateway"
    echo "\t [CANARY_DEPLOYMENT] - The name of the new service we're rolling out."
    echo "\t [TRAFFIC_INCREMENT] - Integer between 1-100 that will step increase traffic"
    echo "\t [NAMESPACE] - Namespace of the application"
    echo "\t [CANARY_IMAGE] - New image url, must use same pull secret"
    exit 1;
fi

echo $BASH_VERSION

mainloop
