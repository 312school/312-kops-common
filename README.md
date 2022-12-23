# Kubernetes cluster creation with kOps
**Note:** All of the below commands can be run on your local machine (Mac or Windows(use WSL2 Ubuntu))

## Prerequisites
    # install kops
        # MacOS users:
            brew update && brew install kops
        # Windows users using WSL2 Ubuntu, follow the official guide for Linux-based installation
            https://kops.sigs.k8s.io/getting_started/install/
    # install aws cli, if you don't have it
        https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
    # install kubectl, if you don't have it
        https://kubernetes.io/docs/tasks/tools/

## KOPS Cluster Installation
    # clone this repo to your local machine, then navigate into the repo folder
        git clone git@github.com:312-bc/312-kops-common.git
        cd 312-kops-common/
    # create buckets for kops and oidc - make sure you have aws credentials configured in ~/.aws/credentials
        make buckets

    # deploy cluster
        make deploy

        # you are expected to receive errors until the cluster and related resources are ready.
        # it could take up to 10 mins for the cluster to be ready, but usually takes less than 5 mins.

    # verify that everything is running properly
        kubectl get nodes
        kubectl get po --all-namespaces

## To reconfigure kubeconfig if getting unauthorized for kubectl commands
    # make sure you have right credentials in ~/.aws/credentials
    aws sts get-caller-identity

    # reconfigure your ~/.kube/config
    make config

## Additional useful info (NOT necessary for installation):

    # check current kubeconfig context (current cluster pointer)
    kubectl config current-context

    # switch to this kops cluster context when needed
    kubectl config use-context 312-kops.k8s.local

    # to list contexts in your current ~/.kube/config
    kubectl config get-contexts

## DANGER ZONE: To delete cluster:
    # Use this also to start from scratch if you mess up somewhere in the installation process.
    make destroy

## Notes
- Both Master and Worker nodes are launched in separate AutoScaling Groups
    - Stopping master and worker nodes manually will only cause AutoScaling Group to create more EC2s as a replacement
        - so proper way to reduce costs is scaling in the ASG group sizes down to 0 (zero)
        - note that once you scale the ASG down to 0, the ASG nodes might take time to actually get terminated
    ![Screenshot 2022-11-21 at 8 53 15 PM](https://user-images.githubusercontent.com/43100287/203209740-69566769-1573-49bb-a7d5-d5e314a689fe.png)

- **Cost of the Resources Disclaimer**:
    - **To make sure you incur very minimal charges**:
        - in AWS Console, set desired and minimum ASG size for both master and worker node AutoScaling Groups to 0(zero) when you don't need the cluster.
        - and then bring back master ASG to 1 and workers ASG to 2 whenever you need a cluster.
    - This installation uses Spot instances for both Master and Worker nodes.
        - If you do not wish to use spot instances, comment out 2 "maxPrice: ..." lines in kops-config.yaml. But it will result in more expenses.
    - Master and Worker nodes use t3.medium type which is the minimum for it's needs. Spot instances typically run %70 cheaper than on-demand.
    - EBS volumes(AWS has 30GB free tier limit, and $0.08/GB-month afterwards):
        - master node has 3 volumes: 1 for itself - 10GB. 2 for etcd stores - each 2GB.
        - worker nodes have 1 volume each - 13GB.
    - **Cost estimates will depend on spot instance pricing in a current market.**
        - EBS volumes cost should very low since you almost fall under free tier (34GB in total, free tier is 30GB)
        - ELB created for exposing Kube API server publicly falls under free tier if you don't run additional load balancers
        - Main expense will be t3.medium instances that run for about $10 a month each
            - **but if you keep resizing your ASGs regularly as recommended, costs should be minimal.**
            - **for example running them for 20 hours/week should cost around $3.6/month for all 3 instances ($1.2/month/each).**

## Additional knowledge
- bucket names are globally unique in S3, therefore we have added `-${account}` suffix to keep your bucket names unique and consistent at the same time.
- kOps creates a Network Load Balancer that exposes cluster's Kubernetes API to public with a static DNS name.
    - This allows you to connect to K8s cluster anywhere from the internet including from your local machine.
    - This NLB address is written down by kOps into your local ~/.kube/config file when creating the cluster with kOps.
        - if you have switched to another cluster later on(ex: to eks), you can switch back to this kOps cluster using `kubectl config use-context 312-kops.k8s.local`
            - or use `make config`
    - AWS provides NLB in free tier for a whole month.
- `etcd` data is stored on 2 dedicated EBS volumes that are attached to the master node. When master node is deleted, the etcd data volumes stay on AWS.
    - They only get deleted when you delete the cluster with kOps.
    - Therefore all of your k8s deployments, configurations and other HA resources will re-run on next cluster restart.
- cilium CNI is used as a network plugin because it supports VPC ENI networking and Kubernetes Network Policies(useful for CKAD/CKA exam hands-on preparation).
- Official kOps documentation - https://kops.sigs.k8s.io/
