#!/bin/sh

# Script to monitor D-Bus signals from IPK extractor
# Usage: ./monitor_dbus.sh

echo "Monitoring D-Bus signals from IPK extractor..."
echo "Service: com.atlas.IPKExtractor"
echo "Interface: com.atlas.IPKExtractor"
echo "Signal: IPKInfoExtracted"
echo ""
echo "Press Ctrl+C to stop monitoring"
echo "----------------------------------------"

# Monitor D-Bus signals using busctl
busctl monitor --system --match="type='signal',interface='com.atlas.IPKExtractor',member='IPKInfoExtracted'"

