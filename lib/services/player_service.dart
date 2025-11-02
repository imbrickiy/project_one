import 'dart:async';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../models/iptv_channel.dart';

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
        _errorMessage = error;
        _notifyStateChanged();
      });

      _isInitialized = true;
      _notifyStateChanged();
    } catch (e) {
      _errorMessage = 'Ошибка инициализации плеера: ${e.toString()}';
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
        _errorMessage = 'Ошибка воспроизведения: ${error.toString()}';
        _notifyStateChanged();
      });
    } catch (e) {
      _errorMessage = 'Ошибка воспроизведения: ${e.toString()}';
      _notifyStateChanged();
    }
  }

  Future<void> _playChannelAsync(IptvChannel channel) async {
    try {
      // Открываем медиа с таймаутом
      await _player!.open(Media(channel.url)).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException('Таймаут открытия медиа', const Duration(seconds: 15));
        },
      );
      
      // Запускаем воспроизведение с таймаутом
      await _player!.play().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('Таймаут запуска воспроизведения', const Duration(seconds: 10));
        },
      );
      
      _notifyStateChanged();
    } catch (e) {
      _errorMessage = 'Ошибка воспроизведения: ${e.toString()}';
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

