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

esy_build() {
    set -e
    set -x
    esy install -P binaries.esy.json
    esy -P binaries.esy.json dune build -p bisect_ppx src/ppx/js/ppx.exe
    cp _build/default/src/ppx/js/ppx.exe ./ppx
    esy -P binaries.esy.json dune build -p bisect_ppx src/report/main.exe
    cp _build/default/src/report/main.exe ./bisect-ppx-report
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

echo "Using pre-built binaries for system '$OS'."
cp bin/$OS/ppx ./ppx
cp bin/$OS/bisect-ppx-report ./bisect-ppx-report
