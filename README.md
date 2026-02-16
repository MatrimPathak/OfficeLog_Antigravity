# OfficeLog

OfficeLog is a comprehensive Flutter application designed to help users track their daily office attendance, manage work logs, and visualize their attendance statistics. Built with modern Flutter practices and Firebase integration, it provides a seamless and secure user experience.

## Features

- **Authentication**: Secure login via Google Sign-In.
- **Attendance Tracking**: Log daily attendance with ease.
- **Smart Onboarding**: Location-based office setup during onboarding.
- **Statistics & Visualization**: View monthly attendance breakdowns and visual charts using `fl_chart`.
- **Theming**: Full support for both Light and Dark themes, adapting to user preference.
- **Notifications**: Scheduled local notifications to remind users to log their attendance.
- **Dynamic App Icon**: Support for dynamic app icon updating (Android/iOS).
- **Cloud Sync**: Real-time data synchronization using Firebase Firestore.
- **Offline Persistence**: Local caching with Hive and Shared Preferences for improved performance.

## Tech Stack

- **Framework**: [Flutter](https://flutter.dev/)
- **Language**: [Dart](https://dart.dev/)
- **State Management**: [Riverpod](https://riverpod.dev/)
- **Backend**: [Firebase](https://firebase.google.com/) (Authentication, Firestore)
- **Local Storage**: [Hive](https://docs.hivedb.dev/), [Shared Preferences](https://pub.dev/packages/shared_preferences)
- **Maps & Location**: [Geolocator](https://pub.dev/packages/geolocator)
- **Notifications**: [Flutter Local Notifications](https://pub.dev/packages/flutter_local_notifications)

## Getting Started

Follow these instructions to get a copy of the project up and running on your local machine.

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (Version 3.9.0 or higher)
- [Dart SDK](https://dart.dev/get-dart)
- A Firebase project with Authentication and Firestore enabled.

### Installation

1.  **Clone the repository**
    ```bash
    git clone https://github.com/yourusername/office_log.git
    cd office_log
    ```

2.  **Install Dependencies**
    ```bash
    flutter pub get
    ```

3.  **Firebase Configuration**
    - This project uses Firebase. You need to provide your own configuration files.
    - **Android**: Place `google-services.json` in `android/app/`.
    - **iOS**: Place `GoogleService-Info.plist` in `ios/Runner/`.

4.  **Run the Application**
    ```bash
    flutter run
    ```

## Project Structure

```
lib/
├── core/               # Core utilities, constants, and theme definitions
├── presentation/       # UI layer containing screens and widgets
│   ├── home/           # Home screen and related widgets
│   ├── login/          # Login screen
│   ├── onboarding/     # Onboarding flow
│   └── providers/      # Riverpod providers for state management
├── services/           # Service layer (Notification, Auth, etc.)
└── main.dart           # Application entry point
```

## Setup & Configuration

- **Environment**: Ensure your Flutter environment matches the SDK constraints in `pubspec.yaml`.
- **Permissions**: The app requires Location and Notification permissions to function correctly. These are requested at runtime.

## Contributing

1. Fork the project.
2. Create your feature branch (`git checkout -b feature/AmazingFeature`).
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`).
4. Push to the branch (`git push origin feature/AmazingFeature`).
5. Open a Pull Request.

## Development
 
 ### Generating App Icons
 The project includes a Python script to generate app icons for both Android and iOS.
 
 1.  Place your source image as `Logo_Source.png` in the root directory.
 2.  Run the script:
     ```bash
     python generate_icons.py
     ```
     *Note: Requires [Pillow](https://pypi.org/project/Pillow/) library (`pip install Pillow`).*
 
 ## License

This project is licensed under the MIT License - see the LICENSE file for details.
