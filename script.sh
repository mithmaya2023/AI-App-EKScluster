#!/bin/bash

# Configure AWS CLI
aws configure set aws_access_key_id YOUR_ACCESS_KEY_ID
aws configure set aws_secret_access_key YOUR_SECRET_ACCESS_KEY
aws configure set default.region us-west-2
aws configure set default.output json

# Update package list and install required software
sudo apt update
sudo snap install aws-cli --classic
sudo apt install -y docker.io unzip curl

# Install kubectl
sudo curl -Lo kubectl https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl
sudo chmod +x ./kubectl
sudo mv ./kubectl /usr/local/bin/kubectl

# Create S3 bucket
aws s3api create-bucket --bucket test-ai-app --region us-west-2 --create-bucket-configuration LocationConstraint=us-west-2

# Install eksctl
curl -sL "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" -o eksctl.tar.gz
tar -xzf eksctl.tar.gz
sudo mv eksctl /usr/local/bin

# Check eksctl version
eksctl version

# Create application directory
mkdir ai-app
cd ai-app/

# Create the Flask application
cat <<EOL > ai-app.py
import numpy as np
from sklearn.linear_model import LinearRegression
import joblib
from flask import Flask, request, jsonify
import boto3

app = Flask(__name__)

s3 = boto3.client('s3')
BUCKET_NAME = 'test-ai-app'

# Train a simple model
def train_model():
    X = np.array([[1, 1], [2, 2], [3, 3], [4, 4]])
    y = np.dot(X, np.array([1, 2])) + 3
    model = LinearRegression().fit(X, y)
    joblib.dump(model, 'model.pkl')
    s3.upload_file('model.pkl', BUCKET_NAME, 'model/model.pkl')
    print("model created and uploaded to s3 bucket")
    return model

# Endpoint for predictions
@app.route('/predict', methods=['POST'])
def predict():
    try:
        model = joblib.load('model.pkl')
        data = request.json['data']
        prediction = model.predict([data])
        result = {'prediction': prediction.tolist()}
        s3.put_object(Body=str(result), Bucket=BUCKET_NAME, Key='predictions/result.json')
        return jsonify(result)
    except Exception as e:
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    model = train_model()
    app.run(host='0.0.0.0', port=5000)
EOL

# Create requirements file
cat <<EOL > requirements.txt
Flask==2.0.3
Werkzeug==2.0.3
scikit-learn==0.24.2
joblib==1.0.1
boto3
EOL

# Create Dockerfile
cat <<EOL > Dockerfile
FROM python:3.8-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install -r requirements.txt

# Copy application code
COPY ai_app.py .

# Expose port and run the app
EXPOSE 5000
CMD ["python", "ai_app.py"]
EOL

# Create Kubernetes deployment and service YAML files
cat <<EOL > deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ai-app
  labels:
    app: ai-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ai-app
  template:
    metadata:
      labels:
        app: ai-app
    spec:
      containers:
      - name: ai-app
        image: 495599769142.dkr.ecr.ap-south-1.amazonaws.com/ai-app
        ports:
        - containerPort: 5000
EOL

cat <<EOL > service.yaml
apiVersion: v1
kind: Service
metadata:
  name: ai-app-service
  namespace: default
spec:
  type: LoadBalancer
  ports:
    - port: 80
      targetPort: 5000
  selector:
    app: ai-app
EOL

# Build Docker image
docker build -t ai-app:latest .

# Create ECR repository and push image
aws ecr create-repository --repository-name ai-app
aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin 495599769142.dkr.ecr.us-west-2.amazonaws.com
docker tag ai-app:latest 495599769142.dkr.ecr.us-west-2.amazonaws.com/ai-app:latest
docker push 495599769142.dkr.ecr.us-west-2.amazonaws.com/ai-app:latest

# Create EKS cluster
eksctl create cluster --name test-ai-app --version 1.30 --region us-west-2 --nodegroup-name standard-workers --node-type t3.medium --nodes 2 --nodes-min 1 --nodes-max 3 --managed

# Get the role name from the EKS node group
ROLE_NAME=$(aws eks describe-nodegroup \
    --cluster-name test-ai-app \
    --nodegroup-name standard-workers \
    --region us-west-2 \
    --query 'nodegroup.nodeRole' --output text | awk -F'/' '{print $2}')

# Attach IAM policies to the role
aws iam attach-role-policy \
    --role-name "$ROLE_NAME" \
    --region us-west-2 \
    --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly

aws iam attach-role-policy \
    --role-name "$ROLE_NAME" \
    --region us-west-2 \
    --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess

# List attached policies
aws iam list-attached-role-policies \
    --role-name "$ROLE_NAME"

# Set up Kubeflow
#kubectl create namespace kubeflow
#git clone https://github.com/kubeflow/manifests.git
#cd manifests
#wget https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv5.4.3/kustomize_v5.4.3_linux_amd64.tar.gz
#tar zxvf kustomize_v5.4.3_linux_amd64.tar.gz
#sudo cp kustomize /usr/bin/

# Deploy Kubeflow
#while ! kustomize build example | kubectl apply -f -; do echo "Retrying to apply resources"; sleep 20; done

# Apply the application deployment and service
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml

# Check the pods
kubectl get pods -n default

