#!/bin/bash

##############################################################################
# watchdog-scan.sh - DNS Reachability Scan for Adobe Blocklist
#
# This script scans domains from list.txt and checks which ones resolve via DNS.
# Reachable domains are added to watchdog_list.txt.
#
# Usage:
#   ./watchdog-scan.sh [mode]
#
# Modes:
#   incremental  - Only check domains not previously scanned (default)
#   full         - Re-check all domains
##############################################################################

set -e

MODE="${1:-incremental}"
STATE_FILE=".watchdog-state.json"
WATCHDOG_FILE="watchdog_list.txt"
SOURCE_FILE="list.txt"
CHANGES_FLAG=".watchdog-changes.detected"
TMP_REACHABLE=".watchdog-reachable.tmp"
NEW_STATE=".watchdog-state.new.json"

# Remove flag if exists
rm -f "$CHANGES_FLAG"

echo "=== Watchdog DNS Scan ==="
echo "Mode: $MODE"
echo "Source: $SOURCE_FILE"
echo "Output: $WATCHDOG_FILE"
echo ""

# Initialize state file if it doesn't exist
if [ ! -f "$STATE_FILE" ]; then
    echo "Initializing state file..."
    cat > "$STATE_FILE" << 'EOF'
{
  "last_full_scan": null,
  "last_incremental_scan": null,
  "checked_domains": {},
  "scan_stats": {
    "total_checked": 0,
    "reachable": 0,
    "unreachable": 0
  }
}
EOF
fi

# Extract all domains from list.txt (skip comments and empty lines)
echo "Extracting domains from $SOURCE_FILE..."
ALL_DOMAINS=$(grep -E '^0\.0\.0\.0 ' "$SOURCE_FILE" 2>/dev/null | awk '{print $2}' | sort -u)
TOTAL_DOMAINS=$(echo "$ALL_DOMAINS" | grep -c . || echo 0)
echo "Found $TOTAL_DOMAINS unique domains in source file"
echo ""

# Load current state
CHECKED_DOMAINS=$(jq -r '.checked_domains // {}' "$STATE_FILE")
TOTAL_CHECKED=$(jq -r '.scan_stats.total_checked // 0' "$STATE_FILE")
REACHABLE_COUNT=$(jq -r '.scan_stats.reachable // 0' "$STATE_FILE")

# Determine domains to check
if [ "$MODE" = "full" ]; then
    echo "Full scan mode: checking all $TOTAL_DOMAINS domains"
    DOMAINS_TO_CHECK="$ALL_DOMAINS"
else
    echo "Incremental mode: finding unchecked domains..."
    CHECKED_COUNT=$(echo "$CHECKED_DOMAINS" | jq 'length')
    echo "Already checked: $CHECKED_COUNT domains"

    # Filter out already-checked domains
    DOMAINS_TO_CHECK=""
    while IFS= read -r domain; do
        [ -z "$domain" ] && continue
        if ! echo "$CHECKED_DOMAINS" | jq -e ".\"$domain\"" > /dev/null 2>&1; then
            [ -n "$DOMAINS_TO_CHECK" ] && DOMAINS_TO_CHECK="$DOMAINS_TO_CHECK"$'\n'
            DOMAINS_TO_CHECK="$DOMAINS_TO_CHECK$domain"
        fi
    done <<< "$ALL_DOMAINS"

    TO_CHECK_COUNT=$(echo "$DOMAINS_TO_CHECK" | grep -c . 2>/dev/null || echo 0)
    echo "New domains to check: $TO_CHECK_COUNT"
fi

echo ""

# Exit early if no domains to check
if [ -z "$DOMAINS_TO_CHECK" ]; then
    echo "No new domains to check. Scan complete."
    # Update scan timestamp
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    jq -r ".last_${MODE}_scan = \"$TIMESTAMP\"" "$STATE_FILE" > "$NEW_STATE"
    mv "$NEW_STATE" "$STATE_FILE"
    exit 0
fi

# Perform DNS checks
echo "Starting DNS checks..."
NEW_REACHABLE=0
SCAN_CHECKED=0

# Temporary file for building checked_domains JSON incrementally
CHECKED_DOMAINS_TMP=".watchdog-checked.tmp"
echo "{}" > "$CHECKED_DOMAINS_TMP"

while IFS= read -r domain; do
    [ -z "$domain" ] && continue

    SCAN_CHECKED=$((SCAN_CHECKED + 1))

    # DNS resolution check with timeout
    if nslookup -retry=1 -timeout=2 "$domain" > /dev/null 2>&1; then
        echo "[$SCAN_CHECKED] ✓ $domain"
        echo "0.0.0.0 $domain" >> "$TMP_REACHABLE"
        NEW_REACHABLE=$((NEW_REACHABLE + 1))
    else
        echo "[$SCAN_CHECKED] ✗ $domain"
    fi

    # Update checked_domains in state (mark as checked with timestamp)
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    # Add domain to checked domains JSON file (incremental update to avoid argument length issues)
    jq ".\"$domain\" = \"$TIMESTAMP\"" "$CHECKED_DOMAINS_TMP" > "$CHECKED_DOMAINS_TMP.new"
    mv "$CHECKED_DOMAINS_TMP.new" "$CHECKED_DOMAINS_TMP"

done <<< "$DOMAINS_TO_CHECK"

# Load the final checked_domains from the temp file
CHECKED_DOMAINS=$(cat "$CHECKED_DOMAINS_TMP")
rm -f "$CHECKED_DOMAINS_TMP"

echo ""
echo "Scan results: $SCAN_CHECKED checked, $NEW_REACHABLE newly reachable"
echo ""

# Update watchdog_list.txt if new reachable domains found
if [ "$NEW_REACHABLE" -gt 0 ]; then
    echo "New reachable domains found! Updating $WATCHDOG_FILE..."

    # Get existing reachable domains from watchdog_list.txt (skip header)
    EXISTING_REACHABLE=""
    if [ -f "$WATCHDOG_FILE" ]; then
        EXISTING_REACHABLE=$(grep -E '^0\.0\.0\.0 ' "$WATCHDOG_FILE" 2>/dev/null || echo "")
    fi

    # Combine existing and new reachable domains, deduplicate
    TIMESTAMP=$(date -u +"%Y-%m-%d %H:%M:%S UTC")

    # Count total reachable domains
    ALL_REACHABLE=$(echo -e "$EXISTING_REACHABLE\n$(cat "$TMP_REACHABLE")" | grep -E '^0\.0\.0\.0 ' | sort -u)
    FINAL_COUNT=$(echo "$ALL_REACHABLE" | grep -c . || echo 0)

    # Rebuild file with header + all reachable domains
    {
        echo "# Adobe Telemetry Blocklist - DNS Reachable Domains Only"
        echo "# This file contains only domains that resolve via DNS"
        echo "# Generated by watchdog-scan workflow"
        echo "# Last update: $TIMESTAMP"
        echo "# Total reachable domains: $FINAL_COUNT"
        echo ""
        echo "$ALL_REACHABLE"
    } > "$WATCHDOG_FILE"

    echo "Updated $WATCHDOG_FILE with $FINAL_COUNT total reachable domains"

    # Create flag to indicate changes were made
    touch "$CHANGES_FLAG"
else
    echo "No new reachable domains found. $WATCHDOG_FILE unchanged."
fi

# Clean up temp file
rm -f "$TMP_REACHABLE"

# Update state file with new statistics
NEW_TOTAL_CHECKED=$((TOTAL_CHECKED + SCAN_CHECKED))
NEW_REACHABLE_TOTAL=$((REACHABLE_COUNT + NEW_REACHABLE))
SCAN_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Write checked_domains to a temp file to avoid argument length issues
echo "$CHECKED_DOMAINS" > "$NEW_STATE.checked"

# Update state file using slurpfile to handle large JSON
jq -r "
    .last_${MODE}_scan = \"$SCAN_TIMESTAMP\" |
    .checked_domains = \$checked |
    .scan_stats.total_checked = $NEW_TOTAL_CHECKED |
    .scan_stats.reachable = $NEW_REACHABLE_TOTAL
" "$STATE_FILE" --slurpfile checked "$NEW_STATE.checked" > "$NEW_STATE"

rm -f "$NEW_STATE.checked"
mv "$NEW_STATE" "$STATE_FILE"

echo ""
echo "=== Scan Complete ==="
echo "Total checked (this scan): $SCAN_CHECKED"
echo "Newly reachable: $NEW_REACHABLE"
echo "Total reachable in watchdog_list.txt: $(jq -r '.scan_stats.reachable' "$STATE_FILE")"
echo "State file updated: $STATE_FILE"
