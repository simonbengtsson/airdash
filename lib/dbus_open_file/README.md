### Source
https://github.com/flutter/flutter/issues/111798

### Command
- dart pub global activate dbus
- dart-dbus generate-remote-object lib/dbus_open_file/org.freedesktop.portal.OpenURI.xml -o lib/dbus_open_file/dbus_open_file.dart
- Fix type issues