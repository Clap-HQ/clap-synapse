# Synapse Kubernetes Manifests

Kubernetes manifests for deploying Matrix Synapse on EKS.

## 📁 Files

- `namespace.yaml` - Dev namespace
- `serviceaccount.yaml` - IRSA-enabled ServiceAccount
- `persistentvolume.yaml` - EFS PersistentVolume and PVC
- `configmap.yaml` - Environment variables
- `deployment.yaml` - Synapse Deployment
- `service.yaml` - ClusterIP Service
- `ingress.yaml` - ALB Ingress
- `create-secrets.sh` - Script to create Secrets from AWS Secrets Manager

## 🚀 Deployment Order

### Prerequisites

1. **EKS Cluster**: Ensure `clap-eks-dev` cluster is running
2. **IRSA**: IAM role `clap-eks-dev-synapse-sa` must exist (created via Terraform)
3. **EFS CSI Driver**: Must be installed on EKS
4. **ALB Ingress Controller**: Must be installed on EKS
5. **kubectl**: Configured to access the EKS cluster

```bash
aws eks update-kubeconfig --region ap-northeast-2 --name clap-eks-dev
```

### Step 1: Create Namespace

```bash
kubectl apply -f namespace.yaml
```

### Step 2: Create ServiceAccount (IRSA)

```bash
kubectl apply -f serviceaccount.yaml
```

**Verify**:
```bash
kubectl get serviceaccount synapse -n dev -o yaml
# Should see annotation: eks.amazonaws.com/role-arn
```

### Step 3: Create Secrets

**Set required environment variables**:
```bash
export DB_SECRET_ARN="arn:aws:secretsmanager:ap-northeast-2:619888520513:secret:clap/synapse/db-20251028050850614600000006-lEW6Pv"
export SYNAPSE_SECRET_ARN="arn:aws:secretsmanager:ap-northeast-2:619888520513:secret:clap/synapse/secrets-20251028050850152900000001-SuOtep"
```

**Or create a `.env` file** (optional):
```bash
cat > k8s/.env <<EOF
DB_SECRET_ARN=arn:aws:secretsmanager:ap-northeast-2:619888520513:secret:clap/synapse/db-20251028050850614600000006-lEW6Pv
SYNAPSE_SECRET_ARN=arn:aws:secretsmanager:ap-northeast-2:619888520513:secret:clap/synapse/secrets-20251028050850152900000001-SuOtep
EOF
```

**Run the script**:
```bash
./create-secrets.sh
```

**Verify**:
```bash
kubectl get secrets -n dev | grep synapse
kubectl describe secret synapse-db-credentials -n dev
kubectl describe secret synapse-app-credentials -n dev
```

### Step 4: Create PersistentVolume and PVC

```bash
kubectl apply -f persistentvolume.yaml
```

**Verify**:
```bash
kubectl get pv synapse-efs-pv
kubectl get pvc synapse-efs-pvc -n dev
```

### Step 5: Create ConfigMap

```bash
kubectl apply -f configmap.yaml
```

**Verify**:
```bash
kubectl describe configmap synapse-config -n dev
```

### Step 6: Create Service

```bash
kubectl apply -f service.yaml
```

**Verify**:
```bash
kubectl get service synapse -n dev
```

### Step 7: Create Deployment

```bash
kubectl apply -f deployment.yaml
```

**Verify**:
```bash
kubectl get deployment synapse -n dev
kubectl get pods -n dev -l app=synapse
kubectl logs -n dev -l app=synapse --tail=50
```

### Step 8: Create Ingress (ALB)

```bash
kubectl apply -f ingress.yaml
```

**Verify**:
```bash
kubectl get ingress synapse -n dev
kubectl describe ingress synapse -n dev

# Wait for ALB to be provisioned (2-4 minutes)
kubectl get ingress synapse -n dev -w
```

## 🧪 Testing

### 1. Check Pod Status

```bash
kubectl get pods -n dev -l app=synapse
kubectl describe pod -n dev -l app=synapse
kubectl logs -n dev -l app=synapse --tail=100
```

### 2. Test Health Endpoint

```bash
# Get ALB DNS
ALB_DNS=$(kubectl get ingress synapse -n dev -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo $ALB_DNS

# Test via ALB
curl -s https://$ALB_DNS/_matrix/client/versions | jq .

# Test via domain (after DNS propagation)
curl -s https://dev.clap.ac/_matrix/client/versions | jq .
```

### 3. Test S3 Access (IRSA)

```bash
kubectl exec -it -n dev $(kubectl get pod -n dev -l app=synapse -o jsonpath='{.items[0].metadata.name}') -- \
  aws s3 ls s3://clap-messenger-media-dev-619888520513/ --region ap-northeast-2
```

### 4. Test Database Connection

```bash
kubectl exec -it -n dev $(kubectl get pod -n dev -l app=synapse -o jsonpath='{.items[0].metadata.name}') -- \
  psql -h clap-synapse-db-dev.cfiyo0k0ywot.ap-northeast-2.rds.amazonaws.com -U synapse -d synapse -c "SELECT COUNT(*) FROM users;"
```

## 🔧 Troubleshooting

### Pod not starting

```bash
kubectl describe pod -n dev -l app=synapse
kubectl logs -n dev -l app=synapse
```

Common issues:
- **ImagePullBackOff**: ECR credentials or image doesn't exist
- **CrashLoopBackOff**: Check logs for application errors
- **Pending**: Check PVC binding or resource constraints

### EFS Mount Issues

```bash
# Check PV/PVC status
kubectl get pv synapse-efs-pv
kubectl get pvc synapse-efs-pvc -n dev

# Check EFS CSI Driver
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-efs-csi-driver
```

### IRSA Issues

```bash
# Check ServiceAccount annotation
kubectl get serviceaccount synapse -n dev -o yaml

# Check IAM role exists
aws iam get-role --role-name clap-eks-dev-synapse-sa

# Check pod can assume role
kubectl exec -it -n dev $(kubectl get pod -n dev -l app=synapse -o jsonpath='{.items[0].metadata.name}') -- \
  env | grep AWS
```

### Ingress/ALB Issues

```bash
# Check Ingress status
kubectl describe ingress synapse -n dev

# Check ALB Ingress Controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=100

# Check Target Group health in AWS Console
```

## 📊 Monitoring

### View Logs

```bash
# Follow logs
kubectl logs -n dev -l app=synapse -f

# Last 100 lines
kubectl logs -n dev -l app=synapse --tail=100

# Previous container logs (if pod crashed)
kubectl logs -n dev -l app=synapse --previous
```

### Resource Usage

```bash
kubectl top pod -n dev -l app=synapse
```

### Events

```bash
kubectl get events -n dev --sort-by='.lastTimestamp'
```

## 🔄 Updates

### Update Deployment

```bash
# Update image
kubectl set image deployment/synapse synapse=619888520513.dkr.ecr.ap-northeast-2.amazonaws.com/clap-synapse:new-tag -n dev

# Or edit directly
kubectl edit deployment synapse -n dev

# Or apply updated manifest
kubectl apply -f deployment.yaml
```

### Restart Pods

```bash
kubectl rollout restart deployment/synapse -n dev
```

### Rollback

```bash
kubectl rollout undo deployment/synapse -n dev
```

## 🗑️ Cleanup

To remove all resources:

```bash
kubectl delete -f ingress.yaml
kubectl delete -f deployment.yaml
kubectl delete -f service.yaml
kubectl delete -f configmap.yaml
kubectl delete -f persistentvolume.yaml
kubectl delete secret synapse-db-credentials -n dev
kubectl delete secret synapse-app-credentials -n dev
kubectl delete -f serviceaccount.yaml
kubectl delete -f namespace.yaml
```

**Note**: This will NOT delete:
- EFS data (persistent)
- RDS database (persistent)
- S3 media files (persistent)
- IAM roles (managed by Terraform)

## 📚 References

- [Synapse Documentation](https://matrix-org.github.io/synapse/latest/)
- [EKS User Guide](https://docs.aws.amazon.com/eks/latest/userguide/)
- [ALB Ingress Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
- [EFS CSI Driver](https://docs.aws.amazon.com/eks/latest/userguide/efs-csi.html)
- [IRSA](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
