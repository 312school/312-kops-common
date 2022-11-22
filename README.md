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
    account=$(aws sts get-caller-identity --query 'Account' --output text)
    export K8S_VERSION=1.25.4
    export BUCKET_FOR_KOPS_STATE=312-k8s-kops-state-${account}
    export BUCKET_FOR_OIDC=312-k8s-kops-oidc-store-${account}
    export DEPLOY_REGION=us-east-1
    export CLUSTER_NAME=312-kops.k8s.local
    
    # create kops state store bucket
    aws s3api create-bucket --bucket "$BUCKET_FOR_KOPS_STATE" --region "$DEPLOY_REGION"
    aws s3api put-bucket-versioning --bucket "$BUCKET_FOR_KOPS_STATE" --versioning-configuration Status=Enabled

    # create separate bucket for oidc store, will be used by serviceaccount+oidc integrations
    aws s3api create-bucket --bucket "$BUCKET_FOR_OIDC" --region "$DEPLOY_REGION" --acl public-read

    # dry-run cluster and adjust configs
    export KOPS_STATE_STORE="s3://$BUCKET_FOR_KOPS_STATE"
    kops create cluster \
        --name=${CLUSTER_NAME} \
        --cloud=aws \
        --zones=${DEPLOY_REGION}a \
        --master-count 1 \
        --master-size t3.medium \
        --master-volume-size 10 \
        --node-count 2 \
        --node-size t3.micro \
        --node-volume-size 8 \
        --kubernetes-version "$K8S_VERSION" \
        --networking cilium \
        --api-loadbalancer-class network \
        --discovery-store=s3://${BUCKET_FOR_OIDC}/${CLUSTER_NAME}/discovery
    
    # create resources, should be run after above dry-run
    kops update cluster --name "${CLUSTER_NAME}" --yes --admin

    # wait for the cluster to be created, below command will watch and wait for the cluster state to become ready
    kops validate cluster --wait 10m
    # you are expected to receive errors until the cluster and related resources are ready.
    # it could take up to 10 mins for the cluster to be ready, but usually takes less than 5 mins.

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
- Both Master and Worker nodes are launched in separate AutoScaling Groups
    - Stopping master and worker nodes manually will only cause AutoScaling Group to create more EC2s as a replacement
        - so proper way to reduce costs is scaling in the ASG group sizes down to 0 (zero)
    ![Screenshot 2022-11-21 at 8 53 15 PM](https://user-images.githubusercontent.com/43100287/203209740-69566769-1573-49bb-a7d5-d5e314a689fe.png)

- **Cost of the Resources Disclaimer**:
    - **To make sure you incur very minimal charges**:
        in AWS Console, set desired and minimum ASG size for both master and worker node AutoScaling Groups to 0(zero) when you don't need the cluster.
        and then bring back master ASG to 1 and workers ASG to 2 whenever you need a cluster.
    - Master node uses t3.medium type which is the minimum for it's needs. It will cost about $30 if you keep it running for a whole month.
    - Worker nodes use t3.micro instances which are in free tier, but you will pay extra if you keep at least 2 running for a whole month. t3.micro instance that's under free tier will cost $7.5/month.
    - EBS volumes(AWS has 30GB free tier limit, and $0.08/GB-month afterwards):
        - master node has 3 volumes: 1 for itself - 10GB. 2 for etcd stores - each 20GB.
        - worker nodes have 1 volume each - 8GB.
    - So assuming you don't resize your ASG to 0 as recommended above when you don't need cluster, total estimates are:
        - if you keep all nodes running for a whole month, approximate cost in us-east-1: `$30.096(t3.medium) + $2.88(gp3) + $7.488 = $40.464`
        - if you keep all nodes running for a half-month, approximate cost in us-east-1: `$15.048(t3.medium) + $2.88(gp3) = $17.928`
        - if you keep all nodes running for 40 hours/week, approximate cost in us-east-1: `$6.688(t3.medium) + $2.88(gp3) = $9.568`
        - if you keep all nodes running for 20 hours/week, approximate cost in us-east-1: `$3.344(t3.medium) + $2.88(gp3) = $6.224`

## Additional knowledge
- bucket names are globally unique in S3, therefore we have added `-${account}` suffix to keep your bucket names unique and consistent at the same time.
- kOps creates a Network Load Balancer that exposes cluster's Kubernetes API to public with a static DNS name.
    - This allows you to connect to K8s cluster anywhere from the internet including from your local machine.
    - This NLB address is written down by kOps into your local ~/.kube/config file when creating the cluster with kOps.
        - if you have switched to another cluster later on(ex: to eks), you can switch back to this kOps cluster using `kubectl config use-context 312-kops.k8s.local`
    - AWS provides NLB in free tier for a whole month.
- `etcd` data is stored on 2 dedicated EBS volumes that are attached to the master node. When master node is deleted, the etcd data volumes stay on AWS.
    - They only get deleted when you delete the cluster with kOps.
    - Therefore all of your k8s deployments, configurations and other HA resources will re-run on next cluster restart.
- cilium CNI is used as a network plugin because it supports VPC ENI networking and Kubernetes Network Policies(useful for CKAD/CKA exam hands-on preparation).
- Official kOps documentation - https://kops.sigs.k8s.io/
