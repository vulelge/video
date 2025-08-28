#!/bin/sh

# Script to extract basic info from IPK files in a directory
# Usage: ./read_ipk.sh [-v] <directory_path>

set -e  # Exit on error

# Global variables to store extracted information
FILEPATH=""
ID=""
NAME=""
VERBOSE=0
LOG_FILE="/tmp/read_ipk_$(date +%Y%m%d_%H%M%S).log"

# Logging function
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Debug logging function
debug_log() {
    if [ "$VERBOSE" -eq 1 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - DEBUG: $1" | tee -a "$LOG_FILE" >&2
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') - DEBUG: $1" >> "$LOG_FILE"
    fi
}

# Parse command line arguments
while [ $# -gt 0 ]; do
    case "$1" in
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        -*)
            echo "Error: Unknown option $1" >&2
            echo "Usage: $0 [-v] <directory_path>" >&2
            exit 1
            ;;
        *)
            SEARCH_DIR="$1"
            shift
            ;;
    esac
done

# Check if directory is specified
if [ -z "$SEARCH_DIR" ]; then
    echo "Error: Please specify a directory path" >&2
    echo "Usage: $0 [-v] <directory_path>" >&2
    exit 1
fi

# Check if directory exists
if [ ! -d "$SEARCH_DIR" ]; then
    echo "Error: Directory '$SEARCH_DIR' not found" >&2
    exit 1
fi

# Initialize log file
log_message "Starting IPK extraction script"
log_message "Search directory: $SEARCH_DIR"
log_message "Verbose mode: $VERBOSE"

# Find all IPK files in directory and subdirectories
find_ipk_files() {
    search_dir="$1"
    
    debug_log "Searching for IPK files in: $search_dir"
    
    # Find all .ipk files recursively
    find "$search_dir" -name "*.ipk" -type f 2>/dev/null
}

# Process multiple IPK files and collect information
process_ipk_files() {
    search_dir="$1"
    
    # Temporary file to store results
    temp_results=$(mktemp)
    
    # Cleanup function for temp file
    cleanup_temp() {
        rm -f "$temp_results"
    }
    trap cleanup_temp EXIT
    
    # Find all IPK files
    ipk_files=$(find_ipk_files "$search_dir")
    
    if [ -z "$ipk_files" ]; then
        debug_log "No IPK files found in $search_dir"
        # Still send empty D-Bus signal
        send_dbus_signal_multiple_empty
        return 0
    fi
    
    debug_log "Found IPK files:"
    echo "$ipk_files" | while read -r file; do
        debug_log "  - $file"
    done
    
    # Process each IPK file using for loop with newlines as separator
    OLD_IFS="$IFS"
    IFS='
'
    for ipk_file in $ipk_files; do
        if [ -n "$ipk_file" ] && [ -f "$ipk_file" ]; then
            debug_log "Processing: $ipk_file"
            
            # Extract info from this IPK file
            if extract_ipk_info "$ipk_file"; then
                # Write results to temp file in format: filepath|id|name
                echo "$FILEPATH|$ID|$NAME" >> "$temp_results"
                
                debug_log "Processed $ipk_file - ID: $ID, Name: $NAME"
            else
                debug_log "Failed to process $ipk_file"
            fi
        fi
    done
    IFS="$OLD_IFS"
    
    # Check if we have any results
    if [ ! -s "$temp_results" ]; then
        debug_log "No valid IPK files processed"
        # Still send empty D-Bus signal
        send_dbus_signal_multiple_empty
        return 0
    fi
    
    # Send D-Bus signal with all collected data
    send_dbus_signal_multiple "$temp_results"
    
    return 0
}
# Check required tools
check_tools() {
    missing_tools=""
    
    if ! command -v ar >/dev/null 2>&1; then
        missing_tools="$missing_tools ar"
    fi
    
    if ! command -v tar >/dev/null 2>&1; then
        missing_tools="$missing_tools tar"
    fi
    
    if ! command -v gzip >/dev/null 2>&1; then
        missing_tools="$missing_tools gzip"
    fi
    
    if ! command -v zstd >/dev/null 2>&1; then
        missing_tools="$missing_tools zstd"
    fi
    
    if ! command -v busctl >/dev/null 2>&1; then
        missing_tools="$missing_tools busctl"
    fi
    
    if [ -n "$missing_tools" ]; then
        echo "Error: The following tools are required:$missing_tools" >&2
        echo "Ubuntu/Debian: sudo apt-get install binutils tar gzip zstd systemd"
        echo "CentOS/RHEL: sudo yum install binutils tar gzip zstd systemd"
        exit 1
    fi
}

# Extract IPK information
extract_ipk_info() {
    ipk_file="$1"
    # Store original file path before changing directory
    original_filepath=$(realpath "$ipk_file")
    temp_dir=$(mktemp -d)
    
    debug_log "Using temp directory: $temp_dir"
    debug_log "Original file path: $original_filepath"
    
    # Save current directory
    current_dir=$(pwd)
    
    # Copy IPK file to temporary directory
    cp "$ipk_file" "$temp_dir/"
    cd "$temp_dir"
    
    ipk_basename=$(basename "$ipk_file")
    
    debug_log "Working with file: $ipk_basename"
    
    # Extract ar archive
    if ar -t "$ipk_basename" >/dev/null 2>&1; then
        ar -x "$ipk_basename"
        
        debug_log "Extracted files from IPK"
        ls -la >> "$LOG_FILE" 2>&1
        
        # Find appinfo.json
        app_id=""
        app_name=""
        
        # Look for appinfo.json in control archive first
        debug_log "Looking for appinfo.json in control archives..."
        
        for archive in control.tar.gz control.tar.xz control.tar.zst; do
            if [ -f "$archive" ]; then
                if [ "$VERBOSE" -eq 1 ]; then
                    echo "DEBUG: Checking control archive: $archive" >&2
                fi
                
                case "$archive" in
                    *.gz)
                        if [ "$VERBOSE" -eq 1 ]; then
                            echo "DEBUG: Contents of $archive:" >&2
                            tar -tzf "$archive" >&2
                        fi
                        if tar -tzf "$archive" | grep -q "appinfo.json"; then
                            if [ "$VERBOSE" -eq 1 ]; then
                                echo "DEBUG: Found appinfo.json in $archive, extracting..." >&2
                            fi
                            tar -xzf "$archive" "appinfo.json" 2>/dev/null || true
                        fi
                        ;;
                    *.xz)
                        if [ "$VERBOSE" -eq 1 ]; then
                            echo "DEBUG: Contents of $archive:" >&2
                            tar -tJf "$archive" >&2
                        fi
                        if tar -tJf "$archive" | grep -q "appinfo.json"; then
                            if [ "$VERBOSE" -eq 1 ]; then
                                echo "DEBUG: Found appinfo.json in $archive, extracting..." >&2
                            fi
                            tar -xJf "$archive" "appinfo.json" 2>/dev/null || true
                        fi
                        ;;
                    *.zst)
                        if [ "$VERBOSE" -eq 1 ]; then
                            echo "DEBUG: Contents of $archive:" >&2
                            zstd -dc "$archive" | tar -tf - >&2
                        fi
                        if zstd -dc "$archive" | tar -tf - | grep -q "appinfo.json"; then
                            if [ "$VERBOSE" -eq 1 ]; then
                                echo "DEBUG: Found appinfo.json in $archive, extracting..." >&2
                            fi
                            zstd -dc "$archive" | tar -xf - "appinfo.json" 2>/dev/null || true
                        fi
                        ;;
                esac
                if [ -f "appinfo.json" ]; then
                    if [ "$VERBOSE" -eq 1 ]; then
                        echo "DEBUG: Successfully extracted appinfo.json from control archive" >&2
                    fi
                    break
                fi
            fi
        done
        
        # If not found in control, check data archive
        if [ ! -f "appinfo.json" ]; then
            if [ "$VERBOSE" -eq 1 ]; then
                echo "DEBUG: appinfo.json not found in control, checking data archives..." >&2
            fi
            
            for archive in data.tar.gz data.tar.xz data.tar.zst; do
                if [ -f "$archive" ]; then
                    if [ "$VERBOSE" -eq 1 ]; then
                        echo "DEBUG: Checking data archive: $archive" >&2
                    fi
                    
                    case "$archive" in
                        *.gz)
                            if [ "$VERBOSE" -eq 1 ]; then
                                echo "DEBUG: Contents of $archive:" >&2
                                tar -tzf "$archive" >&2
                            fi
                            if tar -tzf "$archive" | grep -q "appinfo.json"; then
                                if [ "$VERBOSE" -eq 1 ]; then
                                    echo "DEBUG: Found appinfo.json in $archive, extracting..." >&2
                                fi
                                # Extract all files, then find appinfo.json
                                tar -xzf "$archive" 2>/dev/null || true
                            fi
                            ;;
                        *.xz)
                            if [ "$VERBOSE" -eq 1 ]; then
                                echo "DEBUG: Contents of $archive:" >&2
                                tar -tJf "$archive" >&2
                            fi
                            if tar -tJf "$archive" | grep -q "appinfo.json"; then
                                if [ "$VERBOSE" -eq 1 ]; then
                                    echo "DEBUG: Found appinfo.json in $archive, extracting..." >&2
                                fi
                                # Extract all files, then find appinfo.json
                                tar -xJf "$archive" 2>/dev/null || true
                            fi
                            ;;
                        *.zst)
                            if [ "$VERBOSE" -eq 1 ]; then
                                echo "DEBUG: Contents of $archive:" >&2
                                zstd -dc "$archive" | tar -tf - >&2
                            fi
                            if zstd -dc "$archive" | tar -tf - | grep -q "appinfo.json"; then
                                if [ "$VERBOSE" -eq 1 ]; then
                                    echo "DEBUG: Found appinfo.json in $archive, extracting..." >&2
                                fi
                                # Extract all files, then find appinfo.json
                                zstd -dc "$archive" | tar -xf - 2>/dev/null || true
                            fi
                            ;;
                    esac
                    if [ -f "appinfo.json" ] || find . -name "appinfo.json" -type f >/dev/null 2>&1; then
                        if [ "$VERBOSE" -eq 1 ]; then
                            echo "DEBUG: Successfully extracted appinfo.json from data archive" >&2
                        fi
                        break
                    fi
                fi
            done
        fi
        
        # Extract information from appinfo.json if found
        appinfo_file=$(find . -name "appinfo.json" 2>/dev/null | head -n 1)
        if [ -n "$appinfo_file" ] && [ -f "$appinfo_file" ]; then
            if [ "$VERBOSE" -eq 1 ]; then
                echo "DEBUG: Found appinfo.json at: $appinfo_file" >&2
                echo "DEBUG: Content:" >&2
                cat "$appinfo_file" >&2
            fi
            
            app_id=$(grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' "$appinfo_file" 2>/dev/null | sed 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
            app_name=$(grep -o '"title"[[:space:]]*:[[:space:]]*"[^"]*"' "$appinfo_file" 2>/dev/null | sed 's/.*"title"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
            
            if [ -z "$app_name" ]; then
                app_name=$(grep -o '"name"[[:space:]]*:[[:space:]]*"[^"]*"' "$appinfo_file" 2>/dev/null | sed 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
            fi
            
            if [ "$VERBOSE" -eq 1 ]; then
                echo "DEBUG: Extracted from appinfo.json - ID: '$app_id', Name: '$app_name'" >&2
            fi
        else
            if [ "$VERBOSE" -eq 1 ]; then
                echo "DEBUG: No appinfo.json found in any archive" >&2
            fi
        fi
        
        # Try opkg as fallback for ID if not found in appinfo.json
        if [ -z "$app_id" ] && command -v opkg >/dev/null 2>&1; then
            if [ "$VERBOSE" -eq 1 ]; then
                echo "DEBUG: Trying opkg info as fallback..." >&2
            fi
            
            opkg_output=$(opkg info "$ipk_file" 2>/dev/null || echo "")
            if [ -n "$opkg_output" ]; then
                app_id=$(echo "$opkg_output" | grep "^Package:" | sed 's/^Package:[[:space:]]*//')
                
                if [ "$VERBOSE" -eq 1 ]; then
                    echo "DEBUG: Got ID from opkg: '$app_id'" >&2
                fi
            fi
        fi
        
        # Set global variables (use original file path, not temp copy)
        FILEPATH="$original_filepath"  # Use pre-stored original path
        ID=${app_id:-"N/A"}
        NAME=${app_name:-"N/A"}
        
        debug_log "Final results - FilePath: '$FILEPATH', ID: '$ID', Name: '$NAME'"
        
        # Restore original directory and cleanup
        cd "$current_dir"
        rm -rf "$temp_dir"
        
        return 0
    else
        echo "Error: Cannot read IPK file" >&2
        # Restore original directory and cleanup on error too
        cd "$current_dir"
        rm -rf "$temp_dir"
        return 1
    fi
}

# Send D-Bus signal with multiple IPK information entries
send_dbus_signal_multiple() {
    results_file="$1"
    
    # D-Bus service and interface configuration
    SERVICE_NAME="com.atlas.IPKExtractor"
    OBJECT_PATH="/com/atlas/IPKExtractor"
    INTERFACE_NAME="com.atlas.IPKExtractor"
    SIGNAL_NAME="IPKInfoExtracted"
    
    debug_log "Preparing D-Bus signal with multiple entries..."
    debug_log "Service: $SERVICE_NAME"
    debug_log "Object: $OBJECT_PATH"
    debug_log "Interface: $INTERFACE_NAME"
    debug_log "Signal: $SIGNAL_NAME"
    
    # Build D-Bus array argument (as string - simpler approach)
    # We'll send it as a single string and let the receiver parse it
    dbus_data=""
    entry_count=0
    
    while IFS='|' read -r filepath id name; do
        if [ -n "$filepath" ] && [ -n "$id" ] && [ -n "$name" ]; then
            debug_log "Adding entry - FilePath: '$filepath', ID: '$id', Name: '$name'"
            
            # Build JSON-like string for each entry
            if [ $entry_count -gt 0 ]; then
                dbus_data="$dbus_data,"
            fi
            dbus_data="$dbus_data{\"filepath\":\"$filepath\",\"id\":\"$id\",\"name\":\"$name\"}"
            entry_count=$((entry_count + 1))
        fi
    done < "$results_file"
    
    # Wrap in array brackets (send empty array if no entries)
    if [ $entry_count -eq 0 ]; then
        dbus_message="[]"
        debug_log "No entries found, sending empty array"
    else
        dbus_message="[$dbus_data]"
    fi
    
    debug_log "Sending D-Bus signal with $entry_count entries..."
    debug_log "D-Bus message: $dbus_message"
    
    # Send D-Bus signal using busctl with string type (simpler than a{sss})
    # Format: busctl emit <object-path> <interface> <signal> <signature> <args>
    if busctl emit "$OBJECT_PATH" "$INTERFACE_NAME" "$SIGNAL_NAME" "s" "$dbus_message" 2>/dev/null; then
        debug_log "D-Bus signal sent successfully with $entry_count entries"
        log_message "Successfully processed $entry_count IPK files and sent D-Bus signal"
        echo "Successfully processed $entry_count IPK files and sent D-Bus signal"
        return 0
    else
        log_message "Failed to send D-Bus signal"
        echo "Warning: Failed to send D-Bus signal" >&2
        return 1
    fi
}

# Send empty D-Bus signal when no IPK files found
send_dbus_signal_multiple_empty() {
    # D-Bus service and interface configuration
    SERVICE_NAME="com.atlas.IPKExtractor"
    OBJECT_PATH="/com/atlas/IPKExtractor"
    INTERFACE_NAME="com.atlas.IPKExtractor"
    SIGNAL_NAME="IPKInfoExtracted"
    
    debug_log "Preparing empty D-Bus signal..."
    debug_log "Service: $SERVICE_NAME"
    debug_log "Object: $OBJECT_PATH"
    debug_log "Interface: $INTERFACE_NAME"
    debug_log "Signal: $SIGNAL_NAME"
    
    # Send empty JSON array
    dbus_message="[]"
    
    debug_log "Sending empty D-Bus signal..."
    debug_log "D-Bus message: $dbus_message"
    
    # Send D-Bus signal using busctl with string type
    if busctl emit "$OBJECT_PATH" "$INTERFACE_NAME" "$SIGNAL_NAME" "s" "$dbus_message" 2>/dev/null; then
        debug_log "Empty D-Bus signal sent successfully"
        log_message "No IPK files found, sent empty D-Bus signal"
        echo "No IPK files found, sent empty D-Bus signal"
        return 0
    else
        log_message "Failed to send empty D-Bus signal"
        echo "Warning: Failed to send empty D-Bus signal" >&2
        return 1
    fi
}

# Main function
main() {
    # Check required tools
    check_tools
    
    # Process all IPK files in directory
    if process_ipk_files "$SEARCH_DIR"; then
        debug_log "Successfully processed all IPK files"
        log_message "Script completed successfully"
        echo "Log file: $LOG_FILE"
    else
        log_message "Failed to process IPK files in directory"
        echo "Error: Failed to process IPK files in directory" >&2
        echo "Log file: $LOG_FILE"
        exit 1
    fi
}

# Execute main function only if script is run directly (not sourced)
if [ "${0##*/}" = "read_ipk.sh" ]; then
    main
fi
