#!/bin/bash

# The directories to watch
WATCH_DIRS="./src ./include ./tests"

# The Meson test command
TEST_COMMAND="meson test -C builddir --verbose"

# Start watching the specified directories for changes
# and execute the test command upon any change
fswatch -o $WATCH_DIRS | while read num ; do
  echo "Detected changes, running tests..."
  eval $TEST_COMMAND
done
