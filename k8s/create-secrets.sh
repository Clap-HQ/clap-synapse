#!/bin/bash
# Script to create Kubernetes secrets from AWS Secrets Manager
# Run this BEFORE deploying Synapse to EKS

set -e
set -o pipefail

# Source .env file if present (optional)
if [ -f .env ]; then
  source .env
fi

echo "🔐 Creating Kubernetes Secrets from AWS Secrets Manager..."

# Validate required environment variables
if [ -z "${DB_SECRET_ARN}" ]; then
  echo "❌ ERROR: DB_SECRET_ARN environment variable is not set" >&2
  echo "Please set DB_SECRET_ARN to the AWS Secrets Manager ARN for database credentials" >&2
  exit 1
fi

if [ -z "${SYNAPSE_SECRET_ARN}" ]; then
  echo "❌ ERROR: SYNAPSE_SECRET_ARN environment variable is not set" >&2
  echo "Please set SYNAPSE_SECRET_ARN to the AWS Secrets Manager ARN for Synapse secrets" >&2
  exit 1
fi

echo "✅ Environment variables validated"
echo "📥 Fetching secrets from AWS Secrets Manager..."

# Fetch DB password with error handling
DB_SECRET_JSON=$(aws secretsmanager get-secret-value \
  --secret-id "${DB_SECRET_ARN}" \
  --query SecretString \
  --output text 2>&1)

if [ $? -ne 0 ]; then
  echo "❌ ERROR: Failed to fetch DB secret from AWS Secrets Manager" >&2
  echo "$DB_SECRET_JSON" >&2
  exit 1
fi

DB_PASSWORD=$(echo "$DB_SECRET_JSON" | jq -r .password)
if [ -z "$DB_PASSWORD" ] || [ "$DB_PASSWORD" = "null" ]; then
  echo "❌ ERROR: DB password not found in secret JSON" >&2
  exit 1
fi

# Fetch Synapse secrets with error handling
SYNAPSE_SECRET_JSON=$(aws secretsmanager get-secret-value \
  --secret-id "${SYNAPSE_SECRET_ARN}" \
  --query SecretString \
  --output text 2>&1)

if [ $? -ne 0 ]; then
  echo "❌ ERROR: Failed to fetch Synapse secret from AWS Secrets Manager" >&2
  echo "$SYNAPSE_SECRET_JSON" >&2
  exit 1
fi

REGISTRATION_SECRET=$(echo "$SYNAPSE_SECRET_JSON" | jq -r .registration_shared_secret)
if [ -z "$REGISTRATION_SECRET" ] || [ "$REGISTRATION_SECRET" = "null" ]; then
  echo "❌ ERROR: registration_shared_secret not found in secret JSON" >&2
  exit 1
fi

MACAROON_SECRET=$(echo "$SYNAPSE_SECRET_JSON" | jq -r .macaroon_secret_key)
if [ -z "$MACAROON_SECRET" ] || [ "$MACAROON_SECRET" = "null" ]; then
  echo "❌ ERROR: macaroon_secret_key not found in secret JSON" >&2
  exit 1
fi

FORM_SECRET=$(echo "$SYNAPSE_SECRET_JSON" | jq -r .form_secret)
if [ -z "$FORM_SECRET" ] || [ "$FORM_SECRET" = "null" ]; then
  echo "❌ ERROR: form_secret not found in secret JSON" >&2
  exit 1
fi

echo "✅ Secrets fetched successfully"

echo "🔧 Creating Kubernetes Secrets in 'dev' namespace..."

# Verify all variables are set before creating secrets
if [ -z "$DB_PASSWORD" ]; then
  echo "❌ ERROR: DB_PASSWORD is empty" >&2
  exit 1
fi

if [ -z "$REGISTRATION_SECRET" ] || [ -z "$MACAROON_SECRET" ] || [ -z "$FORM_SECRET" ]; then
  echo "❌ ERROR: One or more Synapse secrets are empty" >&2
  exit 1
fi

# Create DB credentials secret with proper quoting
kubectl create secret generic synapse-db-credentials \
  --from-literal="password=${DB_PASSWORD}" \
  --namespace=dev \
  --dry-run=client -o yaml | kubectl apply -f -

# Create app credentials secret with proper quoting
kubectl create secret generic synapse-app-credentials \
  --from-literal="registration_shared_secret=${REGISTRATION_SECRET}" \
  --from-literal="macaroon_secret_key=${MACAROON_SECRET}" \
  --from-literal="form_secret=${FORM_SECRET}" \
  --namespace=dev \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✅ Secrets created successfully in 'dev' namespace"
echo ""
echo "📋 Verify secrets:"
echo "  kubectl get secrets -n dev | grep synapse"
echo "  kubectl describe secret synapse-db-credentials -n dev"
echo "  kubectl describe secret synapse-app-credentials -n dev"
