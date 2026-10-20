# llm-lab: one-command rebuilds, GPU on/off, and safe teardown.

PROFILE ?= aws-reveal
REGION  ?= us-east-1
CLUSTER ?= llm-lab
ACCOUNT ?= 921081371321
N       ?= 1
TF_DIR  := infra/terraform
SC_DIR  := gitops/platform/storageclasses

export AWS_PROFILE := $(PROFILE)

GPU_NG = $(shell aws eks list-nodegroups --cluster-name $(CLUSTER) --region $(REGION) --profile $(PROFILE) --query "nodegroups[?starts_with(@, 'gpu')] | [0]" --output text 2>/dev/null)

.DEFAULT_GOAL := help
.PHONY: help check-account _need-gpu-group plan up kubeconfig storage status gpu-on gpu-off down leftovers

help: ## Show this help
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "} {printf "  %-14s %s\n", $$1, $$2}'

check-account: ## Fail unless the AWS profile points at the lab account
	@acct=$$(aws sts get-caller-identity --query Account --output text) || exit 1; \
	if [ "$$acct" != "$(ACCOUNT)" ]; then echo "Wrong account: $$acct (expected $(ACCOUNT))"; exit 1; fi; \
	echo "Account OK: $$acct"

_need-gpu-group:
	@if [ -z "$(GPU_NG)" ] || [ "$(GPU_NG)" = "None" ]; then echo "No GPU node group found. Is the cluster up? Try: make up"; exit 1; fi

plan: check-account ## Terraform plan using your current IP
	terraform -chdir=$(TF_DIR) plan -var "my_ip=$$(curl -s https://checkip.amazonaws.com)"

up: check-account ## Build or update everything, then set up kubectl and storage and argo CD
	terraform -chdir=$(TF_DIR) init -input=false
	terraform -chdir=$(TF_DIR) apply -var "my_ip=$$(curl -s https://checkip.amazonaws.com)"
	$(MAKE) kubeconfig
	$(MAKE) storage
	$(MAKE) secrets
	$(MAKE) argocd

kubeconfig: ## Point kubectl at the current cluster
	aws eks update-kubeconfig --name $(CLUSTER) --region $(REGION) --profile $(PROFILE)
	kubectl get nodes

storage: ## Apply StorageClasses (gp3 default, efs-sc with the current EFS ID)
	kubectl patch storageclass gp2 -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}' || true
	kubectl apply -f $(SC_DIR)/gp3.yaml
	sed "s/fileSystemId: .*/fileSystemId: $$(terraform -chdir=$(TF_DIR) output -raw efs_id)/" $(SC_DIR)/efs-sc.yaml | kubectl apply -f -
	kubectl get storageclass

status: check-account _need-gpu-group ## Show nodes and the GPU node group settings
	kubectl get nodes
	aws eks describe-nodegroup --cluster-name $(CLUSTER) --nodegroup-name $(GPU_NG) --region $(REGION) --query "nodegroup.[capacityType,scalingConfig]" --output json

gpu-on: check-account _need-gpu-group ## Scale GPU nodes up (make gpu-on N=2 for two)
	aws eks update-nodegroup-config --cluster-name $(CLUSTER) --nodegroup-name $(GPU_NG) --scaling-config minSize=0,maxSize=2,desiredSize=$(N) --region $(REGION)
	@echo "GPU billing starts when the node boots. Run 'make gpu-off' when you stop."

gpu-off: check-account _need-gpu-group ## Scale GPU nodes to zero
	aws eks update-nodegroup-config --cluster-name $(CLUSTER) --nodegroup-name $(GPU_NG) --scaling-config minSize=0,maxSize=2,desiredSize=0 --region $(REGION)

down: check-account ## Safe teardown: refuses if PVCs or load balancers remain
	@kubectl get ns >/dev/null 2>&1 || { echo "Cannot reach the cluster, so I cannot check for leftovers. Try 'make up' (refreshes your IP) or 'make kubeconfig'."; exit 1; }
	@pvcs=$$(kubectl get pvc -A --no-headers | wc -l | tr -d ' '); \
	lbs=$$(kubectl get svc -A --no-headers | grep -c LoadBalancer || true); \
	if [ "$$pvcs" != "0" ] || [ "$$lbs" != "0" ]; then \
		echo "Found $$pvcs PVC(s) and $$lbs LoadBalancer service(s). Delete them first or they keep billing after destroy."; \
		exit 1; \
	fi
	terraform -chdir=$(TF_DIR) destroy -var "my_ip=$$(curl -s https://checkip.amazonaws.com)"
	@echo "Destroyed. Run 'make leftovers' to confirm nothing is still billing."

leftovers: check-account ## List volumes, NAT gateways and clusters still in the account
	aws ec2 describe-volumes --region $(REGION) --query "Volumes[].[VolumeId,State,Size]" --output table
	aws ec2 describe-nat-gateways --region $(REGION) --filter Name=state,Values=available --query "NatGateways[].NatGatewayId" --output table
	aws eks list-clusters --region $(REGION)

ARGO_CHART_VERSION ?= 10.4.1
REPO_URL ?= git@github.com:vicky97/VLLM-Stack.git
ARGO_KEY ?= $(HOME)/.ssh/argocd-llm-lab

.PHONY: argocd
argocd: check-account ## Install Argo CD, connect the repo, apply the root app
	helm repo add argo https://argoproj.github.io/argo-helm --force-update
	helm upgrade --install argocd argo/argo-cd --version $(ARGO_CHART_VERSION) --namespace argocd --create-namespace -f gitops/bootstrap/argocd-values.yaml --wait --timeout 5m
	kubectl -n argocd create secret generic repo-llm-lab --from-literal=type=git --from-literal=url=$(REPO_URL) --from-file=sshPrivateKey=$(ARGO_KEY) --dry-run=client -o yaml | kubectl apply -f -
	kubectl -n argocd label secret repo-llm-lab argocd.argoproj.io/secret-type=repository --overwrite
	kubectl apply -f gitops/bootstrap/root-app.yaml

HF_TOKEN_FILE ?= $(HOME)/.config/llm-lab/hf-token

.PHONY: secrets
secrets: check-account ## Create the out-of-band Secrets (Grafana, Hugging Face, LiteLLM, Postgres)
	@kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
	@kubectl create namespace llm --dry-run=client -o yaml | kubectl apply -f -
	@kubectl -n monitoring get secret grafana-admin >/dev/null 2>&1 || kubectl -n monitoring create secret generic grafana-admin --from-literal=admin-user=admin --from-literal=admin-password="$$(openssl rand -base64 18)"
	@kubectl -n llm get secret litellm-master-key >/dev/null 2>&1 || kubectl -n llm create secret generic litellm-master-key --from-literal=master-key="sk-$$(openssl rand -hex 24)"
	@kubectl -n llm get secret postgres-credentials >/dev/null 2>&1 || kubectl -n llm create secret generic postgres-credentials --type=kubernetes.io/basic-auth --from-literal=username=litellm --from-literal=password="$$(openssl rand -hex 16)"
	@if [ -s "$(HF_TOKEN_FILE)" ]; then kubectl -n llm create secret generic hf-token --from-literal=token="$$(tr -d '[:space:]' < $(HF_TOKEN_FILE))" --dry-run=client -o yaml | kubectl apply -f -; else echo "WARNING: no token file at $(HF_TOKEN_FILE), skipping hf-token (needed for Phase 3)"; fi
	@kubectl get secret grafana-admin -n monitoring
	@kubectl get secrets -n llm