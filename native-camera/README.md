# TV Calibrator Camera

Native iOS camera instrument for the TV-Kalibracja PWA.

## Build
The GitHub Actions workflow builds an unsigned iOS device app on a macOS runner and packages it as an IPA artifact. Download the artifact from the workflow run and sign it with Signulous before installation.

## Current scope
- Rear camera preview
- Custom ISO and shutter duration
- Focus lock and white-balance lock
- Central ROI RGB/luma sampling
- CSV export

## Important measurement limitation
This is a repeatable camera sampler, not a certified colorimeter. iPhone camera processing, sensor spectral response, lens shading, display reflections, viewing angle, and TV panel characteristics affect readings. Use fixed distance, perpendicular alignment, darkened ambient light, identical camera settings, and allow the TV to warm up. Do not interpret RGB values as absolute display color or Delta E.
