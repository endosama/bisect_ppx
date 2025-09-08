#!/usr/bin/env bash
UNAME=`uname -s`
ARCH=`uname -m`
case "$UNAME" in
    "Linux") 
        # Check if this is Ubuntu 22.04
        if [ -f /etc/lsb-release ]; then
            DISTRIB_DESCRIPTION=$(grep DISTRIB_DESCRIPTION /etc/lsb-release | cut -d= -f2 | tr -d '"')
            if [[ "$DISTRIB_DESCRIPTION" == *"Ubuntu 22.04"* ]]; then
                OS=ubuntu-22.04
            else
                OS=linux
            fi
        elif [ -f /etc/os-release ]; then
            . /etc/os-release
            if [[ "$NAME" == "Ubuntu" && "$VERSION_ID" == "22.04" ]]; then
                OS=ubuntu-22.04
            else
                OS=linux
            fi
        else
            OS=linux
        fi;;
    "Darwin") 
        case "$ARCH" in
            "arm64") OS=macos_m1;;
            *) OS=macos;;
        esac;;
    *) echo "Unknown OS '$UNAME'; falling back to a source build."; esy_build;;
esac

esy_build() {
    set -e
    set -x
    esy install -P binaries.esy.json
    echo "=== OCaml version used for building ==="
    esy -P binaries.esy.json ocaml -version
    echo "======================================="
    esy -P binaries.esy.json dune build -p bisect_ppx src/ppx/js/ppx.exe
    rm -f ./ppx
    cp _build/default/src/ppx/js/ppx.exe ./ppx
    esy -P binaries.esy.json dune build -p bisect_ppx src/report/main.exe
    rm -f ./bisect-ppx-report
    cp _build/default/src/report/main.exe ./bisect-ppx-report
    # Ensure runtime library is built to generate .cmi files
    echo "Building runtime library for .cmi files..."
    esy -P binaries.esy.json dune build -p bisect_ppx
    
    # Compile JavaScript runtime.mli to generate runtime.cmi
    echo "Compiling JavaScript runtime.mli to generate runtime.cmi..."
    esy -P binaries.esy.json ocamlc -c src/runtime/js/runtime.mli -o src/runtime/js/runtime.cmi 2>/dev/null || {
        echo "Direct compilation failed, trying with include paths..."
        esy -P binaries.esy.json ocamlc -I _build/default/src/common/.bisect_common.objs/byte -c src/runtime/js/runtime.mli -o src/runtime/js/runtime.cmi 2>/dev/null || echo "Warning: Could not compile JavaScript runtime.mli"
    }
    # Copy .cmi files for JavaScript runtime compatibility
    echo "=== Copying .cmi files generated with OCaml $(esy -P binaries.esy.json ocaml -version | head -1) ==="
    
    # Clean and recreate directories to avoid version conflicts
    rm -rf lib/ocaml src/runtime/ocaml
    mkdir -p lib/ocaml src/runtime/ocaml
    
    # Copy newly built .cmi files to both locations  
    echo "Searching for .cmi files in runtime build..."
    
    # Native runtime .cmi files
    BISECT_CMI="_build/default/src/runtime/native/.bisect.objs/byte/bisect.cmi"
    RUNTIME_CMI="_build/default/src/runtime/native/.bisect.objs/byte/bisect__Runtime.cmi"
    
    # Copy native runtime .cmi files
    if [ -f "$BISECT_CMI" ]; then
        cp "$BISECT_CMI" lib/ocaml/ 
        cp "$BISECT_CMI" src/runtime/ocaml/
        echo "bisect.cmi copied from native runtime build"
    else
        echo "Warning: bisect.cmi not found at $BISECT_CMI"
    fi
    
    if [ -f "$RUNTIME_CMI" ]; then
        cp "$RUNTIME_CMI" lib/ocaml/
        cp "$RUNTIME_CMI" src/runtime/ocaml/
        echo "bisect__Runtime.cmi copied from native runtime build"
    else
        echo "Warning: bisect__Runtime.cmi not found at $RUNTIME_CMI"
    fi
    
    # Copy JavaScript runtime .cmi file if it was generated
    JS_RUNTIME_CMI="src/runtime/js/runtime.cmi"
    if [ -f "$JS_RUNTIME_CMI" ]; then
        # Copy to the standard locations
        cp "$JS_RUNTIME_CMI" lib/ocaml/runtime.cmi
        cp "$JS_RUNTIME_CMI" src/runtime/ocaml/runtime.cmi
        echo "JavaScript runtime.cmi copied to lib/ocaml/ and src/runtime/ocaml/"
        echo "JavaScript runtime.cmi kept in original location: $JS_RUNTIME_CMI"
    else
        echo "JavaScript runtime.cmi not found, searching for alternatives..."
        # Fallback: search for any runtime.cmi from the build
        FOUND_RUNTIME_CMI=""
        for cmi_file in $(find _build -name "runtime.cmi" -print 2>/dev/null); do
            if [ -f "$cmi_file" ]; then
                cp "$cmi_file" lib/ocaml/runtime.cmi
                cp "$cmi_file" src/runtime/ocaml/runtime.cmi
                cp "$cmi_file" src/runtime/js/runtime.cmi
                echo "Found and copied runtime.cmi from: $cmi_file"
                FOUND_RUNTIME_CMI="$cmi_file"
                break
            fi
        done
        
        if [ -z "$FOUND_RUNTIME_CMI" ]; then
            echo "Warning: No runtime.cmi found anywhere in build output"
        fi
    fi
    
    echo "=== .cmi files copied to lib/ocaml/ and src/runtime/ocaml/ ==="
    mkdir -p bin/$OS || { echo "Failed to create bin/$OS directory"; exit 1; }
    cp ./ppx bin/$OS/ppx || { echo "Failed to copy ppx binary"; exit 1; }
    cp ./bisect-ppx-report bin/$OS/bisect-ppx-report || { echo "Failed to copy bisect-ppx-report binary"; exit 1; } 
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

echo "Using pre-built binaries for system '$OS'."
rm -f ./ppx
cp bin/$OS/ppx ./ppx
rm -f ./bisect-ppx-report
cp bin/$OS/bisect-ppx-report ./bisect-ppx-report

# When using pre-built binaries, clean potentially incompatible .cmi files
echo "=== Cleaning potentially incompatible .cmi files ==="
rm -rf lib/ocaml src/runtime/ocaml
mkdir -p lib/ocaml src/runtime/ocaml
echo "=== .cmi directories cleaned for pre-built binaries ==="