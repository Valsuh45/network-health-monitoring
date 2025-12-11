#!/bin/bash

# Simple Network Monitor Dashboard

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/network_health.csv"

echo "=== Network Health Dashboard ==="
echo "Generated: $(date)"
echo ""

if [[ ! -f "$LOG_FILE" ]]; then
    echo "No log file found!"
    echo "Run './network_monitor.sh --monitor' to start collecting data."
    exit 1
fi

# Check if we have any data
total_entries=$(wc -l < "$LOG_FILE" 2>/dev/null || echo "0")
if [[ "$total_entries" -le 1 ]]; then
    echo "No monitoring data available yet."
    echo "Run './network_monitor.sh --monitor' to start collecting data."
    exit 1
fi

# Show recent status
echo "Recent Tests (Last 10):"
echo "----------------------------------------"
echo "Timestamp,Host,Avg_Latency(ms),Packet_Loss(%),Speed(Mbps),Status"
tail -n 10 "$LOG_FILE" | grep -v "Testing latency\|Testing download" | column -t -s','

echo ""

# Show current status
echo "Current Status:"
LAST_ENTRY=$(tail -1 "$LOG_FILE")
if echo "$LAST_ENTRY" | grep -q "OK"; then
    echo "✓ Network is healthy"
else
    STATUS=$(echo "$LAST_ENTRY" | cut -d',' -f9)
    echo "⚠ Network issues detected: $STATUS"
fi

echo ""

# Quick stats
echo "Quick Statistics:"
awk -F',' 'NR>1 && NF>=9 {
    count++
    if($3 != "" && $3 != "0" && $3 ~ /^[0-9.]+$/) {
        latency_sum += $3
        latency_count++
    }
    if($7 != "" && $7 != "0" && $7 ~ /^[0-9.]+$/) {
        speed_sum += $7
        speed_count++
    }
    if($9 != "OK") issues++
}
END {
    printf "Total tests: %d\n", count
    if(count > 0) printf "Issues detected: %d (%.1f%%)\n", issues, (issues/count)*100
    if(latency_count > 0) printf "Average latency: %.2f ms\n", latency_sum/latency_count
    if(speed_count > 0) printf "Average speed: %.2f Mbps\n", speed_sum/speed_count
}' "$LOG_FILE"

echo ""

# Show issues from last 24 hours
echo "Issues in Last 24 Hours:"
yesterday=$(date -d '24 hours ago' '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -v-24H '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "1970-01-01 00:00:00")
recent_issues=$(awk -F',' -v date_threshold="$yesterday" 'NR>1 && NF>=9 && $1 > date_threshold && $9 != "OK" {count++} END {print count+0}' "$LOG_FILE")

if [[ "$recent_issues" -eq 0 ]]; then
    echo "No issues detected in the last 24 hours"
else
    echo "Found $recent_issues issue(s):"
    awk -F',' -v date_threshold="$yesterday" 'NR>1 && NF>=9 && $1 > date_threshold && $9 != "OK" {printf "  %s: %s\n", $1, $9}' "$LOG_FILE"
fi

echo ""
echo "Commands:"
echo "  ./network_monitor.sh --monitor    # Run single test"
echo "  ./network_monitor.sh --summary    # Detailed statistics"
echo "  ./network_monitor.sh --traceroute # Network trace"
echo "  ./network_monitor.sh --config     # Show configuration"
