import 'dart:convert';

import 'package:firedart/auth/token_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'reporting/logger.dart';

class SharedPreferenceStore extends TokenStore {
  SharedPreferences prefs;
  String storeKey = 'SharedPreferenceStore#token';

  SharedPreferenceStore(this.prefs);

  @override
  Token? read() {
    logger('STORE: Reading token...');
    var json = prefs.getString(storeKey);
    if (json == null) return null;

    var map = jsonDecode(json) as Map<String, dynamic>;
    var token = Token.fromMap(map);
    logger('STORE: Token read ${map['expiry']?.toString()}');
    return token;
  }

  @override
  void write(Token? token) {
    logger('STORE: Writing token...');
    if (token != null) {
      var map = token.toMap();
      var json = jsonEncode(map);
      prefs.setString(storeKey, json);
      logger('STORE: Token written ${map['expiry']?.toString()}');
    } else {
      delete();
    }
  }

  @override
  void delete() {
    prefs.remove(storeKey);
    logger('STORE: Token deleted');
  }
}
