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
