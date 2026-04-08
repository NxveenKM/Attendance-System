# Use the official pre-built image from the library creator
FROM animcogn/face_recognition:cpu

# Set the working directory
WORKDIR /app

# Copy your specific requirements and install them
# We use --no-cache-dir to keep the image small
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy your backend code
COPY . .

# Expose port 10000 for Render
EXPOSE 10000

# Start the server (make sure your FastAPI instance is named 'app' in app.py)
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "10000"]