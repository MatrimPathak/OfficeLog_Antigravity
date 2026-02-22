# OfficeLog

OfficeLog is a comprehensive Flutter application designed to help users track their daily office attendance, manage work logs, and visualize their attendance statistics. Built with modern Flutter practices and Firebase integration, it provides a seamless and secure user experience.

## Features

- **Authentication**: Secure login via Google Sign-In.
- **Smart Attendance Tracking**: 
  - **Manual Log**: Quick one-tap attendance logging.
  - **Auto Check-in**: Background location-based logging (Geofencing) within 200m of office.
- **Statistics & Visualization**:
  - **Progress Tracking**: Compare attended days vs required days for the month.
  - **Shortfall Alerts**: Identification of pending attendance days.
  - **Visual Charts**: Comprehensive yearly and monthly trends using `fl_chart`.
- **Admin Panel**: Centralized management for holidays, office locations, and global configurations.
- **Standardized Feedback**: Premium, consistent floating snackbars for success, errors, and warnings.
- **High-Performance UI**:
  - **Theming**: Full adaptive Light and Dark themes.
  - **Glassmorphism**: Modern, translucent UI elements for a premium feel.
- **Reliable Notifications**: Automated reminders for daily logging, with support for iOS and Android.
- **Offline Persistence**: Fast, persistent storage using Hive and Shared Preferences.

## Tech Stack

- **Framework**: [Flutter](https://flutter.dev/) (SDK 3.19.0+)
- **Language**: [Dart](https://dart.dev/)
- **State Management**: [Riverpod](https://riverpod.dev/)
- **Backend**: [Firebase](https://firebase.google.com/) (Auth, Firestore)
- **Local Storage**: [Hive](https://docs.hivedb.dev/), [Shared Preferences](https://pub.dev/packages/shared_preferences)
- **Maps & Location**: [Geolocator](https://pub.dev/packages/geolocator), [Permission Handler](https://pub.dev/packages/permission_handler)
- **Notifications**: [Flutter Local Notifications](https://pub.dev/packages/flutter_local_notifications) (v20.0.0+)
- **CI/CD**: [Codemagic](https://codemagic.io/)

## Project Structure

```
lib/
├── core/               # Theme, constants, and global utility helpers
├── data/               # Models and data layer logic
├── logic/              # Business logic (Stats calculators)
├── presentation/       # UI Layer
│   ├── admin/          # Admin-only management screens
│   ├── home/           # Dashboard and Calendar view
│   ├── login/          # Google Auth integration
│   ├── onboarding/     # Initial setup and location picker
│   ├── settings/       # User preferences and feedback
│   └── summary/        # Detailed charts and breakdown list
├── services/           # Service layer (Auth, Admin, Notification, Auto Check-in)
└── main.dart           # Application bootstrapper
```

## Getting Started

### Prerequisites
- Flutter SDK 3.19.0+
- A Google Cloud/Firebase project with Google Auth and Firestore enabled.

### Installation
1.  **Clone and Install**
    ```bash
    git clone https://github.com/yourusername/office_log.git
    cd office_log
    flutter pub get
    ```
2.  **Configuration**
    - Place `google-services.json` (Android) and `GoogleService-Info.plist` (iOS) in their respective directories.
    - Run `python generate_icons.py` to set up brand assets.

## Development Utilities

### Asset Generation
The project uses a custom Python script to maintain icon consistency:
```bash
python generate_icons.py
```
*Requires `Pillow` library.*

### Automated Builds
The project is configured for **Codemagic**. See `codemagic.yaml` for build pipeline details.

## License
This project is licensed under the MIT License.
