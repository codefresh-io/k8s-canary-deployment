FROM codefresh/kube-helm:master

RUN mkdir /app

COPY k8s-canary-rollout.sh /app

RUN chmod +x /app/k8s-canary-rollout.sh

CMD /app/k8s-canary-rollout.sh $WORKING_VOLUME $PROD_DEPLOYMENT $CANARY_DEPLOYMENT $TRAFFIC_INCREMENT $NAMESPACE $CANARY_IMAGE $SECONDS