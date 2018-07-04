# k8s-canary-deployment
Performing a kubernetes deployment with canary

This is a shell script that can perform a gradual deployment in K8s using canaries.

It uses the kube-help image because it is using kubectl

It does the following

1. Reads the existing deployment from the cluster to a yml file
1. Changes the name of the deployment and the docker image to a new version 
1. Deploys 1 replica for the new version (the canary)
1. Waits for some time (it is configurable) and checks the number of restarts
1. If everything is ok it adds more canaries and scales down the production instances
1. The cycle continues until all replicas used by the service are canaries (the production replicas are zero)

If something goes wrong (the pods have restarts) the scripts deletes all canaries and scales
back the production version to the original number of replicas

The canary percentage is configurable. The script will automatically calculate the phase

Example
 * Production instance has 5 replicas
 * User enters canary waves to 35%
 * Script calculates 35% is about 2 pods
 
 | Phase | Production | Canary |
 | ------------- | ------------- |------|
 | Original | 5 | 0 |
 | A  | 5  |1 |
 | B    | 3 | 3 |
 | C    | 1 | 5 |
 | Final    | 0 | 5 |

Notes:

- The healthcheck is a bit flaky. It only looks at number of restarts and it doesn't actually
wait for the pods to be fully deployed

