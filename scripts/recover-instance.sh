#!/bin/bash

# Recovery script to manually set up Python venv and restart services
# Run this on an instance via SSM if the initial bootstrap failed
# Usage: aws ssm send-command --document-name AWS-RunShellScript --instance-ids <id> --region <region> --parameters 'commands=["/path/to/recover-instance.sh"]'

set -e

echo "=========================================="
echo "TriageBot Instance Recovery"
echo "=========================================="
echo "Time: $(date)"
echo ""

APP_DIR="/opt/triagebot"

# Check if app directory exists
if [ ! -d "$APP_DIR" ]; then
    echo "ERROR: Application directory $APP_DIR does not exist"
    exit 1
fi

cd "$APP_DIR"

# Step 1: Verify code is present
echo "Step 1: Verifying application code..."
if [ ! -d "app" ]; then
    echo "ERROR: app/ directory not found"
    echo "Attempting to clone from GitHub..."
    cd /tmp
    rm -rf triagebot-repo
    git clone https://github.com/DaveRoyale/TriageBot.git triagebot-repo
    if [ ! -d "triagebot-repo/app" ]; then
        echo "ERROR: Failed to clone code from GitHub"
        exit 1
    fi
    cp -r triagebot-repo/app "$APP_DIR/"
    cp triagebot-repo/requirements.txt "$APP_DIR/"
    cd "$APP_DIR"
fi
echo "✓ Application code found"

# Step 2: Recreate virtual environment if broken
echo ""
echo "Step 2: Checking virtual environment..."
if [ ! -f "venv/bin/python" ] || [ ! -f "venv/bin/pip" ]; then
    echo "Virtual environment is missing or broken. Recreating..."
    rm -rf venv
    python3.11 -m venv venv

    if [ ! -f "venv/bin/python" ] || [ ! -f "venv/bin/pip" ]; then
        echo "ERROR: Failed to create virtual environment"
        exit 1
    fi
    echo "✓ Virtual environment created"
fi

# Step 3: Verify Python version
echo ""
echo "Step 3: Verifying Python version..."
PYTHON_VERSION=$("$APP_DIR/venv/bin/python" --version 2>&1)
echo "Python version: $PYTHON_VERSION"

# Step 4: Install/upgrade dependencies
echo ""
echo "Step 4: Installing dependencies..."
if [ ! -f "requirements.txt" ]; then
    echo "ERROR: requirements.txt not found"
    exit 1
fi

"$APP_DIR/venv/bin/pip" install --upgrade pip setuptools wheel
"$APP_DIR/venv/bin/pip" install -r requirements.txt

# Verify critical packages
if ! "$APP_DIR/venv/bin/pip" show fastapi > /dev/null 2>&1; then
    echo "ERROR: Failed to install fastapi"
    exit 1
fi
echo "✓ Dependencies installed successfully"

# Step 5: Verify systemd service file exists
echo ""
echo "Step 5: Verifying systemd service configuration..."
if [ ! -f "/etc/systemd/system/triagebot.service" ]; then
    echo "Creating systemd service file..."
    cat > /etc/systemd/system/triagebot.service << 'EOF'
[Unit]
Description=TriageBot FastAPI Application
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/triagebot
Environment="PATH=/opt/triagebot/venv/bin"
Environment="PYTHONUNBUFFERED=1"
Environment="LLM_PROVIDER=ollama"
Environment="OLLAMA_MODEL=tinyllama"
ExecStart=/opt/triagebot/venv/bin/python -m uvicorn app.main:app --host 0.0.0.0 --port 8000
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable triagebot
    echo "✓ Systemd service created"
else
    echo "✓ Systemd service file exists"
fi

# Step 6: Ensure Ollama is running
echo ""
echo "Step 6: Checking Ollama service..."
if ! systemctl is-active --quiet ollama; then
    echo "Starting Ollama service..."
    systemctl start ollama

    # Wait for Ollama to be ready
    echo "Waiting for Ollama to start..."
    for i in {1..30}; do
        if curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
            echo "✓ Ollama is ready"
            break
        fi
        sleep 1
    done

    # Pull tinyllama model
    echo "Pulling tinyllama model..."
    export HOME=/root
    /usr/local/bin/ollama pull tinyllama || echo "WARNING: Model pull failed"
else
    echo "✓ Ollama service is running"
fi

# Step 7: Restart the service
echo ""
echo "Step 7: Restarting TriageBot service..."
systemctl restart triagebot

# Step 8: Wait and verify
echo ""
echo "Step 8: Verifying service is running..."
sleep 3

SERVICE_STATUS=$(systemctl is-active triagebot || echo "inactive")
if [ "$SERVICE_STATUS" != "active" ]; then
    echo "ERROR: Service is not running. Status: $SERVICE_STATUS"
    echo "Service logs:"
    journalctl -u triagebot -n 30 --no-pager
    exit 1
fi
echo "✓ Service is running"

# Step 9: Health check
echo ""
echo "Step 9: Checking application health..."
for i in {1..10}; do
    if curl -s http://localhost:8000/ > /dev/null 2>&1; then
        echo "✓ Application is responding"
        break
    fi
    if [ $i -eq 10 ]; then
        echo "WARNING: Application not responding after 10 seconds"
        echo "Service logs:"
        journalctl -u triagebot -n 20 --no-pager
    fi
    sleep 1
done

echo ""
echo "=========================================="
echo "Recovery completed successfully!"
echo "=========================================="
echo "Time: $(date)"
echo ""
echo "TriageBot is running at:"
echo "  http://localhost:8000 (internal)"
echo "  http://$(hostname -I | awk '{print $1}'):8000 (internal IP)"
echo ""
echo "For logs, run:"
echo "  journalctl -u triagebot -f"
