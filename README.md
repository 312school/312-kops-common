# Kubernetes cluster creation with kOps
**Note:** All of the below commands can be run on your local machine (Mac or Windows(use WSL2 Ubuntu))

## Prerequisites
    # install kops
        https://kops.sigs.k8s.io/getting_started/install/
    # install aws cli, if you don't have it
        https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
    # install kubectl, if you don't have it
        https://kubernetes.io/docs/tasks/tools/

## KOPS Cluster Installation
    export K8S_VERSION=1.25.4
    export BUCKET_FOR_KOPS_STATE=312-k8s-kops-state
    export BUCKET_FOR_OIDC=312-k8s-kops-oidc-store
    export DEPLOY_REGION=us-east-1
    export CLUSTER_NAME=312-kops.k8s.local
    
    # create kops state store bucket
    aws s3api create-bucket --bucket "$BUCKET_FOR_KOPS_STATE" --region "$DEPLOY_REGION"
    aws s3api put-bucket-versioning --bucket "$BUCKET_FOR_KOPS_STATE" --versioning-configuration Status=Enabled

    # create separate bucket for oidc store, will be used by serviceaccount+oidc integrations
    aws s3api create-bucket --bucket "$BUCKET_FOR_OIDC" --region "$DEPLOY_REGION" --acl public-read

    # dry-run cluster and adjust configs
    export KOPS_STATE_STORE=s3://$BUCKET_FOR_KOPS_STATE
    kops create cluster \
        --name=${CLUSTER_NAME} \
        --cloud=aws \
        --zones=${DEPLOY_REGION}a \
        --master-count 1 \
        --master-size t3.micro \
        --node-count 2 \
        --node-size t3.micro \
        --kubernetes-version "$K8S_VERSION" \
        --networking calico \
        --api-loadbalancer-class classic \
        --discovery-store=s3://${BUCKET_FOR_OIDC}/${CLUSTER_NAME}/discovery
    
    # create resources, should be run after above dry-run
    kops update cluster --name "${CLUSTER_NAME}" --yes --admin

    # wait for the cluster to be created, below command will watch and wait for the cluster state to become ready
    kops validate cluster --wait 10m
    # you are expected to receive errors until the cluster and related resources are ready.
    # it could take up to 10-15 mins for the cluster to be ready

    # verify that everything is running properly
    kubectl get nodes
    kubectl get po --all-namespaces

---
## Additional useful info (NOT necessary for installation):

    # check current kubeconfig context (current cluster pointer)
    kubectl config current-context

    # switch to this kops cluster context when needed
    kubectl config use-context 312-kops.k8s.local

    # to list contexts in your current ~/.kube/config
    kubectl config get-contexts


    # DANGER ZONE: to delete cluster.
    # Use this also to start from scratch if you mess up somewhere in the installation process.
    export CLUSTER_NAME=312-kops.k8s.local
    kops delete cluster --name ${CLUSTER_NAME} --yes

## Notes
- both Master and Worker nodes are launched in separate AutoScaling Groups
- stopping master and worker nodes manually will only cause AutoScaling Group to create more EC2s as a replacement
    - so proper way to reduce costs is scaling in the ASG group sizes down to 0 (zero)
- official kOps documentation - https://kops.sigs.k8s.io/
