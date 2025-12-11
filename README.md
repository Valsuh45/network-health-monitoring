# Network Health Monitor

A comprehensive network monitoring system that tracks bandwidth, latency, and overall network health. This tool provides automated monitoring, logging, and alerting capabilities for network performance analysis.

## Features

- **Latency Monitoring**: Uses `ping` to measure network latency with configurable hosts and packet counts
- **Bandwidth Testing**: Downloads test files to measure internet speed and connection quality
- **CSV Logging**: Stores all results with timestamps in CSV format for analysis
- **Summary Statistics**: Generates min/avg/max statistics for latency and bandwidth
- **Threshold Alerts**: Configurable warnings for slow internet and high latency
- **Network Discovery**: Optional scanning of local network to identify active devices
- **Advanced Network Tools**: Integration with `traceroute`, `tracepath`, and `mtr` commands
- **Automated Scheduling**: Support for cron jobs and systemd timers
- **Log Rotation**: Built-in log management to prevent disk space issues

## Quick Start

1. **Setup the monitor**:
   ```bash
   chmod +x setup_monitor.sh
   ./setup_monitor.sh
   ```

2. **Run a single test**:
   ```bash
   ./network_monitor.sh --monitor
   ```

3. **View the dashboard**:
   ```bash
   ./dashboard.sh
   ```

## Installation

### Prerequisites

Required commands:
- `ping` - For latency testing
- `curl` - For bandwidth testing
- `bc` - For calculations

Optional commands:
- `nmap` - For advanced network scanning
- `traceroute` / `tracepath` / `mtr` - For network path analysis

### Setup Process

1. Clone or download the network monitor files
2. Run the setup script:
   ```bash
   ./setup_monitor.sh
   ```
3. Follow the interactive prompts to configure:
   - Ping target host
   - Download test URL
   - Threshold values
   - Monitoring frequency
   - Network scanning options

## Usage

### Command Line Options

```bash
./network_monitor.sh [OPTIONS]

Options:
  -h, --help          Show help message
  -m, --monitor       Run network monitoring (default)
  -s, --summary       Generate and display summary statistics
  -t, --traceroute    Run traceroute to ping host
  -c, --config        Show current configuration
  -v, --verbose       Enable verbose output
```

### Examples

**Run a single monitoring cycle:**
```bash
./network_monitor.sh --monitor
```

**Generate summary statistics:**
```bash
./network_monitor.sh --summary
```

**Run network trace:**
```bash
./network_monitor.sh --traceroute
```

**Show current configuration:**
```bash
./network_monitor.sh --config
```

## Configuration

The system uses a configuration file `network_config.conf` with the following options:

```bash
# Ping settings
PING_HOST="8.8.8.8"              # Target host for latency testing
PING_COUNT=4                      # Number of ping packets to send

# Download test settings
DOWNLOAD_URL="http://speedtest.ftp.otenet.gr/files/test1Mb.db"  # Test file URL

# Threshold settings
LATENCY_THRESHOLD=100             # High latency warning threshold (ms)
SPEED_THRESHOLD=1                 # Slow speed warning threshold (Mbps)
TIMEOUT=30                        # Network operation timeout (seconds)

# Network scanning (optional)
ENABLE_NETWORK_SCAN=false         # Enable local network discovery
NETWORK_RANGE="192.168.1.0/24"    # IP range to scan
```

### Customizing Test Parameters

**Change ping target:**
```bash
# Edit network_config.conf
PING_HOST="1.1.1.1"  # Cloudflare DNS
```

**Use different speed test file:**
```bash
# Edit network_config.conf
DOWNLOAD_URL="https://your-server.com/testfile.bin"
```

**Adjust thresholds:**
```bash
# Edit network_config.conf
LATENCY_THRESHOLD=50    # More sensitive latency detection
SPEED_THRESHOLD=5       # Higher speed requirements
```

## Output Files

### CSV Log Format
The main log file `network_health.csv` contains:

| Column | Description |
|--------|-------------|
| timestamp | When the test was performed |
| ping_host | Target host for ping test |
| avg_latency_ms | Average ping latency |
| min_latency_ms | Minimum ping latency |
| max_latency_ms | Maximum ping latency |
| packet_loss_% | Percentage of lost packets |
| download_speed_mbps | Measured download speed |
| download_time_sec | Time taken for download |
| status | Overall status (OK, HIGH_LATENCY, SLOW_SPEED, PACKET_LOSS) |

### Additional Files

- `network_summary.txt` - Statistical summary report
- `monitor.log` - System operation log (when run via cron)
- `network_scan.log` - Network discovery results (if enabled)

## Scheduling

### Cron Jobs

The setup script can configure automatic monitoring via cron:

```bash
# Every 15 minutes
*/15 * * * * /path/to/network_monitor.sh --monitor >> /path/to/monitor.log 2>&1

# Every hour
0 * * * * /path/to/network_monitor.sh --monitor >> /path/to/monitor.log 2>&1
```

### Systemd Timer (Linux)

For more advanced scheduling on Linux systems:

1. Install the systemd service files (created by setup script)
2. Enable and start the timer:
   ```bash
   sudo systemctl enable network-monitor.timer
   sudo systemctl start network-monitor.timer
   ```

## Monitoring and Alerts

### Status Indicators

- **OK**: All metrics within normal ranges
- **HIGH_LATENCY**: Ping latency exceeds threshold
- **SLOW_SPEED**: Download speed below threshold  
- **PACKET_LOSS**: High packet loss detected (>5%)

### Integration with Monitoring Systems

The CSV output can be easily integrated with:
- **Grafana**: Import CSV data for visualization
- **Nagios/Zabbix**: Parse log files for alerting
- **Custom Scripts**: Process CSV for specific needs

## Troubleshooting

### Common Issues

**Permission denied:**
```bash
chmod +x network_monitor.sh
chmod +x setup_monitor.sh
```

**Command not found:**
```bash
# Install required packages (Ubuntu/Debian)
sudo apt-get install iputils-ping curl bc

# Install optional packages
sudo apt-get install traceroute mtr-tiny nmap
```

**Download test fails:**
- Check internet connectivity
- Verify download URL is accessible
- Adjust timeout settings in configuration

**High latency false positives:**
- Choose a closer ping target
- Increase latency threshold
- Check for network congestion

### Log Analysis

**View recent issues:**
```bash
grep -v "OK" network_health.csv | tail -10
```

**Check average performance:**
```bash
./network_monitor.sh --summary
```

**Monitor real-time:**
```bash
tail -f monitor.log
```

## Advanced Features

### Network Discovery

Enable network scanning to identify active devices:

```bash
# Edit network_config.conf
ENABLE_NETWORK_SCAN=true
NETWORK_RANGE="192.168.1.0/24"
```

This feature uses `nmap` if available, otherwise performs a ping sweep.

### Custom Test URLs

For internal network testing:

```bash
# Use internal server
DOWNLOAD_URL="http://internal-server/testfile.bin"

# Use multiple test sizes
DOWNLOAD_URL="http://speedtest-server/100MB.bin"  # Larger file for better accuracy
```

### Integration Examples

**Email alerts on issues:**
```bash
#!/bin/bash
LAST_STATUS=$(tail -1 network_health.csv | cut -d',' -f9)
if [ "$LAST_STATUS" != "OK" ]; then
    echo "Network issue detected: $LAST_STATUS" | mail -s "Network Alert" admin@example.com
fi
```

**Slack notifications:**
```bash
#!/bin/bash
WEBHOOK_URL="https://hooks.slack.com/your-webhook"
LAST_ENTRY=$(tail -1 network_health.csv)
STATUS=$(echo "$LAST_ENTRY" | cut -d',' -f9)

if [ "$STATUS" != "OK" ]; then
    curl -X POST -H 'Content-type: application/json' \
        --data "{\"text\":\"Network issue: $STATUS\"}" \
        "$WEBHOOK_URL"
fi
```

## Contributing

Feel free to submit issues and enhancement requests. When contributing:

1. Test your changes thoroughly
2. Update documentation as needed
3. Follow the existing code style
4. Add appropriate error handling

## License

This project is open source. Use and modify as needed for your requirements.

## Support

For issues and questions:
1. Check the troubleshooting section
2. Review log files for error messages
3. Test with verbose mode: `./network_monitor.sh --verbose`
4. Verify configuration settings: `./network_monitor.sh --config`

---

**Note**: This tool is designed for network monitoring and diagnostics. Ensure you have permission to test network resources and comply with your organization's policies when using bandwidth testing features.