# Icon Generation Guide

This project includes a Python script to automatically generate all required app icon variants for both Android and iOS platforms.

## Prerequisites

- **Python**: Ensure Python is installed on your system.
- **Pillow**: The script requires the Pillow library for image processing.
  ```bash
  pip install Pillow
  ```

## Setup

1. Prepare your source image as a high-resolution PNG file.
2. Name it `Logo_Source.png`.
3. Place it in the project root directory.

## Usage

Run the following command from the project root:

```bash
python generate_icons.py
```

## Output Locations

The script will update icons in the following locations:

- **Android**: `android/app/src/main/res/mipmap-*` (Includes adaptive icons)
- **iOS**: `ios/Runner/Assets.xcassets/AppIcon.appiconset` (Standard variants)

## Notes

- Android adaptive icons use the project's primary color (`#2E88F6`) as the background.
- iOS icons are generated with the alpha channel removed to comply with App Store requirements.
