#!/bin/bash
# Seed AWS Secrets Manager in LocalStack for local development
set -e

ENDPOINT="http://localhost:4566"

echo "Creating secrets in LocalStack..."

aws --endpoint-url=$ENDPOINT secretsmanager create-secret \
  --name "app-secret-key" \
  --secret-string '{"value":"local-dev-app-secret-12345"}' \
  --region us-east-1 || true

aws --endpoint-url=$ENDPOINT secretsmanager create-secret \
  --name "notification-api-key" \
  --secret-string '{"value":"local-dev-notification-key-xyz"}' \
  --region us-east-1 || true

echo "Secrets seeded successfully."
