# SphereView360

SphereView360 is a native iOS app for previewing equirectangular 360 videos on iPhone and iPad. It maps a video onto the inside of a sphere and lets you look around with touch: one-finger drag to look around, two-finger drag to pan the view, and pinch to zoom.

## Build

Build the iOS Simulator app locally:

```bash
./script/build_and_run.sh
```

Unsigned device builds and IPA packaging run in CI (`.github/workflows/build-unsigned-ipa.yml`). Download the `SphereView360iOS-unsigned` artifact from a successful run to sideload.

## iPhone and iPad

The app opens videos from Photos or Files and supports iPhone and iPad orientations. A Share extension is also included: select a video in Photos, tap Share, then choose SphereView360.

## Video support

This prototype assumes the video is already equirectangular, which is the usual format for exported 360 MP4/MOV files. Raw dual-fisheye Insta360 `.insv` footage may need to be stitched/exported first unless AVFoundation can decode it as a normal equirectangular movie.
