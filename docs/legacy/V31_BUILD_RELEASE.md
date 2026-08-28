# Build targets

Run `flutter analyze` successfully before release builds.

## Client Android APK
```powershell
cd D:\ERP\flexi_erp\apps\client_app
flutter build apk --release
```
Output is under `build\app\outputs\flutter-apk\`.

## Client Windows
```powershell
cd D:\ERP\flexi_erp\apps\client_app
flutter build windows --release
```
The project binary name is `flexi_erp`.
Distribute the complete Windows release bundle, not only the EXE.

## Client Web
```powershell
cd D:\ERP\flexi_erp\apps\client_app
flutter build web --release
```
Deploy the contents of `build\web` to your web host. Use HTTPS for production.

## POS Android APK
```powershell
cd D:\ERP\flexi_erp\apps\pos_app
flutter build apk --release
```

## POS Windows
```powershell
cd D:\ERP\flexi_erp\apps\pos_app
flutter build windows --release
```
The project binary name is `flexi_pos`.

Admin remains a Web application.
