#!/bin/bash

set -e

echo "Building Linux binaries using Docker..."

# Build the Docker image
echo "Building Docker image..."
docker build --platform linux/amd64 -f Dockerfile.linux-build -t bisect-ppx-linux-builder .

# Run the container to build binaries
echo "Running build in container..."
CONTAINER_ID=$(docker run --platform linux/amd64 -d bisect-ppx-linux-builder)

# Wait for the container to finish
docker wait $CONTAINER_ID

# Create bin/linux directory if it doesn't exist
mkdir -p bin/linux

# Copy the built binaries from the container
echo "Copying built binaries..."
docker cp $CONTAINER_ID:/output/ppx bin/linux/ppx
docker cp $CONTAINER_ID:/output/bisect-ppx-report bin/linux/bisect-ppx-report

# Copy .cmi files if they exist
echo "Copying .cmi files..."
docker cp $CONTAINER_ID:/output/lib . 2>/dev/null || echo "No .cmi files found, skipping..."

# Clean up the container
docker rm $CONTAINER_ID

# Verify the binaries were created
echo "Verifying binaries..."
if [ -f "bin/linux/ppx" ] && [ -f "bin/linux/bisect-ppx-report" ]; then
    echo "✅ Linux binaries built successfully!"
    echo "📁 Binaries location:"
    echo "   - bin/linux/ppx"
    echo "   - bin/linux/bisect-ppx-report"
    
    # Show file sizes
    echo "📊 Binary sizes:"
    ls -lh bin/linux/ppx bin/linux/bisect-ppx-report
else
    echo "❌ Error: Binaries were not created successfully"
    exit 1
fi

echo "🎉 Done! You can now commit these binaries to your repository." 