#!/bin/bash
# Script to create Kubernetes secrets from AWS Secrets Manager
# Run this BEFORE deploying Synapse to EKS

set -e

echo "🔐 Creating Kubernetes Secrets from AWS Secrets Manager..."

# Secrets Manager ARNs
DB_SECRET_ARN="arn:aws:secretsmanager:ap-northeast-2:619888520513:secret:clap/synapse/db-20251028050850614600000006-lEW6Pv"
SYNAPSE_SECRET_ARN="arn:aws:secretsmanager:ap-northeast-2:619888520513:secret:clap/synapse/secrets-20251028050850152900000001-SuOtep"

echo "📥 Fetching secrets from AWS Secrets Manager..."

# Fetch DB password
DB_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id "$DB_SECRET_ARN" \
  --query SecretString \
  --output text | jq -r .password)

# Fetch Synapse secrets
REGISTRATION_SECRET=$(aws secretsmanager get-secret-value \
  --secret-id "$SYNAPSE_SECRET_ARN" \
  --query SecretString \
  --output text | jq -r .registration_shared_secret)

MACAROON_SECRET=$(aws secretsmanager get-secret-value \
  --secret-id "$SYNAPSE_SECRET_ARN" \
  --query SecretString \
  --output text | jq -r .macaroon_secret_key)

FORM_SECRET=$(aws secretsmanager get-secret-value \
  --secret-id "$SYNAPSE_SECRET_ARN" \
  --query SecretString \
  --output text | jq -r .form_secret)

echo "✅ Secrets fetched successfully"

echo "🔧 Creating Kubernetes Secrets in 'dev' namespace..."

# Create DB credentials secret
kubectl create secret generic synapse-db-credentials \
  --from-literal=password="$DB_PASSWORD" \
  --namespace=dev \
  --dry-run=client -o yaml | kubectl apply -f -

# Create app credentials secret
kubectl create secret generic synapse-app-credentials \
  --from-literal=registration_shared_secret="$REGISTRATION_SECRET" \
  --from-literal=macaroon_secret_key="$MACAROON_SECRET" \
  --from-literal=form_secret="$FORM_SECRET" \
  --namespace=dev \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✅ Secrets created successfully in 'dev' namespace"
echo ""
echo "📋 Verify secrets:"
echo "  kubectl get secrets -n dev | grep synapse"
echo "  kubectl describe secret synapse-db-credentials -n dev"
echo "  kubectl describe secret synapse-app-credentials -n dev"
