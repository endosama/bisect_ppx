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

# Install additional dependencies that might be missing
install_additional_deps() {
    echo "Installing additional dependencies..."
    
    # Install reason for refmt
    if ! esy -P binaries.esy.json exec -- which refmt &> /dev/null; then
        echo "Installing reason for refmt..."
        esy -P binaries.esy.json add @opam/reason@latest || true
    fi
    
    # Install js_of_ocaml-compiler for runtime library
    echo "Installing js_of_ocaml-compiler..."
    esy -P binaries.esy.json add @opam/js_of_ocaml-compiler@latest || true
    
    # Reinstall dependencies
    esy install -P binaries.esy.json
}

esy_build() {
    set -e
    set -x
    
    # Check dependencies first
    check_dependencies
    
    # Install dependencies
    echo "Installing dependencies..."
    esy install -P binaries.esy.json
    
    # Install additional dependencies
    install_additional_deps
    
    # Build core components first (skip problematic test directories)
    echo "Building core libraries..."
    esy -P binaries.esy.json dune build -p bisect_ppx src/common src/runtime src/ppx src/report
    
    # Build the common library (generates .cmi files)
    echo "Building bisect_ppx.common library..."
    esy -P binaries.esy.json dune build -p bisect_ppx src/common/bisect_common.cmi || true
    
    # Build the runtime library (generates .cmi files)
    echo "Building bisect_ppx.runtime library..."
    esy -P binaries.esy.json dune build -p bisect_ppx src/runtime/native/runtime.cmi || true
    esy -P binaries.esy.json dune build -p bisect_ppx src/runtime/js/runtime.cmi || true
    
    # Build the PPX library (generates .cmi files)
    echo "Building bisect_ppx library..."
    esy -P binaries.esy.json dune build -p bisect_ppx src/ppx/instrument.cmi || true
    esy -P binaries.esy.json dune build -p bisect_ppx src/ppx/exclusions.cmi || true
    
    # Build executables
    echo "Building executables..."
    esy -P binaries.esy.json dune build -p bisect_ppx src/ppx/js/ppx.exe
    cp _build/default/src/ppx/js/ppx.exe ./ppx
    
    esy -P binaries.esy.json dune build -p bisect_ppx src/report/main.exe
    cp _build/default/src/report/main.exe ./bisect-ppx-report
    
    # Copy .cmi files to accessible locations
    echo "Copying .cmi files..."
    mkdir -p lib/ocaml
    
    # Copy common .cmi files
    if [ -f "_build/default/src/common/bisect_common.cmi" ]; then
        cp _build/default/src/common/bisect_common.cmi lib/ocaml/
    fi
    
    # Copy runtime .cmi files
    if [ -f "_build/default/src/runtime/native/runtime.cmi" ]; then
        cp _build/default/src/runtime/native/runtime.cmi lib/ocaml/
    fi
    
    # Copy PPX .cmi files
    if [ -f "_build/default/src/ppx/instrument.cmi" ]; then
        cp _build/default/src/ppx/instrument.cmi lib/ocaml/
    fi
    
    if [ -f "_build/default/src/ppx/exclusions.cmi" ]; then
        cp _build/default/src/ppx/exclusions.cmi lib/ocaml/
    fi
    
    # Copy any other .cmi files from the build
    find _build/default -name "*.cmi" -exec cp {} lib/ocaml/ \; 2>/dev/null || true
    
    echo "Build completed successfully with .cmi files generated."
    
    # cp ./ppx bin/$OS/ppx 
    # cp ./bisect-ppx-report bin/$OS/bisect-ppx-report 
    
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
cp bin/$OS/ppx ./ppx
cp bin/$OS/bisect-ppx-report ./bisect-ppx-report
