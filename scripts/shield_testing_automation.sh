#!/bin/bash

################################################################################
# Shield Testing Automation Script
#
# This script automates the process of:
# 1. Ensuring branch cleanliness on shield-debug-test
# 2. Performing Shield discovery via ADB
# 3. Running playback tests
# 4. Updating results to shield-exoplayer-patch branch
#
# Requirements:
# - ADB must be installed and accessible in PATH
# - NVIDIA Shield must be connected via ADB
# - Git repository must be clean
#
# Usage:
#   ./scripts/shield_testing_automation.sh
################################################################################

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Constants
WORK_BRANCH="shield-debug-test"
RESULTS_BRANCH="shield-exoplayer-patch"
RESULTS_DIR="shield_results"
DOCS_DIR="docs/shield"
APP_PACKAGE="com.github.damontecres.wholphin"
APP_MAIN_ACTIVITY="${APP_PACKAGE}/.MainActivity"

# Configurable wait times (can be overridden via environment variables)
INIT_WAIT_TIME="${SHIELD_INIT_WAIT:-30}"
TEST_DURATION="${SHIELD_TEST_DURATION:-60}"

# Test URL - MUST be set via SHIELD_TEST_URL environment variable
# Example: export SHIELD_TEST_URL="https://your-server.com/path/to/media?api_key=YOUR_KEY"
if [ -z "$SHIELD_TEST_URL" ]; then
    echo "ERROR: SHIELD_TEST_URL environment variable is not set." >&2
    echo "Please set it before running this script:" >&2
    echo "  export SHIELD_TEST_URL=\"https://your-server.com/path/to/media\"" >&2
    exit 1
fi
TEST_URL="$SHIELD_TEST_URL"

################################################################################
# Utility Functions
# log_info prints MESSAGE to stdout prefixed with a green "[INFO]" label.

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

# log_warn prints a warning message prefixed with [WARN] in yellow.
log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# log_error prints an error message prefixed with a red [ERROR] tag.
log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# log_step prints a blank line, a green step header containing the provided message, and another blank line.
log_step() {
    echo ""
    echo -e "${GREEN}==> $1${NC}"
    echo ""
}

# exit_with_error logs an error message and exits the script with status 1.
exit_with_error() {
    log_error "$1"
    exit 1
}

################################################################################
# Safety Checks
# check_adb_installed checks that the Android Debug Bridge (adb) is available in PATH and exits with an error if it is not.

check_adb_installed() {
    log_step "Checking ADB installation..."
    if ! command -v adb &> /dev/null; then
        exit_with_error "ADB is not installed or not in PATH. Please install Android SDK Platform Tools."
    fi
    log_info "ADB found: $(which adb)"
}

# check_shield_connected checks for an attached ADB device, starts the ADB server if needed, logs the number of connected devices and the device model, and exits with an error if no devices are found.
check_shield_connected() {
    log_step "Checking for NVIDIA Shield connection..."
    
    # Start ADB server if not running
    adb start-server > /dev/null 2>&1 || true
    
    # Get list of devices
    local devices
    devices=$(adb devices | grep -v "List of devices" | grep -v "^$" | grep "device$" || true)
    
    if [ -z "$devices" ]; then
        exit_with_error "No ADB devices connected. Please connect your NVIDIA Shield via ADB."
    fi
    
    # Count devices
    local device_count
    device_count=$(echo "$devices" | wc -l)
    log_info "Found $device_count ADB device(s) connected"
    
    # Check if device is a Shield (optional check - some Shield devices may not report model)
    local model
    model=$(adb shell getprop ro.product.model 2>/dev/null | tr -d '\r\n' || echo "Unknown")
    log_info "Device model: $model"
}

# check_git_repo verifies the script is running from the root of a Git repository and exits with an error if not.
check_git_repo() {
    log_step "Verifying git repository..."
    if [ ! -d ".git" ]; then
        exit_with_error "Not in a git repository. Please run this script from the repository root."
    fi
    log_info "Git repository verified"
}

################################################################################
# Branch Management
# ensure_branch_clean ensures the given Git branch exists locally, has no uncommitted changes, and is reset to match origin/<branch> when that remote branch exists.
# $1: branch name to verify/create and make clean (e.g., "shield-debug-test").

ensure_branch_clean() {
    local branch=$1
    log_step "Ensuring branch '$branch' is clean and up-to-date..."
    
    # Fetch latest changes
    log_info "Fetching latest changes from origin..."
    git fetch origin
    
    # Check if branch exists locally
    if git rev-parse --verify "$branch" &> /dev/null; then
        log_info "Branch '$branch' exists locally"
        git checkout "$branch"
    else
        # Check if branch exists on remote
        if git rev-parse --verify "origin/$branch" &> /dev/null; then
            log_info "Branch '$branch' exists on remote, checking out..."
            git checkout -b "$branch" "origin/$branch"
        else
            log_warn "Branch '$branch' does not exist. Creating new branch..."
            git checkout -b "$branch"
        fi
    fi
    
    # Check for uncommitted changes
    if ! git diff-index --quiet HEAD --; then
        exit_with_error "Working directory has uncommitted changes. Please commit or stash them first."
    fi
    
    # Sync with remote if it exists
    if git rev-parse --verify "origin/$branch" &> /dev/null; then
        log_info "Syncing with origin/$branch..."
        git reset --hard "origin/$branch"
        log_info "Branch '$branch' is now clean and matches remote"
    else
        log_info "No remote tracking branch. Local branch '$branch' is clean"
    fi
}

################################################################################
# Shield Discovery
# prepare_results_directory prepares the results directory for a run by removing any existing "$RESULTS_DIR" and creating an empty directory at that path.

prepare_results_directory() {
    log_step "Preparing results directory..."
    
    # Remove old results for idempotency
    if [ -d "$RESULTS_DIR" ]; then
        log_info "Removing previous results directory..."
        rm -rf "$RESULTS_DIR"
    fi
    
    # Create fresh results directory
    mkdir -p "$RESULTS_DIR"
    log_info "Results directory created: $RESULTS_DIR"
}

# perform_shield_discovery captures Shield device diagnostics (audio flinger, device features, codecs, and display) via ADB and writes the outputs into files under $RESULTS_DIR.
perform_shield_discovery() {
    log_step "Performing Shield discovery via ADB..."
    
    # Audio flinger dump
    log_info "Capturing audio flinger information..."
    adb shell dumpsys media.audio_flinger > "$RESULTS_DIR/shield_audio_dump.txt" 2>&1 || \
        log_warn "Failed to capture audio flinger dump"
    
    # Features list
    log_info "Capturing device features..."
    adb shell pm list features > "$RESULTS_DIR/shield_features.txt" 2>&1 || \
        log_warn "Failed to capture features"
    
    # Codecs dump - handle cases where codec service is unavailable
    log_info "Capturing codec information..."
    if adb shell "cmd media.codec list" > "$RESULTS_DIR/shield_codecs_dump.txt" 2>&1; then
        log_info "Codec information captured successfully"
    else
        log_warn "Codec service unavailable, saving error message"
        echo "Codec service unavailable on this device" > "$RESULTS_DIR/shield_codecs_dump.txt"
    fi
    
    # Display dump
    log_info "Capturing display information..."
    adb shell dumpsys display > "$RESULTS_DIR/shield_display_dump.txt" 2>&1 || \
        log_warn "Failed to capture display dump"
    
    log_info "Shield discovery completed"
}

################################################################################
# Playback Testing
# run_playback_test runs the playback test by launching the app with $TEST_URL and collecting logcat output into the results directory (`stream_test_launch.txt` and `stream_test_results.txt`).

run_playback_test() {
    log_step "Running playback test on Shield..."
    
    log_info "Test URL: $TEST_URL"
    
    # Clear logcat buffer
    log_info "Clearing logcat buffer..."
    adb logcat -c || true
    
    # Launch the app with the test URL via Intent
    log_info "Launching app with test URL..."
    # Using ACTION_VIEW intent to open the URL
    # Note: The app needs to handle this intent or we need to use a specific test activity
    # For now, we'll launch the main activity and the app should handle the URL
    adb shell am start -n "$APP_MAIN_ACTIVITY" \
        -a android.intent.action.VIEW \
        -d "$TEST_URL" \
        2>&1 | tee -a "$RESULTS_DIR/stream_test_launch.txt" || \
        log_warn "Failed to launch app with intent"
    
    # Alternative approach: Start activity with extra data
    log_info "Starting activity with URL as extra data..."
    adb shell am start -n "$APP_MAIN_ACTIVITY" \
        --es "test_url" "$TEST_URL" \
        2>&1 | tee -a "$RESULTS_DIR/stream_test_launch.txt" || true
    
    # Wait for app to start and begin playback
    log_info "Waiting for app to initialize ($INIT_WAIT_TIME seconds)..."
    sleep "$INIT_WAIT_TIME"
    
    # Capture initial logcat state
    log_info "Capturing initial logcat..."
    adb logcat -d > "$RESULTS_DIR/stream_test_results.txt" 2>&1 || \
        log_warn "Failed to capture initial logcat"
    
    # Clear logcat buffer to avoid duplicates in next capture
    adb logcat -c || true
    
    # Continue capturing for test duration
    log_info "Continuing test for $TEST_DURATION seconds..."
    sleep "$TEST_DURATION"
    
    # Append new logcat entries only (since we cleared the buffer)
    log_info "Appending additional logcat output..."
    adb logcat -d >> "$RESULTS_DIR/stream_test_results.txt" 2>&1 || \
        log_warn "Failed to append additional logcat"
    
    log_info "Playback test completed"
}

################################################################################
# Results Handling
# update_results_branch updates the results branch by copying the contents of RESULTS_DIR into DOCS_DIR, committing any changes, and pushing them to origin/RESULTS_BRANCH.

update_results_branch() {
    log_step "Updating results to '$RESULTS_BRANCH' branch..."
    
    # Checkout results branch
    if git rev-parse --verify "$RESULTS_BRANCH" &> /dev/null; then
        log_info "Checking out existing '$RESULTS_BRANCH' branch..."
        git checkout "$RESULTS_BRANCH"
    else
        if git rev-parse --verify "origin/$RESULTS_BRANCH" &> /dev/null; then
            log_info "Checking out '$RESULTS_BRANCH' from remote..."
            git checkout -b "$RESULTS_BRANCH" "origin/$RESULTS_BRANCH"
        else
            log_warn "Creating new '$RESULTS_BRANCH' branch..."
            git checkout -b "$RESULTS_BRANCH"
        fi
    fi
    
    # Reset to remote if it exists
    if git rev-parse --verify "origin/$RESULTS_BRANCH" &> /dev/null; then
        log_info "Resetting to origin/$RESULTS_BRANCH..."
        git reset --hard "origin/$RESULTS_BRANCH"
    fi
    
    # Create docs/shield directory if needed
    log_info "Creating $DOCS_DIR directory..."
    mkdir -p "$DOCS_DIR"
    
    # Copy results to docs/shield/
    log_info "Copying Shield results to $DOCS_DIR..."
    if [ -n "$(ls -A "$RESULTS_DIR" 2>/dev/null)" ]; then
        cp -r "$RESULTS_DIR"/* "$DOCS_DIR/" 2>/dev/null || \
            exit_with_error "Failed to copy results to $DOCS_DIR"
    else
        exit_with_error "No results to copy from $RESULTS_DIR"
    fi
    
    # Force add all files to git
    log_info "Adding results to git..."
    git add -f "$DOCS_DIR" || log_warn "Failed to add $DOCS_DIR to git"
    
    # Check if there are changes to commit
    if git diff --cached --quiet; then
        log_warn "No changes to commit - results may be identical to previous run"
    else
        # Commit changes
        log_info "Committing changes..."
        git commit -m "Add Shield discovery and playback test results"
        
        # Push changes
        log_info "Pushing changes to remote..."
        git push origin "$RESULTS_BRANCH"
        
        log_info "Results successfully pushed to $RESULTS_BRANCH"
    fi
}

################################################################################
# Cleanup
# cleanup returns to the work branch named by $WORK_BRANCH if it exists and logs progress.
# It attempts to checkout that branch and suppresses any checkout errors.

cleanup() {
    log_step "Cleaning up..."
    
    # Return to work branch
    if git rev-parse --verify "$WORK_BRANCH" &> /dev/null; then
        log_info "Returning to $WORK_BRANCH branch..."
        git checkout "$WORK_BRANCH" 2>/dev/null || true
    fi
    
    log_info "Cleanup completed"
}

################################################################################
# Main Execution
# main starts the Shield testing automation workflow by performing environment checks, preparing results, running discovery and playback tests, updating the results branch, and cleaning up.

main() {
    log_step "Starting Shield Testing Automation"
    log_info "Script started at: $(date)"
    
    # Perform safety checks
    check_adb_installed
    check_git_repo
    check_shield_connected
    
    # Ensure we're on the correct branch and it's clean
    ensure_branch_clean "$WORK_BRANCH"
    
    # Prepare results directory
    prepare_results_directory
    
    # Perform Shield discovery
    perform_shield_discovery
    
    # Run playback test
    run_playback_test
    
    # Update results branch
    update_results_branch
    
    # Cleanup
    cleanup
    
    log_step "Shield Testing Automation Completed Successfully!"
    log_info "Script completed at: $(date)"
    log_info "Results have been pushed to the '$RESULTS_BRANCH' branch"
    log_info "Check the results in: $DOCS_DIR/"
}

# Trap errors and cleanup
trap 'exit_code=$?; log_error "Script failed at line $LINENO (exit code: $exit_code). Cleaning up..."; cleanup; exit $exit_code' ERR

# Run main function
main "$@"