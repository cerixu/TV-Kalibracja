# TV Kalibracja

Mobile-first PWA for guided display assessment and camera-assisted measurements.

## Target hardware
- TV: Samsung UE55TU7002KXXH
- Controller/camera: iPhone 17 Pro Max (rear camera)
- First target: PS5 gaming SDR; HDR workflow follows after SDR validation

## Current implementation
- PWA controller with camera preview and explicit permission flow.
- TV test-pattern player: black, PLUGE, 50% gray, grayscale steps, white clipping, RGB primaries, color bars.
- Five-frame center-region camera sampling; median RGB/luma, luminance spread and potential clipping estimate.
- Measurement history in IndexedDB and JSON export.
- GitHub Pages deployment workflow.

## How to run the first experiment
1. Deploy the repository with GitHub Pages over HTTPS.
2. Open `pattern.html` in the Samsung TV browser. Keep the pattern controls available.
3. Open the PWA on the iPhone and grant rear-camera permission.
4. Select the same pattern in the iPhone controller and TV pattern player.
5. Keep the phone steady, perpendicular to the screen, with the center guide over the center of the TV.
6. Capture five samples. Repeat the same pattern several times to assess repeatability.
7. Export the JSON report for analysis.

For a repeatability test, do not change TV picture settings, room lighting, camera distance, angle, or zoom between captures. Start with SDR and disable dynamic picture processing where practical.

## Measurement limitations — read before interpreting results
This is an experimental camera-assisted tool, not a colorimeter.
- iOS browser camera access does not guarantee manual exposure, ISO, shutter, focus, or white-balance control. The app reports available capability hints but does not claim to lock them.
- The camera applies device-specific image processing. RGB values are camera output values, not display-native tristimulus measurements.
- A camera image alone cannot establish absolute luminance (cd/m²), gamma/EOTF, white point, gamut coverage, or Delta E.
- Auto exposure and auto white balance can change between frames and patterns. Five-frame median reduces random variation but does not remove systematic bias.
- Reflections, viewing angle, screen uniformity, local processing and browser color management affect the reading.
- Do not apply numeric white-balance or CMS corrections based only on these readings.

The first milestone is repeatability: determine whether repeated readings under unchanged conditions are stable enough for relative diagnostics. If not, the camera workflow must remain qualitative until a supported external colorimeter is available.

## Architecture
- `/`: controller PWA, opened on iPhone
- `/pattern.html`: full-screen test-pattern player, opened on the TV
- Static hosting: GitHub Pages
- Offline shell: Service Worker + Cache Storage
- Session and measurement data: IndexedDB (no LocalStorage)

## Roadmap
1. PWA shell and TV pattern generator — implemented.
2. Camera preview, sampling, history and export — implemented experimentally.
3. Repeatability protocol and test report validation — next.
4. Measurement model with explicit confidence and limitations.
5. Samsung-specific guided settings for SDR Game Mode, then HDR.
6. Optional integration with a supported colorimeter for actual colorimetric calibration.

## Development
No build step or third-party runtime dependencies. Serve over HTTPS (GitHub Pages) for camera access.
