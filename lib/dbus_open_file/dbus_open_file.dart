// This file was generated using the following command and may be overwritten.
// dart-dbus generate-remote-object lib/dbus_open_file/org.freedesktop.portal.OpenURI.xml

import 'package:dbus/dbus.dart';

class OrgFreedesktopPortalOpenURI extends DBusRemoteObject {
  OrgFreedesktopPortalOpenURI(DBusClient client, String destination,
      {DBusObjectPath path = const DBusObjectPath.unchecked('/')})
      : super(client, name: destination, path: path);

  /// Gets org.freedesktop.portal.OpenURI.version
  Future<int> getversion() async {
    var value = await getProperty('org.freedesktop.portal.OpenURI', 'version',
        signature: DBusSignature('u'));
    return value.asUint32();
  }

  /// Invokes org.freedesktop.portal.OpenURI.OpenURI()
  Future<DBusObjectPath> callOpenURI(
      String parent_window, String uri, Map<String, DBusValue> options,
      {bool noAutoStart = false,
      bool allowInteractiveAuthorization = false}) async {
    var result = await callMethod(
        'org.freedesktop.portal.OpenURI',
        'OpenURI',
        [
          DBusString(parent_window),
          DBusString(uri),
          DBusDict.stringVariant(options)
        ],
        replySignature: DBusSignature('o'),
        noAutoStart: noAutoStart,
        allowInteractiveAuthorization: allowInteractiveAuthorization);
    return result.returnValues[0].asObjectPath();
  }

  /// Invokes org.freedesktop.portal.OpenURI.OpenFile()
  Future<DBusObjectPath> callOpenFile(
      String parent_window, DBusValue fd, Map<String, DBusValue> options,
      {bool noAutoStart = false,
      bool allowInteractiveAuthorization = false}) async {
    var result = await callMethod('org.freedesktop.portal.OpenURI', 'OpenFile',
        [DBusString(parent_window), fd, DBusDict.stringVariant(options)],
        replySignature: DBusSignature('o'),
        noAutoStart: noAutoStart,
        allowInteractiveAuthorization: allowInteractiveAuthorization);
    return result.returnValues[0].asObjectPath();
  }

  /// Invokes org.freedesktop.portal.OpenURI.OpenDirectory()
  Future<DBusObjectPath> callOpenDirectory(
      String parent_window, DBusValue fd, Map<String, DBusValue> options,
      {bool noAutoStart = false,
      bool allowInteractiveAuthorization = false}) async {
    var result = await callMethod(
        'org.freedesktop.portal.OpenURI',
        'OpenDirectory',
        [DBusString(parent_window), fd, DBusDict.stringVariant(options)],
        replySignature: DBusSignature('o'),
        noAutoStart: noAutoStart,
        allowInteractiveAuthorization: allowInteractiveAuthorization);
    return result.returnValues[0].asObjectPath();
  }
}
