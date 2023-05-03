# use us-east-1 region, cluster config is hardcoded for it
region = us-east-1
# This uses the current aws config profile (or $AWS_PROFILE)
aws := aws --region $(region)
account := $(shell aws sts get-caller-identity --output text --query 'Account')

cluster = 312-kops.k8s.local
version = 1.25.4
kops_bucket = 312-k8s-kops-state-$(account)
oidc_bucket = 312-k8s-kops-oidc-store-$(account)
kops := kops --state=s3://$(kops_bucket)

default: help

# Lists all available targets
help:
	@make -qp | awk -F':' '/^[a-z0-9][^$$#\/\t=]*:([^=]|$$)/ {split($$1,A,/ /);for(i in A)print A[i]}' | sort

buckets:
	# creating kops state store bucket
	$(aws) s3api create-bucket --bucket $(kops_bucket)
	$(aws) s3api put-bucket-versioning --bucket $(kops_bucket) --versioning-configuration Status=Enabled
	# creating separate bucket for oidc store, will be used by serviceaccount+oidc integrations
	$(aws) s3api create-bucket --bucket $(oidc_bucket)
	$(aws) s3api put-public-access-block --bucket $(oidc_bucket) --public-access-block-configuration "BlockPublicPolicy=false"
	$(aws) s3api put-bucket-ownership-controls --bucket $(oidc_bucket) --ownership-controls="Rules=[{ObjectOwnership=BucketOwnerPreferred}]"
	$(aws) s3api put-bucket-acl --bucket $(oidc_bucket) --acl public-read

dry-run:
	# dry-run cluster and adjust configs
	cat kops-config.yaml | sed "s/ACCOUNT/$(account)/g;s/CLUSTER_NAME/$(cluster)/g;s/CLUSTER_VERSION/$(version)/g" | $(kops) replace --force -f -

deploy: dry-run
	# apply the configs and run cluster
	$(kops) update cluster --name $(cluster) --yes --admin
	$(kops) validate cluster --wait 10m

config:
	@# use this target if getting unauthorized after scaling master nodes to 0 and back to 1
	# make sure you are logged in to the same account with AWS CLi
	$(kops) export kubeconfig --name $(cluster) --admin
	kubectl get nodes

destroy:
	$(kops) delete cluster --name $(cluster) --yes

