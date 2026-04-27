#!/bin/bash
set -e

# Enable logging
exec > >(tee /var/log/triagebot-bootstrap.log)
exec 2>&1

echo "=========================================="
echo "TriageBot Bootstrap Script Starting"
echo "=========================================="
echo "Time: $(date)"

# Update system
echo "Updating system packages..."
apt-get update
apt-get upgrade -y

# Install Python and dependencies
echo "Installing Python 3.11 and dependencies..."
apt-get install -y \
    python3.11 \
    python3.11-venv \
    python3.11-dev \
    python3-pip \
    curl \
    wget \
    git \
    build-essential \
    jq

# Install Ollama
echo "Installing Ollama..."
curl -fsSL https://ollama.ai/install.sh | sh

# Create app directory
echo "Creating application directory..."
mkdir -p /opt/triagebot
cd /opt/triagebot

# Clone application code from GitHub
echo "Cloning application code from GitHub..."
git clone https://github.com/DaveRoyale/TriageBot.git /tmp/triagebot-repo
if [ -d /tmp/triagebot-repo ]; then
    cp -r /tmp/triagebot-repo/app /opt/triagebot/
    cp /tmp/triagebot-repo/requirements.txt /opt/triagebot/
    rm -rf /tmp/triagebot-repo
    echo "Code cloned successfully"
else
    echo "WARNING: Failed to clone from GitHub. App won't run until code is available."
fi

# Create Python virtual environment
echo "Creating Python virtual environment..."
python3.11 -m venv /opt/triagebot/venv
source /opt/triagebot/venv/bin/activate

# Install Python dependencies
echo "Installing Python dependencies..."
if [ -f /opt/triagebot/requirements.txt ]; then
    pip install --upgrade pip
    pip install -r /opt/triagebot/requirements.txt
else
    echo "WARNING: requirements.txt not found"
fi

# Create systemd service for Ollama
echo "Configuring Ollama service..."
cat > /etc/systemd/system/ollama.service << 'EOF'
[Unit]
Description=Ollama Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=ollama
ExecStart=/usr/bin/ollama serve
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Create ollama user if it doesn't exist
if ! id -u ollama > /dev/null 2>&1; then
    useradd -r -s /bin/false ollama
fi

# Start Ollama service
echo "Starting Ollama service..."
systemctl daemon-reload
systemctl enable ollama
systemctl start ollama

# Wait for Ollama to be ready
echo "Waiting for Ollama to start (this may take 30-60 seconds)..."
for i in {1..120}; do
    if curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
        echo "Ollama is ready!"
        break
    fi
    if [ $i -eq 120 ]; then
        echo "WARNING: Ollama did not start in time. Check logs with: systemctl status ollama"
    fi
    sleep 1
done

# Pull default model (tinyllama for testing, configurable) if environment variable not set
echo "Pulling default Ollama model..."
OLLAMA_MODEL="$${OLLAMA_MODEL:-tinyllama}"
echo "Model to pull: $OLLAMA_MODEL"
sudo -u ollama /usr/bin/ollama pull "$OLLAMA_MODEL" || echo "WARNING: Model pull failed. You may need to pull manually."

# Create systemd service for FastAPI app
echo "Configuring FastAPI service..."
cat > /etc/systemd/system/triagebot.service << 'EOF'
[Unit]
Description=TriageBot FastAPI Application
After=network-online.target ollama.service
Wants=network-online.target

[Service]
Type=simple
User=www-data
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

# Create www-data user if needed and set permissions
if ! id -u www-data > /dev/null 2>&1; then
    useradd -r -s /bin/false www-data
fi

chown -R www-data:www-data /opt/triagebot

# Start FastAPI service
echo "Starting FastAPI application..."
systemctl daemon-reload
systemctl enable triagebot
systemctl start triagebot

# Wait for app to be ready
echo "Waiting for application to start..."
for i in {1..30}; do
    if curl -s http://localhost:8000/health > /dev/null 2>&1; then
        echo "Application is ready!"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "WARNING: Application did not start in time. Check logs with: systemctl status triagebot"
    fi
    sleep 1
done

echo "=========================================="
echo "Bootstrap completed successfully!"
echo "=========================================="
echo "Application running at http://$(hostname -I | awk '{print $1}'):8000"
echo "Logs:"
echo "  Ollama: journalctl -u ollama -f"
echo "  TriageBot: journalctl -u triagebot -f"
echo "Time: $(date)"
