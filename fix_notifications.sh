#!/bin/bash

echo "=== PriceActionTimer Notification Fix Script ==="
echo ""

# Kill existing app instances
echo "1. Stopping PriceActionTimer..."
killall PriceActionTimer 2>/dev/null

# Reset notification permissions
echo "2. Resetting notification permissions..."
tccutil reset Notifications com.m.PriceActionTimer 2>/dev/null

# Clear notification database
echo "3. Clearing notification database..."
killall NotificationCenter 2>/dev/null

# Wait a moment
sleep 2

echo ""
echo "✅ Done! Now please:"
echo "   1. Clean build folder in Xcode (Shift+Cmd+K)"
echo "   2. Build and run the app"
echo "   3. Grant notification permission when prompted"
echo "   4. Test the notification"
echo ""
