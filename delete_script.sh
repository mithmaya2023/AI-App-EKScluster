#!/bin/bash

# Set the AWS region
AWS_REGION="us-west-2"
EKS_CLUSTER_NAME="test-ai-app1"
S3_BUCKET_NAME="test-ai-app"
ECR_REPOSITORY="ai-app"

# Delete Kubernetes deployment and service
echo "Deleting Kubernetes deployment and service..."
kubectl delete -f deployment.yaml
kubectl delete -f service.yaml

# Detach IAM policies from the node role
echo "Detaching IAM policies from the EKS node role..."
ROLE_NAME=$(aws eks describe-nodegroup \
    --cluster-name $EKS_CLUSTER_NAME \
    --nodegroup-name standard-workers \
    --region $AWS_REGION \
    --query 'nodegroup.nodeRole' --output text | awk -F'/' '{print $2}')

if [ -n "$ROLE_NAME" ]; then
    aws iam detach-role-policy --role-name "$ROLE_NAME" --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
    aws iam detach-role-policy --role-name "$ROLE_NAME" --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
    echo "IAM policies detached from role $ROLE_NAME"
else
    echo "Role name not found. Skipping IAM policy detachment."
fi

# Delete EKS cluster and node group
echo "Deleting EKS cluster and node group..."
eksctl delete cluster --name $EKS_CLUSTER_NAME --region $AWS_REGION

# Delete the ECR repository
echo "Deleting ECR repository..."
aws ecr delete-repository --repository-name $ECR_REPOSITORY --region $AWS_REGION --force

# Empty and delete the S3 bucket
echo "Emptying and deleting S3 bucket..."
aws s3 rm s3://$S3_BUCKET_NAME --recursive
aws s3api delete-bucket --bucket $S3_BUCKET_NAME --region $AWS_REGION

# Optionally delete IAM role (if created by eksctl)
echo "Deleting IAM roles..."
aws iam delete-role --role-name "$ROLE_NAME" 2>/dev/null

# Verify deletion of resources
echo "Verifying resource deletion..."
aws eks list-clusters --region $AWS_REGION
aws ecr describe-repositories --region $AWS_REGION
aws s3api list-buckets --query "Buckets[].Name"

echo "All resources should be deleted."
