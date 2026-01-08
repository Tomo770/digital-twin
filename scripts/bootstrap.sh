#!/bin/bash
set -e

echo "🚀 Bootstrapping Terraform State Infrastructure..."

# Get AWS Account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
# Use detected region or default
if [ -z "$DEFAULT_AWS_REGION" ]; then
    AWS_REGION=$(aws configure get region 2>/dev/null)
    AWS_REGION=${AWS_REGION:-us-east-1}
else
    AWS_REGION=$DEFAULT_AWS_REGION
fi

BUCKET_NAME="twin-terraform-state-${AWS_ACCOUNT_ID}"
TABLE_NAME="twin-terraform-locks"

echo "Using Account ID: $AWS_ACCOUNT_ID"
echo "Region: $AWS_REGION"

# 1. Create S3 Bucket for Terraform State
if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
    echo "✅ S3 bucket $BUCKET_NAME already exists."
else
    echo "📦 Creating S3 bucket: $BUCKET_NAME..."
    if [ "$AWS_REGION" == "us-east-1" ]; then
        aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION"
    else
        aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION" --create-bucket-configuration LocationConstraint="$AWS_REGION"
    fi
    
    # Enable versioning
    aws s3api put-bucket-versioning --bucket "$BUCKET_NAME" --versioning-configuration Status=Enabled
    echo "✅ Enabled versioning on $BUCKET_NAME"
    
    # Block public access
    aws s3api put-public-access-block \
        --bucket "$BUCKET_NAME" \
        --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
    echo "✅ Blocked public access on $BUCKET_NAME"
fi

# 2. Create DynamoDB Table for State Locking
if aws dynamodb describe-table --table-name "$TABLE_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
    echo "✅ DynamoDB table $TABLE_NAME already exists."
else
    echo "🔒 Creating DynamoDB table: $TABLE_NAME..."
    aws dynamodb create-table \
        --table-name "$TABLE_NAME" \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
        --region "$AWS_REGION"
    
    echo "⏳ Waiting for DynamoDB table to be active..."
    aws dynamodb wait table-exists --table-name "$TABLE_NAME" --region "$AWS_REGION"
    echo "✅ DynamoDB table $TABLE_NAME is ready."
fi

echo "🎉 Bootstrap complete! You can now run the deployment script."
