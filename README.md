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

## Native iPhone measurement — experimental milestone

The native iOS app now samples the rear camera's central screen region using AVFoundation:
- Manual ISO and shutter controls, plus focus and white-balance locks.
- Five most recent camera frames are combined with a per-channel median to reduce frame noise; a one-second settling window follows a pattern change.
- A temporal coefficient of variation (CV) reports frame-to-frame luma stability for the captured five-frame set.
- Reports keep different pattern types separate; the dashboard does not average black, gray and white patterns into a meaningless single brightness value.
- RGB remains camera-processed and device-relative.
- Luma is calculated after sRGB transfer-function linearization (still not a calibrated luminance measurement).
- Reports include the fraction of sampled pixels near black/white code-value endpoints and spatial luma standard deviation.
- CSV export includes the additional fields.

### Measurement protocol
1. Warm up the TV for at least 30 minutes and keep room lighting unchanged.
2. Use one fixed picture mode and one fixed signal path for the whole comparison.
3. Put the phone perpendicular to the screen; keep distance, zoom and framing fixed.
4. Lock focus and white balance. Set manual ISO/shutter once, then do not change them within a comparison series.
5. Capture the same neutral-gray pattern at least five times. Compare the spread of readings before trusting any relative trend.
6. Check the temporal CV: below 1% is a useful repeatability sign, 1–3% means repeat the capture, and above 3% means the setup is unstable. These are provisional engineering flags, not display-calibration tolerances.
7. Repeat the series after a single TV setting change. Never change several controls at once.

Important: the PWA pattern page opened in the Samsung TV browser tests that TV-browser path, not the PS5 HDMI input. For PS5-specific results, the test pattern must be delivered through the PS5 HDMI path. The PS5 HDR calibration screens are a separate workflow. Do not mix measurements from different sources or picture modes.

This is still an experimental camera sampler, not Apple's private sensor/algorithm and not a colorimeter. The app does not have access to the iPhone ambient-light sensor's raw measurements. Camera ISP processing, spectral response, panel reflections, angle, and display processing remain sources of systematic error. Do not infer Delta E, absolute cd/m², gamma/EOTF, white point or gamut coverage from these values.

## Roadmap
1. PWA shell and TV pattern generator — implemented.
2. Native camera sampling with manual controls and robust frame aggregation — experimental implementation.
3. Repeatability validation on the actual iPhone and TV — pending real-device testing.
4. Confidence scoring and pattern-specific interpretation — next.
5. Samsung-specific guided settings for SDR Game Mode, then HDR.
6. Optional integration with a supported colorimeter for actual colorimetric calibration.

## Development
No build step or third-party runtime dependencies. Serve over HTTPS (GitHub Pages) for camera access.
