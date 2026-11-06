import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../messaging/schema.dart';
import '../transport/android_ble.dart';

/// Points the app database at its Android file, encrypted with the key the
/// Android Keystore protects; an older unencrypted database is encrypted on
/// the way. Returns a notice for the user when the old data could not be
/// opened and a new database was started.
Future<String?> prepareAppDatabase() async {
  sqfliteFfiInit();
  if (!Platform.isAndroid) {
    throw UnsupportedError('Database của ứng dụng chỉ có trên Android');
  }
  final directory = await AndroidBleTransport.databaseDirectory();
  await Directory(directory).create(recursive: true);
  var lost = false;
  String key;
  try {
    key = await AndroidBleTransport.databaseKey();
  } on PlatformException {
    // The Keystore no longer has the key that wraps ours, so what the
    // database holds cannot be read again.
    key = await AndroidBleTransport.databaseKey(reset: true);
    lost = true;
  }
  return useMeshDatabase(
    file: path.join(directory, databaseName),
    key: key,
    discard: lost,
  );
}
