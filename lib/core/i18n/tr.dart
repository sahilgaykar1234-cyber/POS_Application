import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'strings_gu.dart';
import 'strings_hi.dart';
import 'strings_mr.dart';

/// Languages the POS screens can show. Bills, receipts and WhatsApp
/// messages stay in English (they go to customers).
enum AppLanguage {
  en('English', 'English'),
  hi('हिन्दी', 'Hindi'),
  gu('ગુજરાતી', 'Gujarati'),
  mr('मराठी', 'Marathi');

  const AppLanguage(this.nativeName, this.englishName);
  final String nativeName;
  final String englishName;

  Locale get locale => Locale(name);

  static AppLanguage? fromCode(String? code) {
    for (final l in values) {
      if (l.name == code) return l;
    }
    return null;
  }
}

const _catalogs = <AppLanguage, Map<String, String>>{
  AppLanguage.hi: kHi,
  AppLanguage.gu: kGu,
  AppLanguage.mr: kMr,
};

/// The text for [english] in the current language. `{0}`, `{1}` … in the
/// text are replaced by [args]. Unknown text falls back to English.
String tr(String english, [List<Object?> args = const []]) {
  final lang = LanguageController.instance.value;
  var s = lang == AppLanguage.en ? english : (_catalogs[lang]?[english] ?? english);
  for (var i = 0; i < args.length; i++) {
    s = s.replaceAll('{$i}', '${args[i] ?? ''}');
  }
  return s;
}

/// The chosen language, remembered on this device (and per login, so a
/// manager and a captain sharing a tablet each keep their own).
class LanguageController extends ValueNotifier<AppLanguage> {
  LanguageController._() : super(AppLanguage.en);
  static final LanguageController instance = LanguageController._();

  static const _deviceKey = 'cafe_pos_language';
  static String _userKey(String uid) => 'cafe_pos_language_$uid';
  String? _uid;

  /// Device language (used on the login screen).
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      value = AppLanguage.fromCode(prefs.getString(_deviceKey)) ?? AppLanguage.en;
    } catch (_) {}
  }

  /// After sign-in: switch to the language this login chose before.
  Future<void> useFor(String? uid) async {
    _uid = uid;
    if (uid == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = AppLanguage.fromCode(prefs.getString(_userKey(uid)));
      if (saved != null && saved != value) _apply(saved);
    } catch (_) {}
  }

  Future<void> set(AppLanguage lang) async {
    _apply(lang);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_deviceKey, lang.name);
      if (_uid != null) await prefs.setString(_userKey(_uid!), lang.name);
    } catch (_) {}
  }

  void _apply(AppLanguage lang) {
    if (value == lang) return;
    value = lang;
    rebuildAllWidgets();
  }
}

/// Rebuilds every widget on screen (keeping their state) so text that was
/// already built picks up the new language straight away.
void rebuildAllWidgets() {
  final root = WidgetsBinding.instance.rootElement;
  if (root == null) return;
  void visit(Element e) {
    e.markNeedsBuild();
    e.visitChildren(visit);
  }

  root.visitChildren(visit);
}
