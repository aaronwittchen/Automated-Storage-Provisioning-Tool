#!/bin/bash
# Fix .env file by converting Windows line endings to Unix

# Create a backup of the original .env file
cp .env .env.bak

# Convert line endings and remove any control characters
dos2unix < .env.bak | tr -d '\r' > .env.new
mv .env.new .env

echo ".env file has been fixed. Original saved as .env.bak"

# Show the fixed content
echo -e "\n=== Fixed .env content ==="
cat -A .env
