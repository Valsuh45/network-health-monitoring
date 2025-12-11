#!/bin/bash

# Network Health Monitor Script
# Monitors bandwidth, latency, and network health
# Author: Generated for GIS-UDM project
# Date: 2025-12-11

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/network_health.csv"
CONFIG_FILE="$SCRIPT_DIR/network_config.conf"
SUMMARY_FILE="$SCRIPT_DIR/network_summary.txt"

# Default Configuration
DEFAULT_PING_HOST="8.8.8.8"
DEFAULT_PING_COUNT=4
DEFAULT_DOWNLOAD_URL="http://speedtest.ftp.otenet.gr/files/test1Mb.db"
DEFAULT_LATENCY_THRESHOLD=100
DEFAULT_SPEED_THRESHOLD=1
DEFAULT_TIMEOUT=30

# Load configuration if exists
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    # Create default config file
    cat > "$CONFIG_FILE" << EOF
# Network Monitor Configuration
PING_HOST="$DEFAULT_PING_HOST"
PING_COUNT=$DEFAULT_PING_COUNT
DOWNLOAD_URL="$DEFAULT_DOWNLOAD_URL"
LATENCY_THRESHOLD=$DEFAULT_LATENCY_THRESHOLD
SPEED_THRESHOLD=$DEFAULT_SPEED_THRESHOLD
TIMEOUT=$DEFAULT_TIMEOUT
ENABLE_NETWORK_SCAN=false
NETWORK_RANGE="192.168.1.0/24"
EOF
    source "$CONFIG_FILE"
fi

# Logging functions
log_message() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >&2
}

error_message() {
    echo "[ERROR] $1" >&2
}

warning_message() {
    echo "[WARNING] $1" >&2
}

success_message() {
    echo "[SUCCESS] $1" >&2
}

# Initialize CSV file with headers if it doesn't exist
initialize_csv() {
    if [[ ! -f "$LOG_FILE" ]]; then
        echo "timestamp,ping_host,avg_latency_ms,min_latency_ms,max_latency_ms,packet_loss_%,download_speed_mbps,download_time_sec,status" > "$LOG_FILE"
        log_message "Created new CSV log file: $LOG_FILE"
    fi
}

# Ping test function
test_latency() {
    local host="$1"
    local count="$2"

    log_message "Testing latency to $host with $count pings..."

    local ping_output=$(ping -c "$count" -W "$TIMEOUT" "$host" 2>&1)
    local ping_exit_code=$?

    if [[ $ping_exit_code -eq 0 ]]; then
        # Extract statistics from ping output
        local stats_line=$(echo "$ping_output" | grep "rtt min/avg/max/mdev\|round-trip min/avg/max")
        if [[ -n "$stats_line" ]]; then
            # Parse ping statistics
            local times=$(echo "$stats_line" | sed 's/.*= //' | sed 's/ ms.*//')
            local min_latency=$(echo "$times" | cut -d'/' -f1)
            local avg_latency=$(echo "$times" | cut -d'/' -f2)
            local max_latency=$(echo "$times" | cut -d'/' -f3)
        else
            # Fallback parsing
            avg_latency=$(echo "$ping_output" | grep -o "time=[0-9.]*" | sed 's/time=//' | awk '{sum+=$1; count++} END {if(count>0) printf "%.2f", sum/count; else print "0"}')
            min_latency="$avg_latency"
            max_latency="$avg_latency"
        fi

        # Extract packet loss
        local packet_loss=$(echo "$ping_output" | grep -o "[0-9]*% packet loss" | grep -o "[0-9]*" | head -1)
        [[ -z "$packet_loss" ]] && packet_loss=0

        echo "$avg_latency|$min_latency|$max_latency|$packet_loss"
        return 0
    else
        error_message "Ping to $host failed"
        echo "0|0|0|100"
        return 1
    fi
}

# Bandwidth test function
test_bandwidth() {
    local url="$1"

    log_message "Testing download speed from: $url"

    local temp_file=$(mktemp)
    local start_time=$(date +%s)

    if curl -L --max-time "$TIMEOUT" -s -o "$temp_file" "$url" 2>/dev/null; then
        local end_time=$(date +%s)
        local download_time=$((end_time - start_time))
        local file_size=$(stat -c%s "$temp_file" 2>/dev/null || stat -f%z "$temp_file" 2>/dev/null || echo "0")

        if [[ "$file_size" -gt 0 ]] && [[ "$download_time" -gt 0 ]]; then
            # Calculate speed in Mbps using awk for floating point
            local speed_mbps=$(awk "BEGIN {printf \"%.2f\", ($file_size / $download_time) / 1048576}")

            rm -f "$temp_file"
            echo "$speed_mbps|$download_time"
            return 0
        else
            rm -f "$temp_file"
            error_message "Invalid download or zero file size"
            echo "0|0"
            return 1
        fi
    else
        rm -f "$temp_file"
        error_message "Download failed from $url"
        echo "0|0"
        return 1
    fi
}

# Network scan function (optional)
scan_network() {
    local network_range="$1"

    if [[ "$ENABLE_NETWORK_SCAN" == "true" ]]; then
        log_message "Scanning network range: $network_range"

        if command -v nmap >/dev/null 2>&1; then
            nmap -sn "$network_range" 2>/dev/null | grep -E "Nmap scan report|Host is up" >> "$SCRIPT_DIR/network_scan.log"
        else
            # Simple ping sweep
            local base_ip=$(echo "$network_range" | cut -d'/' -f1 | cut -d'.' -f1-3)
            echo "$(date): Starting network scan of $network_range" >> "$SCRIPT_DIR/network_scan.log"

            for i in {1..254}; do
                local ip="$base_ip.$i"
                if ping -c 1 -W 1 "$ip" >/dev/null 2>&1; then
                    echo "$(date): Active IP found: $ip" >> "$SCRIPT_DIR/network_scan.log"
                fi &
            done
            wait
        fi
    fi
}

# Check thresholds and generate warnings
check_thresholds() {
    local avg_latency="$1"
    local speed_mbps="$2"
    local packet_loss="$3"
    local status="OK"

    # Check latency threshold (using awk for floating point comparison)
    if awk "BEGIN {exit !($avg_latency > $LATENCY_THRESHOLD)}"; then
        warning_message "High latency detected: ${avg_latency}ms (threshold: ${LATENCY_THRESHOLD}ms)"
        status="HIGH_LATENCY"
    fi

    # Check speed threshold
    if awk "BEGIN {exit !($speed_mbps < $SPEED_THRESHOLD)}"; then
        warning_message "Slow internet detected: ${speed_mbps}Mbps (threshold: ${SPEED_THRESHOLD}Mbps)"
        status="SLOW_SPEED"
    fi

    # Check packet loss
    if awk "BEGIN {exit !($packet_loss > 5)}"; then
        warning_message "High packet loss detected: ${packet_loss}%"
        status="PACKET_LOSS"
    fi

    echo "$status"
}

# Generate summary statistics
generate_summary() {
    if [[ ! -f "$LOG_FILE" ]]; then
        error_message "No log file found to generate summary"
        return 1
    fi

    log_message "Generating network health summary..."

    cat > "$SUMMARY_FILE" << EOF
Network Health Monitor Summary
Generated: $(date)
==================================

EOF

    # Calculate statistics using awk
    awk -F',' 'NR>1 && NF>=9 {
        if ($3 != "" && $3 != "0" && $3 ~ /^[0-9.]+$/) {
            latency_sum += $3; latency_count++;
            if ($3 > latency_max || latency_max == "") latency_max = $3;
            if ($3 < latency_min || latency_min == "") latency_min = $3;
        }
        if ($7 != "" && $7 != "0" && $7 ~ /^[0-9.]+$/) {
            speed_sum += $7; speed_count++;
            if ($7 > speed_max || speed_max == "") speed_max = $7;
            if ($7 < speed_min || speed_min == "") speed_min = $7;
        }
        total_tests++;
    }
    END {
        print "LATENCY STATISTICS:"
        if (latency_count > 0) {
            printf "  Average: %.2f ms\n", latency_sum/latency_count;
            printf "  Minimum: %.2f ms\n", latency_min;
            printf "  Maximum: %.2f ms\n", latency_max;
        } else {
            print "  No valid latency data found";
        }
        print "";
        print "BANDWIDTH STATISTICS:"
        if (speed_count > 0) {
            printf "  Average: %.2f Mbps\n", speed_sum/speed_count;
            printf "  Minimum: %.2f Mbps\n", speed_min;
            printf "  Maximum: %.2f Mbps\n", speed_max;
        } else {
            print "  No valid bandwidth data found";
        }
        print "";
        printf "Total tests conducted: %d\n", total_tests;
    }' "$LOG_FILE" >> "$SUMMARY_FILE"

    # Add recent issues
    echo "" >> "$SUMMARY_FILE"
    echo "RECENT ISSUES (Last 24 hours):" >> "$SUMMARY_FILE"
    local yesterday=$(date -d '24 hours ago' '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -v-24H '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "1970-01-01 00:00:00")
    awk -F',' -v date_threshold="$yesterday" '
    NR>1 && NF>=9 && $1 > date_threshold && $9 != "OK" {
        printf "  %s: %s\n", $1, $9
    }' "$LOG_FILE" >> "$SUMMARY_FILE"

    success_message "Summary generated: $SUMMARY_FILE"
    cat "$SUMMARY_FILE"
}

# Main monitoring function
run_monitor() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    log_message "Starting network health monitoring..."

    # Initialize CSV file
    initialize_csv

    # Test latency
    local ping_result=$(test_latency "$PING_HOST" "$PING_COUNT")
    IFS='|' read -r avg_latency min_latency max_latency packet_loss <<< "$ping_result"

    # Test bandwidth
    local bandwidth_result=$(test_bandwidth "$DOWNLOAD_URL")
    IFS='|' read -r speed_mbps download_time <<< "$bandwidth_result"

    # Check thresholds
    local status=$(check_thresholds "$avg_latency" "$speed_mbps" "$packet_loss")

    # Log results to CSV
    echo "$timestamp,$PING_HOST,$avg_latency,$min_latency,$max_latency,$packet_loss,$speed_mbps,$download_time,$status" >> "$LOG_FILE"

    # Display results
    echo ""
    echo "=== Network Health Results ==="
    echo "Timestamp: $timestamp"
    echo "Ping Host: $PING_HOST"
    echo "Latency - Avg: ${avg_latency}ms, Min: ${min_latency}ms, Max: ${max_latency}ms"
    echo "Packet Loss: ${packet_loss}%"
    echo "Download Speed: ${speed_mbps}Mbps"
    echo "Download Time: ${download_time}s"
    echo "Status: $status"
    echo "=============================="

    # Optional network scan
    if [[ "$ENABLE_NETWORK_SCAN" == "true" ]]; then
        scan_network "$NETWORK_RANGE" &
    fi

    success_message "Network monitoring completed"
}

# Traceroute function
run_traceroute() {
    local host="${1:-$PING_HOST}"

    log_message "Running traceroute to $host..."

    if command -v traceroute >/dev/null 2>&1; then
        traceroute "$host"
    elif command -v tracepath >/dev/null 2>&1; then
        tracepath "$host"
    elif command -v mtr >/dev/null 2>&1; then
        mtr -r -c 5 "$host"
    else
        error_message "No traceroute, tracepath, or mtr command available"
        return 1
    fi
}

# Usage function
usage() {
    echo "Network Health Monitor"
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  -m, --monitor       Run network monitoring (default)"
    echo "  -s, --summary       Generate and display summary statistics"
    echo "  -t, --traceroute    Run traceroute to ping host"
    echo "  -c, --config        Show current configuration"
    echo "  -v, --verbose       Enable verbose output"
    echo ""
    echo "Files:"
    echo "  Log file: $LOG_FILE"
    echo "  Config file: $CONFIG_FILE"
    echo "  Summary file: $SUMMARY_FILE"
}

# Main script logic
main() {
    case "${1:-}" in
        -h|--help)
            usage
            ;;
        -s|--summary)
            generate_summary
            ;;
        -t|--traceroute)
            run_traceroute "$2"
            ;;
        -c|--config)
            echo "Current Configuration:"
            echo "====================="
            cat "$CONFIG_FILE"
            ;;
        -v|--verbose)
            set -x
            run_monitor
            ;;
        -m|--monitor|"")
            run_monitor
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
}

# Check for required commands
check_dependencies() {
    local missing_deps=()

    for cmd in ping curl awk; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        error_message "Missing required dependencies: ${missing_deps[*]}"
        echo "Please install the missing commands and try again."
        exit 1
    fi
}

# Run dependency check
check_dependencies

# Execute main function with all arguments
main "$@"
