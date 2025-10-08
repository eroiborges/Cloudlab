# Use an official Python runtime as a parent image - Updated to Python 3.12
FROM python:3.12-slim

# Metadata for troubleshooting and maintenance
LABEL maintainer="troubleshooting-team"
LABEL version="2.0"
LABEL description="Backend service for load balancer troubleshooting"
LABEL service="getheader-backend"

# Create a non-root user for security
RUN groupadd -r appuser && useradd -r -g appuser appuser

# Set the working directory in the container to /app
WORKDIR /app

# Copy requirements first for better layer caching
COPY requirements.txt* ./

# Install any needed packages specified in requirements.txt
# Updated packages and added security practices
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir flask flask_restx && \
    pip install --no-cache-dir gunicorn && \
    rm -rf /root/.cache/pip

# Copy application code
COPY getheader.py ./

# Change ownership to non-root user
RUN chown -R appuser:appuser /app

# Switch to non-root user
USER appuser

# Make port 8080 available to the world outside this container
EXPOSE 8080

# Add health check for container orchestration
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Use Gunicorn for production instead of Flask dev server
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "--timeout", "30", "--access-logfile", "-", "--error-logfile", "-", "getheader:app"]