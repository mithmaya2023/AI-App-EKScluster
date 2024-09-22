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
    #model = joblib.load('model.pkl')
    #data = request.json['data']
    #prediction = model.predict([data])
    #result = {'prediction': prediction.tolist()}
    #s3.put_object(Body=str(result), Bucket=BUCKET_NAME, Key='predictions/result.json')
    #return jsonify(result)
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
