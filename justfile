set shell := ['bash', '-ceuo', 'pipefail']

cpp_version := "17"

matlab := "disabled"
matlab-test-cmd := if matlab != "disabled" { "run-matlab-command run_tests" } else { "echo Skipping Matlab tests..." }
matlab-sandbox-cmd := if matlab != "disabled" { "run-matlab-command run_sandbox" } else { "echo Skipping Matlab sandbox..." }
benchmark-cmd := if matlab != "disabled" { "python python/benchmark.py --include-matlab" } else { "python python/benchmark.py" }


@default: run

@configure:
    mkdir -p cpp/build; \
    cd cpp/build; \
    cmake -GNinja -D CMAKE_CXX_STANDARD={{ cpp_version }} ..

@ensure-configured:
    if [ ! -f cpp/build/CMakeCache.txt ]; then \
        just configure; \
    fi

@generate:
    cd model && yardl generate

@build: generate ensure-configured
    cd cpp/build && ninja

@run: run-cpp run-python

@run-cpp: build
    #!/usr/bin/env bash
    cd cpp/build
    echo =============================
    echo Run C++ using stdin/stdout
    echo -----------------------------
    ./petsird_generator | ./petsird_analysis
    echo =============================
    echo Run C++ using Indexed files
    echo -----------------------------
    ./petsird_generator > raw.bin
    ./petsird_analysis raw.bin
    rm -f raw.bin

@run-python: generate
    #!/usr/bin/env bash
    cd python
    echo =============================
    echo Run Python using stdin/stdout
    echo -----------------------------
    python petsird_generator.py | python petsird_analysis.py
    echo =============================
    echo Run Python using Indexed files
    echo -----------------------------
    python petsird_generator.py > raw.bin
    python petsird_analysis.py raw.bin
    rm -f raw.bin
