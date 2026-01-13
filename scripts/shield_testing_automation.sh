#!/bin/bash -e

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

# Test URL - can be overridden via environment variable
# Default URL is provided in the problem statement for testing
TEST_URL="${SHIELD_TEST_URL:-https://jellyfin.trogsmedia.com/Items/747d07d0d28a9cb044c7c228bf97e1fe/Download?api_key=9c97fc0c351149639b12aea5698f2d63}"

################################################################################
# Utility Functions
################################################################################

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo ""
    echo -e "${GREEN}==> $1${NC}"
    echo ""
}

exit_with_error() {
    log_error "$1"
    exit 1
}

################################################################################
# Safety Checks
################################################################################

check_adb_installed() {
    log_step "Checking ADB installation..."
    if ! command -v adb &> /dev/null; then
        exit_with_error "ADB is not installed or not in PATH. Please install Android SDK Platform Tools."
    fi
    log_info "ADB found: $(which adb)"
}

check_shield_connected() {
    log_step "Checking for NVIDIA Shield connection..."
    
    # Start ADB server if not running
    adb start-server > /dev/null 2>&1 || true
    
    # Get list of devices
    local devices=$(adb devices | grep -v "List of devices" | grep -v "^$" | grep "device$" || true)
    
    if [ -z "$devices" ]; then
        exit_with_error "No ADB devices connected. Please connect your NVIDIA Shield via ADB."
    fi
    
    # Count devices
    local device_count=$(echo "$devices" | wc -l)
    log_info "Found $device_count ADB device(s) connected"
    
    # Check if device is a Shield (optional check - some Shield devices may not report model)
    local model=$(adb shell getprop ro.product.model 2>/dev/null | tr -d '\r\n' || echo "Unknown")
    log_info "Device model: $model"
}

check_git_repo() {
    log_step "Verifying git repository..."
    if [ ! -d ".git" ]; then
        exit_with_error "Not in a git repository. Please run this script from the repository root."
    fi
    log_info "Git repository verified"
}

################################################################################
# Branch Management
################################################################################

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
################################################################################

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
################################################################################

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
    log_info "Waiting for app to initialize (30 seconds)..."
    sleep 30
    
    # Capture initial logcat state
    log_info "Capturing initial logcat..."
    adb logcat -d > "$RESULTS_DIR/stream_test_results.txt" 2>&1 || \
        log_warn "Failed to capture initial logcat"
    
    # Continue capturing for test duration
    log_info "Continuing test for 60 seconds..."
    sleep 60
    
    # Append final logcat state to capture full test duration
    log_info "Appending final logcat output..."
    adb logcat -d >> "$RESULTS_DIR/stream_test_results.txt" 2>&1 || \
        log_warn "Failed to append final logcat"
    
    log_info "Playback test completed"
}

################################################################################
# Results Handling
################################################################################

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
################################################################################

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
################################################################################

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
trap 'log_error "Script failed at line $LINENO. Cleaning up..."; cleanup; exit 1' ERR

# Run main function
main "$@"
