# Shield Testing Automation

This directory contains the automated Shield testing script for the Wholphin Android TV application.

## Overview

The `shield_testing_automation.sh` script automates the complete process of:
1. Ensuring branch cleanliness on `shield-debug-test`
2. Performing Shield device discovery via ADB
3. Running playback tests with network streaming
4. Updating test results to the `shield-exoplayer-patch` branch

## Prerequisites

### Required Tools
- **ADB (Android Debug Bridge)**: Must be installed and accessible in your PATH
  - Install via Android SDK Platform Tools
  - Download from: https://developer.android.com/studio/releases/platform-tools

### Device Requirements
- NVIDIA Shield TV device
- Shield must be connected via ADB (USB or network)
- Shield must be in developer mode with USB debugging enabled

### Repository Requirements
- Clean git working directory (no uncommitted changes)
- Access to push to the remote repository

## Setup

### 1. Enable ADB on NVIDIA Shield

1. Go to **Settings** > **Device Preferences** > **About**
2. Click on **Build** 7 times to enable Developer Options
3. Go back to **Device Preferences** > **Developer Options**
4. Enable **USB Debugging** and **Network Debugging** (if connecting over network)

### 2. Connect Shield via ADB

#### Option A: USB Connection
```bash
# Connect Shield to your computer via USB
adb devices
# You should see your Shield listed
```

#### Option B: Network Connection
```bash
# Get Shield's IP address from Settings > Network
adb connect <SHIELD_IP_ADDRESS>:5555
adb devices
# You should see your Shield listed
```

### 3. Verify Connection
```bash
adb shell getprop ro.product.model
# Should show Shield model information
```

## Usage

### Required Environment Variable

The script requires the `SHIELD_TEST_URL` environment variable to be set before execution. This URL should point to your test media file.

```bash
export SHIELD_TEST_URL="https://your-server.com/path/to/media?api_key=YOUR_KEY"
```

### Basic Execution

From the repository root, after setting the required environment variable:

```bash
export SHIELD_TEST_URL="https://your-server.com/path/to/media"
./scripts/shield_testing_automation.sh
```

**Security Note**: Never hardcode API keys in the script. Always pass them via the `SHIELD_TEST_URL` environment variable.

### What the Script Does

#### Phase 1: Safety Checks
- Verifies ADB is installed
- Confirms Shield is connected
- Validates git repository state

#### Phase 2: Branch Management
- Checks out `shield-debug-test` branch
- Ensures branch is clean and matches remote
- Creates branch if it doesn't exist

#### Phase 3: Shield Discovery
- Removes previous results for idempotency
- Captures audio flinger information
- Lists device features
- Dumps codec information (handles unavailable codec service)
- Captures display information

All discovery results are saved to `shield_results/` directory:
- `shield_audio_dump.txt`
- `shield_features.txt`
- `shield_codecs_dump.txt`
- `shield_display_dump.txt`

#### Phase 4: Playback Testing
- Launches Wholphin app on Shield
- Streams test media from network URL (provided via `SHIELD_TEST_URL`)
- Captures logcat output during playback
- Saves results to `shield_results/stream_test_results.txt`

**Note**: The test URL must be set via the `SHIELD_TEST_URL` environment variable before running the script.

#### Phase 5: Results Upload
- Switches to `shield-exoplayer-patch` branch
- Resets to match remote branch
- Creates `docs/shield/` directory
- Copies all results from `shield_results/` to `docs/shield/`
- Force-adds results to git (ensures all files are tracked)
- Commits with message: "Add Shield discovery and playback test results"
- Pushes changes to remote repository

#### Phase 6: Cleanup
- Returns to `shield-debug-test` branch
- Completes execution

## Script Features

### Idempotency
- Removes old `shield_results/` directory before each run
- Resets branches to match remote state
- Safe to run multiple times

### Error Handling
- Comprehensive error checking with colored output
- Automatic cleanup on failure
- Clear error messages for troubleshooting

### Safety Features
- Verifies ADB connectivity before proceeding
- Checks for clean git working directory
- Confirms correct branch context
- No destructive operations on app or data

## Output

### Console Output
The script provides colored, structured output:
- **Green**: Informational messages and successful operations
- **Yellow**: Warnings (non-fatal issues)
- **Red**: Errors (fatal issues)

### Generated Files

In `shield_results/` (temporary):
- `shield_audio_dump.txt` - Audio subsystem information
- `shield_features.txt` - Device feature list
- `shield_codecs_dump.txt` - Available codecs
- `shield_display_dump.txt` - Display configuration
- `stream_test_results.txt` - Playback test logcat output
- `stream_test_launch.txt` - App launch logs

In `docs/shield/` (committed to git):
- All files from `shield_results/` are copied here
- Tracked in the `shield-exoplayer-patch` branch

## Troubleshooting

### "ADB is not installed"
- Install Android SDK Platform Tools
- Add ADB to your system PATH

### "No ADB devices connected"
- Verify Shield is connected via `adb devices`
- Try disconnecting and reconnecting
- Check USB debugging is enabled on Shield

### "Working directory has uncommitted changes"
- Commit or stash your changes before running
- Use `git status` to see uncommitted changes

### "Failed to launch app"
- Ensure Wholphin app is installed on Shield
- Verify app package name: `com.github.damontecres.wholphin`
- Check Shield has network connectivity for streaming

### Codec Service Unavailable
- This is expected on some Shield configurations
- Script handles this gracefully and continues
- Check `shield_codecs_dump.txt` for status

## Notes

- The script does NOT download media files locally
- The script does NOT delete or modify the app
- The script does NOT modify `shield-exoplayer-patch` except to add results
- All operations are safe and reversible

## Script Location

`scripts/shield_testing_automation.sh`

## Support

For issues or questions about this script, please file an issue in the repository.
