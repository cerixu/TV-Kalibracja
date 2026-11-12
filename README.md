# TV Kalibracja

Mobile-first PWA for guided display assessment and calibration assistance.

## Target hardware
- TV: Samsung UE55TU7002KXXH
- Controller/camera: iPhone 17 Pro Max
- First target: gaming SDR/HDR workflow for PS5

## Important measurement limits
This project is an assisted calibration tool, not a certified colorimeter. A phone camera's RGB response, lens shading, automatic image processing, viewing angle, and display spectral characteristics can bias measurements. Camera-only results must be treated as estimates until validated against a reference colorimeter.

The app must never claim measured Delta E, gamma, white point, or luminance accuracy unless a traceable measurement device supplies the data.

## Architecture
- `/`: controller PWA, opened on iPhone
- `/pattern.html`: full-screen test-pattern player, opened on the TV browser
- Static hosting: GitHub Pages
- Offline shell: Service Worker + Cache Storage
- Session data: IndexedDB (no LocalStorage)

## Initial milestones
1. PWA shell, TV pattern page, safe camera permission flow.
2. Test-pattern protocol and guided TV setup.
3. Camera capture experiments with fixed geometry and repeatability checks.
4. Measurement model with explicit confidence and limitations.
5. Samsung-specific guided profiles for SDR, HDR, and Game Mode.

## Development
No build step or third-party runtime dependencies. Serve over HTTPS (GitHub Pages) for camera access.
