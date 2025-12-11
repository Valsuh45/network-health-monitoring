#!/bin/bash

# Network Monitor Setup Script
# Sets up the network monitoring system with scheduling and configuration

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITOR_SCRIPT="$SCRIPT_DIR/network_monitor.sh"
SERVICE_NAME="network-monitor"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_message() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success_message() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

error_message() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warning_message() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if script exists and make it executable
setup_permissions() {
    if [[ ! -f "$MONITOR_SCRIPT" ]]; then
        error_message "Network monitor script not found: $MONITOR_SCRIPT"
        exit 1
    fi

    chmod +x "$MONITOR_SCRIPT"
    success_message "Made network monitor script executable"
}

# Create default configuration
create_config() {
    local config_file="$SCRIPT_DIR/network_config.conf"

    if [[ -f "$config_file" ]]; then
        warning_message "Configuration file already exists: $config_file"
        read -p "Do you want to recreate it? (y/N): " -r recreate
        if [[ ! "$recreate" =~ ^[Yy]$ ]]; then
            return 0
        fi
    fi

    log_message "Creating configuration file..."

    # Interactive configuration
    echo "Network Monitor Configuration Setup"
    echo "=================================="

    read -p "Ping host (default: 8.8.8.8): " ping_host
    ping_host=${ping_host:-8.8.8.8}

    read -p "Ping count (default: 4): " ping_count
    ping_count=${ping_count:-4}

    read -p "Download test URL (default: http://speedtest.ftp.otenet.gr/files/test1Mb.db): " download_url
    download_url=${download_url:-"http://speedtest.ftp.otenet.gr/files/test1Mb.db"}

    read -p "Latency threshold in ms (default: 100): " latency_threshold
    latency_threshold=${latency_threshold:-100}

    read -p "Speed threshold in Mbps (default: 1): " speed_threshold
    speed_threshold=${speed_threshold:-1}

    read -p "Timeout in seconds (default: 30): " timeout
    timeout=${timeout:-30}

    read -p "Enable network scanning? (y/N): " enable_scan
    if [[ "$enable_scan" =~ ^[Yy]$ ]]; then
        enable_scan="true"
        read -p "Network range to scan (default: 192.168.1.0/24): " network_range
        network_range=${network_range:-"192.168.1.0/24"}
    else
        enable_scan="false"
        network_range="192.168.1.0/24"
    fi

    # Create configuration file
    cat > "$config_file" << EOF
# Network Monitor Configuration
# Generated on $(date)

# Ping settings
PING_HOST="$ping_host"
PING_COUNT=$ping_count

# Download test settings
DOWNLOAD_URL="$download_url"

# Threshold settings
LATENCY_THRESHOLD=$latency_threshold
SPEED_THRESHOLD=$speed_threshold
TIMEOUT=$timeout

# Network scanning (optional)
ENABLE_NETWORK_SCAN=$enable_scan
NETWORK_RANGE="$network_range"
EOF

    success_message "Configuration file created: $config_file"
}

# Setup cron job for periodic monitoring
setup_cron() {
    log_message "Setting up cron job for periodic monitoring..."

    echo "Choose monitoring frequency:"
    echo "1) Every 5 minutes"
    echo "2) Every 15 minutes"
    echo "3) Every 30 minutes"
    echo "4) Every hour"
    echo "5) Every 6 hours"
    echo "6) Custom interval"
    echo "7) Skip cron setup"

    read -p "Select option (1-7): " freq_choice

    case $freq_choice in
        1) cron_schedule="*/5 * * * *";;
        2) cron_schedule="*/15 * * * *";;
        3) cron_schedule="*/30 * * * *";;
        4) cron_schedule="0 * * * *";;
        5) cron_schedule="0 */6 * * *";;
        6)
            read -p "Enter custom cron schedule (e.g., '0 */2 * * *'): " cron_schedule
            ;;
        7)
            log_message "Skipping cron setup"
            return 0
            ;;
        *)
            warning_message "Invalid choice, using every 15 minutes as default"
            cron_schedule="*/15 * * * *"
            ;;
    esac

    # Add cron job
    local cron_entry="$cron_schedule $MONITOR_SCRIPT --monitor >> $SCRIPT_DIR/monitor.log 2>&1"

    # Check if cron job already exists
    if crontab -l 2>/dev/null | grep -q "$MONITOR_SCRIPT"; then
        warning_message "Cron job already exists for network monitor"
        read -p "Replace existing cron job? (y/N): " replace_cron
        if [[ "$replace_cron" =~ ^[Yy]$ ]]; then
            # Remove existing cron job
            crontab -l 2>/dev/null | grep -v "$MONITOR_SCRIPT" | crontab -
        else
            return 0
        fi
    fi

    # Add new cron job
    (crontab -l 2>/dev/null; echo "$cron_entry") | crontab -

    success_message "Cron job added: $cron_schedule"
    success_message "Logs will be written to: $SCRIPT_DIR/monitor.log"
}

# Create systemd service (Linux only)
setup_systemd_service() {
    if [[ "$OSTYPE" != "linux-gnu"* ]]; then
        log_message "Systemd service setup is only available on Linux"
        return 0
    fi

    read -p "Create systemd service for network monitoring? (y/N): " create_service
    if [[ ! "$create_service" =~ ^[Yy]$ ]]; then
        return 0
    fi

    read -p "Monitoring interval in seconds (default: 300): " interval
    interval=${interval:-300}

    # Create systemd service file
    local service_file="/tmp/$SERVICE_NAME.service"
    cat > "$service_file" << EOF
[Unit]
Description=Network Health Monitor
After=network.target

[Service]
Type=oneshot
ExecStart=$MONITOR_SCRIPT --monitor
User=$USER
WorkingDirectory=$SCRIPT_DIR

[Install]
WantedBy=multi-user.target
EOF

    # Create systemd timer file
    local timer_file="/tmp/$SERVICE_NAME.timer"
    cat > "$timer_file" << EOF
[Unit]
Description=Network Health Monitor Timer
Requires=$SERVICE_NAME.service

[Timer]
OnUnitActiveSec=${interval}s
OnBootSec=60s

[Install]
WantedBy=timers.target
EOF

    echo ""
    echo "Systemd service and timer files have been created:"
    echo "Service file: $service_file"
    echo "Timer file: $timer_file"
    echo ""
    echo "To install them, run as root:"
    echo "  sudo cp $service_file /etc/systemd/system/"
    echo "  sudo cp $timer_file /etc/systemd/system/"
    echo "  sudo systemctl daemon-reload"
    echo "  sudo systemctl enable $SERVICE_NAME.timer"
    echo "  sudo systemctl start $SERVICE_NAME.timer"
    echo ""
}

# Create log rotation configuration
setup_logrotate() {
    read -p "Setup log rotation for network monitor logs? (y/N): " setup_rotation
    if [[ ! "$setup_rotation" =~ ^[Yy]$ ]]; then
        return 0
    fi

    local logrotate_file="/tmp/network-monitor"
    cat > "$logrotate_file" << EOF
$SCRIPT_DIR/network_health.csv
$SCRIPT_DIR/monitor.log
$SCRIPT_DIR/network_scan.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 644 $USER $USER
}
EOF

    echo ""
    echo "Logrotate configuration created: $logrotate_file"
    echo "To install it, run as root:"
    echo "  sudo cp $logrotate_file /etc/logrotate.d/"
    echo ""
}

# Test the monitoring system
test_monitor() {
    log_message "Testing network monitor..."

    if [[ -x "$MONITOR_SCRIPT" ]]; then
        echo ""
        echo "Running test monitoring cycle..."
        "$MONITOR_SCRIPT" --monitor
        echo ""

        if [[ -f "$SCRIPT_DIR/network_health.csv" ]]; then
            success_message "Test completed successfully!"
            echo "Results saved to: $SCRIPT_DIR/network_health.csv"
            echo ""
            echo "Last entry:"
            tail -1 "$SCRIPT_DIR/network_health.csv"
        else
            error_message "Test failed - no log file created"
        fi
    else
        error_message "Monitor script is not executable"
    fi
}

# Create a simple dashboard script
create_dashboard() {
    local dashboard_script="$SCRIPT_DIR/dashboard.sh"

    cat > "$dashboard_script" << 'EOF'
#!/bin/bash

# Simple Network Monitor Dashboard

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/network_health.csv"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Network Health Dashboard ===${NC}"
echo "Generated: $(date)"
echo ""

if [[ ! -f "$LOG_FILE" ]]; then
    echo -e "${RED}No log file found!${NC}"
    exit 1
fi

# Show recent status
echo -e "${YELLOW}Recent Tests (Last 10):${NC}"
echo "----------------------------------------"
tail -11 "$LOG_FILE" | column -t -s','

echo ""

# Show current status
echo -e "${YELLOW}Current Status:${NC}"
LAST_ENTRY=$(tail -1 "$LOG_FILE")
if echo "$LAST_ENTRY" | grep -q "OK"; then
    echo -e "${GREEN}✓ Network is healthy${NC}"
else
    echo -e "${RED}⚠ Network issues detected${NC}"
fi

echo ""

# Quick stats
echo -e "${YELLOW}Quick Statistics:${NC}"
awk -F',' 'NR>1 {
    count++
    if($3 != "" && $3 != "0") {
        latency_sum += $3
        latency_count++
    }
    if($6 != "" && $6 != "0") {
        speed_sum += $6
        speed_count++
    }
    if($9 != "OK") issues++
}
END {
    printf "Total tests: %d\n", count
    printf "Issues detected: %d (%.1f%%)\n", issues, (issues/count)*100
    if(latency_count > 0) printf "Average latency: %.2f ms\n", latency_sum/latency_count
    if(speed_count > 0) printf "Average speed: %.2f Mbps\n", speed_sum/speed_count
}' "$LOG_FILE"

echo ""
echo "Use '$SCRIPT_DIR/network_monitor.sh --summary' for detailed statistics"
EOF

    chmod +x "$dashboard_script"
    success_message "Dashboard script created: $dashboard_script"
}

# Main setup function
main() {
    echo "Network Health Monitor Setup"
    echo "============================"
    echo ""

    # Setup permissions
    setup_permissions

    # Create configuration
    create_config

    # Setup scheduling
    echo ""
    read -p "Setup automatic scheduling? (y/N): " setup_scheduling
    if [[ "$setup_scheduling" =~ ^[Yy]$ ]]; then
        setup_cron
        setup_systemd_service
        setup_logrotate
    fi

    # Create dashboard
    create_dashboard

    # Test the system
    echo ""
    read -p "Run test monitoring cycle? (y/N): " run_test
    if [[ "$run_test" =~ ^[Yy]$ ]]; then
        test_monitor
    fi

    echo ""
    echo -e "${GREEN}Setup completed!${NC}"
    echo ""
    echo "Available commands:"
    echo "  $MONITOR_SCRIPT --monitor    # Run single monitoring cycle"
    echo "  $MONITOR_SCRIPT --summary    # Generate summary report"
    echo "  $MONITOR_SCRIPT --traceroute # Run network trace"
    echo "  $SCRIPT_DIR/dashboard.sh     # Show quick dashboard"
    echo ""
    echo "Files created:"
    echo "  Configuration: $SCRIPT_DIR/network_config.conf"
    echo "  Log file: $SCRIPT_DIR/network_health.csv"
    echo "  Dashboard: $SCRIPT_DIR/dashboard.sh"
}

# Handle command line arguments
case "${1:-}" in
    -h|--help)
        echo "Network Monitor Setup Script"
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  -h, --help     Show this help"
        echo "  --config-only  Only create configuration"
        echo "  --cron-only    Only setup cron job"
        echo "  --test-only    Only run test"
        ;;
    --config-only)
        setup_permissions
        create_config
        ;;
    --cron-only)
        setup_cron
        ;;
    --test-only)
        test_monitor
        ;;
    *)
        main
        ;;
esac
