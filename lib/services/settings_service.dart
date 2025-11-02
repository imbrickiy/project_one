import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  static const String _keyCacheSize = 'player_cache_size';
  static const String _keyCacheEnabled = 'player_cache_enabled';
  static const String _keyAutoPlay = 'auto_play';
  static const String _keyConnectionTimeout = 'connection_timeout';
  static const String _keyPlaybackTimeout = 'playback_timeout';
  static const String _keyVolume = 'volume';
  static const String _keyHardwareAcceleration = 'hardware_acceleration';

  // Значения по умолчанию
  static const int defaultCacheSize = 64; // МБ
  static const bool defaultCacheEnabled = true;
  static const bool defaultAutoPlay = true;
  static const int defaultConnectionTimeout = 15; // секунды
  static const int defaultPlaybackTimeout = 10; // секунды
  static const double defaultVolume = 1.0; // 0.0 - 1.0
  static const bool defaultHardwareAcceleration = true;

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  // Настройки кэша
  Future<void> setCacheSize(int sizeMB) async {
    await init();
    await _prefs!.setInt(_keyCacheSize, sizeMB);
  }

  Future<int> getCacheSize() async {
    await init();
    return _prefs!.getInt(_keyCacheSize) ?? defaultCacheSize;
  }

  Future<void> setCacheEnabled(bool enabled) async {
    await init();
    await _prefs!.setBool(_keyCacheEnabled, enabled);
  }

  Future<bool> getCacheEnabled() async {
    await init();
    return _prefs!.getBool(_keyCacheEnabled) ?? defaultCacheEnabled;
  }

  // Автоматическое воспроизведение
  Future<void> setAutoPlay(bool enabled) async {
    await init();
    await _prefs!.setBool(_keyAutoPlay, enabled);
  }

  Future<bool> getAutoPlay() async {
    await init();
    return _prefs!.getBool(_keyAutoPlay) ?? defaultAutoPlay;
  }

  // Таймаут подключения
  Future<void> setConnectionTimeout(int seconds) async {
    await init();
    await _prefs!.setInt(_keyConnectionTimeout, seconds);
  }

  Future<int> getConnectionTimeout() async {
    await init();
    return _prefs!.getInt(_keyConnectionTimeout) ?? defaultConnectionTimeout;
  }

  // Таймаут воспроизведения
  Future<void> setPlaybackTimeout(int seconds) async {
    await init();
    await _prefs!.setInt(_keyPlaybackTimeout, seconds);
  }

  Future<int> getPlaybackTimeout() async {
    await init();
    return _prefs!.getInt(_keyPlaybackTimeout) ?? defaultPlaybackTimeout;
  }

  // Громкость
  Future<void> setVolume(double volume) async {
    await init();
    await _prefs!.setDouble(_keyVolume, volume.clamp(0.0, 1.0));
  }

  Future<double> getVolume() async {
    await init();
    return _prefs!.getDouble(_keyVolume) ?? defaultVolume;
  }

  // Аппаратное ускорение
  Future<void> setHardwareAcceleration(bool enabled) async {
    await init();
    await _prefs!.setBool(_keyHardwareAcceleration, enabled);
  }

  Future<bool> getHardwareAcceleration() async {
    await init();
    return _prefs!.getBool(_keyHardwareAcceleration) ?? defaultHardwareAcceleration;
  }

  // Сброс всех настроек к значениям по умолчанию
  Future<void> resetToDefaults() async {
    await init();
    await _prefs!.remove(_keyCacheSize);
    await _prefs!.remove(_keyCacheEnabled);
    await _prefs!.remove(_keyAutoPlay);
    await _prefs!.remove(_keyConnectionTimeout);
    await _prefs!.remove(_keyPlaybackTimeout);
    await _prefs!.remove(_keyVolume);
    await _prefs!.remove(_keyHardwareAcceleration);
  }
}

