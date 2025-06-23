#!/bin/bash

echo "🔧 HAG HVAC Setup - Home Assistant Token Configuration"
echo "=================================================="
echo ""

if [ -n "$HASS_TOKEN" ]; then
    echo "✅ HASS_TOKEN environment variable is already set"
    echo "🔑 Token length: ${#HASS_TOKEN} characters"
    echo ""
else
    echo "❌ HASS_TOKEN environment variable is not set"
    echo ""
    echo "To set up your Home Assistant token:"
    echo "1. Go to your Home Assistant UI"
    echo "2. Navigate to Profile → Security → Long-lived access tokens"
    echo "3. Click 'Create Token'"
    echo "4. Copy the generated token"
    echo "5. Set the environment variable:"
    echo ""
    echo "   export HASS_TOKEN=\"your_token_here\""
    echo ""
    echo "Or add it to your shell profile:"
    echo "   echo 'export HASS_TOKEN=\"your_token_here\"' >> ~/.bashrc"
    echo "   source ~/.bashrc"
    echo ""
fi

echo "🏠 Home Assistant Configuration:"
echo "   URL: ws://192.168.0.204:8123/api/websocket"
echo "   Make sure your Home Assistant is accessible at this address"
echo ""

if [ "$1" = "test" ]; then
    echo "🧪 Testing connection to Home Assistant..."
    curl -s -o /dev/null -w "%{http_code}" http://192.168.0.204:8123 | \
    {
        read http_code
        if [ "$http_code" = "200" ]; then
            echo "✅ Home Assistant is reachable"
        else
            echo "❌ Home Assistant is not reachable (HTTP $http_code)"
            echo "   Check if Home Assistant is running and accessible"
        fi
    }
fi