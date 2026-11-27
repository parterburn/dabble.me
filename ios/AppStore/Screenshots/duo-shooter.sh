#!/bin/zsh
# iPhone Duo screenshots: XCUIScreen only gives the outer screen, so ScreenshotTests (run with
# TEST_RUNNER_DABBLE_SCREENSHOT_DISPLAY set) leaves <name>.request in its folder and waits, and
# this takes each shot from the Mac and removes the request. Start it before the test:
#   duo-shooter.sh <device> <display> <folder>
# The display is 3 for the Duo open (inner screen) and 1 closed (outer); `xcrun simctl io
# <device> screenshot x.png` lists them.
dev=$1; display=$2; dir=$3
while true; do
  for r in $dir/*.request(N); do
    xcrun simctl io $dev screenshot --display=$display "$dir/${r:t:r}.png" >/dev/null 2>&1
    rm -f $r
  done
  sleep 0.3
done
