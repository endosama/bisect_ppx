#!/usr/bin/env bash
UNAME=`uname -s`
ARCH=`uname -m`
case "$UNAME" in
    "Linux") OS=linux;;
    "Darwin") 
        case "$ARCH" in
            "arm64") OS=macos_m1;;
            *) OS=macos;;
        esac;;
    *) echo "Unknown OS '$UNAME'; falling back to a source build."; esy_build;;
esac

# Check if OCaml and Dune are available
check_dependencies() {
    echo "Checking dependencies..."
    
    # Check if ocaml is available
    if ! command -v ocamlc &> /dev/null; then
        echo "OCaml not found. Installing via esy..."
        if ! command -v esy &> /dev/null; then
            echo "Error: esy not found. Please install esy first: npm install -g esy"
            exit 1
        fi
    fi
    
    # Check if dune is available
    if ! command -v dune &> /dev/null; then
        echo "Dune not found. Will install via esy..."
        if ! command -v esy &> /dev/null; then
            echo "Error: esy not found. Please install esy first: npm install -g esy"
            exit 1
        fi
    fi
}

esy_build() {
    set -e
    set -x
    
    # Check dependencies first
    check_dependencies
    
    # Install dependencies
    echo "Installing dependencies..."
    esy install -P binaries.esy.json
    
    # Build the entire project using the configuration from binaries.esy.json
    echo "Building bisect_ppx..."
    esy -P binaries.esy.json dune build -p bisect_ppx
    
    # Find and copy the built executables
    echo "Copying built executables..."
    
    # Find the PPX executable
    PPX_EXE=$(find _build -name "ppx.exe" -o -name "register.exe" | head -1)
    if [ -z "$PPX_EXE" ]; then
        # Try alternative build approach
        echo "PPX executable not found, trying alternative build..."
        esy -P binaries.esy.json dune build src/ppx/js/ppx.exe
        PPX_EXE="_build/default/src/ppx/js/ppx.exe"
    fi
    
    # Find the report executable
    REPORT_EXE=$(find _build -name "main.exe" -path "*/report/*" | head -1)
    if [ -z "$REPORT_EXE" ]; then
        # Try alternative build approach
        echo "Report executable not found, trying alternative build..."
        esy -P binaries.esy.json dune build src/report/main.exe
        REPORT_EXE="_build/default/src/report/main.exe"
    fi
    
    # Copy executables with proper permissions
    if [ -f "$PPX_EXE" ]; then
        rm -f ./ppx
        cp "$PPX_EXE" ./ppx
        chmod +x ./ppx
        echo "PPX executable copied successfully"
    else
        echo "Error: PPX executable not found"
        exit 1
    fi
    
    if [ -f "$REPORT_EXE" ]; then
        rm -f ./bisect-ppx-report
        cp "$REPORT_EXE" ./bisect-ppx-report
        chmod +x ./bisect-ppx-report
        echo "Report executable copied successfully"
    else
        echo "Error: Report executable not found"
        exit 1
    fi
    
    # Copy .cmi files to accessible locations
    echo "Copying .cmi files..."
    mkdir -p lib/ocaml
    
    # Find and copy all .cmi files from the build
    find _build -name "*.cmi" -exec cp {} lib/ocaml/ \; 2>/dev/null || true
    
    echo "Build completed successfully."
    
    exit 0
}

RESULT=$?
if [ "$RESULT" != 0 ]
then
    echo "Cannot detect OS; falling back to a source build."
    esy_build
fi


if [ ! -f bin/$OS/ppx ]
then
    echo "bin/$OS/ppx not found; falling back to a source build."
    esy_build
fi

if [ ! -f bin/$OS/bisect-ppx-report ]
then
    echo "bin/$OS/bisect-ppx-report not found; falling back to a source build."
    esy_build
fi

bin/$OS/bisect-ppx-report --help plain > /dev/null
RESULT=$?
if [ "$RESULT" != 0 ]
then
    echo "Pre-built binaries invalid; falling back to a source build."
    esy_build
fi

# Even when using pre-built binaries, ensure .cmi files are available
echo "Ensuring .cmi files are available..."
if [ ! -d "lib/ocaml" ] || [ -z "$(ls -A lib/ocaml/*.cmi 2>/dev/null)" ]; then
    echo "Missing .cmi files, generating them..."
    esy_build
fi

echo "Using pre-built binaries for system '$OS'."
rm -f ./ppx ./bisect-ppx-report
cp bin/$OS/ppx ./ppx
cp bin/$OS/bisect-ppx-report ./bisect-ppx-report
chmod +x ./ppx ./bisect-ppx-report
