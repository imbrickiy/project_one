import 'dart:async';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../models/iptv_channel.dart';
import 'settings_service.dart';

class PlayerService {
  static final PlayerService _instance = PlayerService._internal();
  factory PlayerService() => _instance;
  PlayerService._internal() {
    // Отправляем начальное состояние сразу
    _notifyStateChanged();
    // Инициализируем плеер асинхронно
    _initializePlayer();
  }

  Player? _player;
  VideoController? _videoController;
  IptvChannel? _currentChannel;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<Playlist>? _playlistSubscription;
  
  final _playerStateController = StreamController<PlayerState>.broadcast();
  Stream<PlayerState> get playerStateStream => _playerStateController.stream;
  
  final SettingsService _settingsService = SettingsService();
  
  bool _isInitialized = false;
  bool _isPlaying = false;
  String? _errorMessage;

  Player? get player => _player;
  VideoController? get videoController => _videoController;
  IptvChannel? get currentChannel => _currentChannel;
  bool get isPlaying => _isPlaying;
  bool get isInitialized => _isInitialized;
  String? get errorMessage => _errorMessage;

  Future<void> _initializePlayer() async {
    try {
      await _settingsService.init();
      
      // Инициализируем плеер
      // Настройки кэша и другие параметры применяются динамически при воспроизведении
      _player = Player();
      _videoController = VideoController(_player!);

      _playingSubscription = _player!.stream.playing.listen((playing) {
        _isPlaying = playing;
        _notifyStateChanged();
      });

      _playlistSubscription = _player!.stream.playlist.listen((playlist) {
        _notifyStateChanged();
      });

      _player!.stream.error.listen((error) {
        _errorMessage = _formatErrorMessage(error);
        _notifyStateChanged();
      });

      _isInitialized = true;
      _notifyStateChanged();
    } catch (e) {
      _errorMessage = _formatErrorMessage('Ошибка инициализации плеера: ${e.toString()}');
      _isInitialized = true;
      _notifyStateChanged();
    }
  }

  Future<void> playChannel(IptvChannel channel) async {
    if (_currentChannel?.url == channel.url && _isPlaying) {
      return;
    }

    // Проверяем что плеер инициализирован
    if (_player == null || !_isInitialized) {
      _errorMessage = 'Плеер не инициализирован';
      _notifyStateChanged();
      // Ждем инициализации максимум 5 секунд
      var waitCount = 0;
      while ((_player == null || !_isInitialized) && waitCount < 50) {
        await Future.delayed(const Duration(milliseconds: 100));
        waitCount++;
      }
      if (_player == null || !_isInitialized) {
        _errorMessage = 'Таймаут инициализации плеера';
        _notifyStateChanged();
        return;
      }
    }

    try {
      _errorMessage = null;
      _currentChannel = channel;
      _notifyStateChanged();
      
      // Выполняем открытие и воспроизведение в фоне без блокировки UI
      _playChannelAsync(channel).catchError((error) {
        _errorMessage = _formatErrorMessage(error.toString());
        _notifyStateChanged();
      });
    } catch (e) {
      _errorMessage = _formatErrorMessage(e.toString());
      _notifyStateChanged();
    }
  }

  Future<void> _playChannelAsync(IptvChannel channel) async {
    try {
      // Получаем настройки таймаутов
      final connectionTimeout = await _settingsService.getConnectionTimeout();
      final playbackTimeout = await _settingsService.getPlaybackTimeout();
      final autoPlay = await _settingsService.getAutoPlay();
      final volume = await _settingsService.getVolume();
      
      // Устанавливаем громкость
      await _player?.setVolume(volume);
      
      // Открываем медиа с таймаутом из настроек
      await _player!.open(Media(channel.url)).timeout(
        Duration(seconds: connectionTimeout),
        onTimeout: () {
          throw TimeoutException('Таймаут открытия медиа', Duration(seconds: connectionTimeout));
        },
      );
      
      // Запускаем воспроизведение с таймаутом из настроек (если авто-воспроизведение включено)
      if (autoPlay) {
        await _player!.play().timeout(
          Duration(seconds: playbackTimeout),
          onTimeout: () {
            throw TimeoutException('Таймаут запуска воспроизведения', Duration(seconds: playbackTimeout));
          },
        );
      }
      
      _notifyStateChanged();
    } catch (e) {
      _errorMessage = _formatErrorMessage(e.toString());
      _notifyStateChanged();
    }
  }

  Future<void> pause() async {
    await _player?.pause();
  }

  Future<void> resume() async {
    await _player?.play();
  }

  void togglePlayPause() {
    if (_isPlaying) {
      pause();
    } else {
      resume();
    }
  }

  /// Останавливает воспроизведение и очищает текущий канал
  Future<void> stop() async {
    try {
      await _player?.pause();
      await _player?.stop();
      _currentChannel = null;
      _errorMessage = null;
      _notifyStateChanged();
    } catch (e) {
      _errorMessage = _formatErrorMessage('Ошибка остановки плеера: ${e.toString()}');
      _notifyStateChanged();
    }
  }

  String _formatErrorMessage(String error) {
    // Преобразуем технические ошибки в понятные сообщения
    final errorLower = error.toLowerCase();
    
    // Ошибки подключения к недоступному каналу
    if (errorLower.contains('ffurl_read') || 
        errorLower.contains('0xffffff76') ||
        errorLower.contains('connection refused') ||
        errorLower.contains('connection reset') ||
        errorLower.contains('connection timed out')) {
      return 'Не удалось подключиться к каналу. Канал может быть недоступен или перегружен.';
    }
    
    // Ошибки таймаута
    if (errorLower.contains('timeout') || errorLower.contains('timed out')) {
      return 'Превышено время ожидания подключения к каналу.';
    }
    
    // Ошибки HTTP
    if (errorLower.contains('http') && (errorLower.contains('404') || errorLower.contains('not found'))) {
      return 'Канал не найден (404). URL может быть неверным или канал удален.';
    }
    if (errorLower.contains('http') && errorLower.contains('403')) {
      return 'Доступ к каналу запрещен (403).';
    }
    if (errorLower.contains('http') && errorLower.contains('500')) {
      return 'Ошибка сервера канала (500).';
    }
    
    // Ошибки формата
    if (errorLower.contains('format') || errorLower.contains('codec') || errorLower.contains('unsupported')) {
      return 'Формат потока не поддерживается или поврежден.';
    }
    
    // Ошибки сети
    if (errorLower.contains('network') || errorLower.contains('host') || errorLower.contains('unreachable')) {
      return 'Ошибка сети. Проверьте подключение к интернету.';
    }
    
    // Ошибки DNS
    if (errorLower.contains('dns') || errorLower.contains('name resolution')) {
      return 'Не удалось найти сервер канала. Проверьте URL.';
    }
    
    // Общие ошибки TCP/IP
    if (errorLower.contains('tcp') || errorLower.contains('socket')) {
      return 'Ошибка подключения к каналу. Канал недоступен или URL неверный.';
    }
    
    // Если не удалось определить тип ошибки, возвращаем общее сообщение
    // но не показываем технические детали пользователю
    if (error.length > 100 || error.contains('0x') || error.contains('ffmpeg') || error.contains('libav')) {
      return 'Ошибка воспроизведения канала. Канал может быть недоступен или поток поврежден.';
    }
    
    // Для коротких ошибок возвращаем как есть
    return error;
  }

  void _notifyStateChanged() {
    _playerStateController.add(PlayerState(
      isInitialized: _isInitialized,
      isPlaying: _isPlaying,
      currentChannel: _currentChannel,
      errorMessage: _errorMessage,
    ));
  }

  void dispose() {
    _playingSubscription?.cancel();
    _playlistSubscription?.cancel();
    _player?.dispose();
    _videoController = null;
    _playerStateController.close();
  }
}

class PlayerState {
  final bool isInitialized;
  final bool isPlaying;
  final IptvChannel? currentChannel;
  final String? errorMessage;

  PlayerState({
    required this.isInitialized,
    required this.isPlaying,
    this.currentChannel,
    this.errorMessage,
  });
}

