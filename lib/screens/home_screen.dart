import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../models/iptv_channel.dart';
import '../services/m3u8_parser_service.dart';
import '../services/favorites_service.dart';
import '../services/player_service.dart';
import '../services/playlist_storage_service.dart';
import '../widgets/channel_logo.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  final M3u8ParserService _parserService = M3u8ParserService();
  final FavoritesService _favoritesService = FavoritesService();
  final PlayerService _playerService = PlayerService();
  final PlaylistStorageService _playlistStorageService = PlaylistStorageService();
  final TextEditingController _searchController = TextEditingController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  
  List<IptvChannel> _loadedChannels = [];
  List<IptvChannel> _favoriteChannels = [];
  List<IptvChannel> _filteredLoadedChannels = [];
  List<IptvChannel> _filteredFavoriteChannels = [];
  
  late TabController _tabController;
  int _selectedTabIndex = 0;
  bool _isLoading = false;
  String? _errorMessage;
  String? _loadedFileName;
  bool _isDrawerOpen = false;
  bool _showDrawerButton = false;
  bool _isMouseOverPlayer = false;
  late final ValueNotifier<bool> _drawerNotifier;
  Timer? _hideDrawerButtonTimer;
  Timer? _drawerStateCheckTimer;
  Timer? _filterDebounceTimer;
  OverlayEntry? _drawerButtonOverlay;
  OverlayEntry? _successNotificationOverlay;
  Timer? _successNotificationTimer;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  bool _overlayInitialized = false;
  // Кэш состояния избранного для оптимизации
  final Map<String, bool> _favoritesCache = {};
  bool _isFavoritesLoaded = false;
  // Состояние раскрытых групп - используем ValueNotifier для изоляции от setState
  late final ValueNotifier<Map<String, bool>> _expandedGroupsNotifier;
  // Флаг открытого экрана настроек
  bool _isSettingsOpen = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _selectedTabIndex = _tabController.index;
        });
      }
    });
    _searchController.addListener(_onSearchChanged);
    _drawerNotifier = ValueNotifier<bool>(false);
    _drawerNotifier.addListener(_onDrawerStateChanged);
    _expandedGroupsNotifier = ValueNotifier<Map<String, bool>>({});
    _startDrawerStateChecking();
    // Загружаем только избранное
    _loadFavorites();
    // Загружаем сохраненный плейлист из кэша
    _loadSavedPlaylist();
    // Слушаем изменения состояния плеера для обновления overlay
    _playerStateSubscription = _playerService.playerStateStream.listen((state) {
      if (mounted && _drawerButtonOverlay != null) {
        _drawerButtonOverlay!.markNeedsBuild();
      }
      
      final isVideoPlaying = state.isPlaying && state.currentChannel != null;
      final hasError = state.errorMessage != null || _errorMessage != null;
      
      // Если есть ошибка - всегда показываем кнопку drawer
      if (hasError) {
        if (!_showDrawerButton) {
          setState(() {
            _showDrawerButton = true;
          });
        }
        // Отменяем таймер скрытия при ошибке
        _hideDrawerButtonTimer?.cancel();
        _hideDrawerButtonTimer = null;
        if (_drawerButtonOverlay != null) {
          _drawerButtonOverlay!.markNeedsBuild();
        }
        return;
      }
      
      // Если мышь над плеером - показываем кнопку
      if (_isMouseOverPlayer && isVideoPlaying) {
        if (!_showDrawerButton) {
          setState(() {
            _showDrawerButton = true;
          });
        }
        // Отменяем таймер скрытия при наведении мыши
        _hideDrawerButtonTimer?.cancel();
        _hideDrawerButtonTimer = null;
        if (_drawerButtonOverlay != null) {
          _drawerButtonOverlay!.markNeedsBuild();
        }
        return;
      }
      
      // Автоматически показываем кнопку когда видео не играет
      if (!isVideoPlaying) {
        if (!_showDrawerButton) {
          setState(() {
            _showDrawerButton = true;
          });
        }
        // Отменяем таймер скрытия, если видео остановлено
        _hideDrawerButtonTimer?.cancel();
        _hideDrawerButtonTimer = null;
        if (_drawerButtonOverlay != null) {
          _drawerButtonOverlay!.markNeedsBuild();
        }
      } else {
        // Когда видео играет и мышь не над плеером - скрываем кнопку после короткой задержки
        _hideDrawerButtonTimer?.cancel();
        _hideDrawerButtonTimer = Timer(const Duration(seconds: 2), () {
          if (mounted && _showDrawerButton && !_isMouseOverPlayer) {
            setState(() {
              _showDrawerButton = false;
            });
            if (_drawerButtonOverlay != null) {
              _drawerButtonOverlay!.markNeedsBuild();
            }
          }
        });
      }
    });
    // Устанавливаем флаг показа кнопки по умолчанию (кнопка видна когда видео не играет)
    _showDrawerButton = true;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Добавляем overlay для кнопки drawer после готовности контекста
    if (!_overlayInitialized) {
      _overlayInitialized = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _drawerButtonOverlay == null) {
          _showDrawerButtonOverlay();
        }
      });
    }
  }

  @override
  void dispose() {
    _hideDrawerButtonTimer?.cancel();
    _filterDebounceTimer?.cancel();
    _successNotificationTimer?.cancel();
    _playerStateSubscription?.cancel();
    _drawerStateCheckTimer?.cancel();
    // Сначала удаляем overlay, чтобы ValueListenableBuilder не использовал disposed ValueNotifier
    _drawerButtonOverlay?.remove();
    _drawerButtonOverlay = null;
    _hideSuccessNotification();
    // Затем удаляем слушатели и dispose-им ValueNotifier
    _drawerNotifier.removeListener(_onDrawerStateChanged);
    _drawerNotifier.dispose();
    _expandedGroupsNotifier.dispose();
    // Восстанавливаем системный UI при закрытии
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _showDrawerButtonOverlay() {
    if (!mounted) return;
    
    // Гарантируем, что кнопка должна быть видна при создании overlay
    if (!_showDrawerButton) {
      _showDrawerButton = true;
    }
    
    if (_drawerButtonOverlay != null) {
      _drawerButtonOverlay!.remove();
      _drawerButtonOverlay = null;
    }

    final overlay = Overlay.of(context);
    if (overlay == null) {
      // Если overlay еще не готов, попробуем создать его в следующем кадре
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showDrawerButtonOverlay();
        }
      });
      return;
    }

    _drawerButtonOverlay = OverlayEntry(
      builder: (overlayContext) {
        if (!mounted) {
          return const SizedBox.shrink();
        }
        
        return StreamBuilder<PlayerState>(
          stream: _playerService.playerStateStream,
          initialData: PlayerState(
            isInitialized: false,
            isPlaying: false,
          ),
          builder: (context, snapshot) {
            if (!mounted) {
              return const SizedBox.shrink();
            }
            
            final state = snapshot.data!;
            
            // Проверяем наличие ошибок
            final hasError = state.errorMessage != null || _errorMessage != null;
            
            // Проверяем, должно ли видео скрывать кнопку
            final isVideoPlaying = state.isPlaying && state.currentChannel != null;
            final shouldHideForVideo = isVideoPlaying && !_showDrawerButton && !hasError && !_isMouseOverPlayer;
            
            return ValueListenableBuilder<bool>(
              valueListenable: _drawerNotifier,
              builder: (context, isDrawerOpen, child) {
                if (!mounted) {
                  return const SizedBox.shrink();
                }
                
                // Скрываем кнопку только в следующих случаях:
                // 1. Видео играет И временный флаг не установлен И нет ошибок И мышь не над плеером
                // 2. Drawer открыт
                // 3. Экран настроек открыт
                // При наличии ошибок или наведении мыши кнопка всегда видна
                if ((shouldHideForVideo || isDrawerOpen || _isSettingsOpen) && !hasError && !_isMouseOverPlayer) {
                  return const SizedBox.shrink();
                }
              
                return Positioned(
                  top: MediaQuery.of(overlayContext).padding.top + 8,
                  left: 8,
                  child: Material(
                    elevation: 0,
                    shadowColor: Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.transparent,
                    child: _DrawerButton(
                      onTap: () {
                        if (mounted) {
                          _scaffoldKey.currentState?.openDrawer();
                        }
                      },
                    ),
                  ),
                );
              },
            );
          },
        );
      },
      opaque: false,
    );

    overlay.insert(_drawerButtonOverlay!);
    
    // Принудительно обновляем overlay, чтобы кнопка появилась сразу
    _drawerButtonOverlay!.markNeedsBuild();
  }

  void _showDrawerButtonTemporarily() {
    setState(() {
      _showDrawerButton = true;
    });

    _hideDrawerButtonTimer?.cancel();
    _hideDrawerButtonTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() {
          _showDrawerButton = false;
        });
        // Обновляем overlay после изменения состояния
        if (_drawerButtonOverlay != null) {
          _drawerButtonOverlay!.markNeedsBuild();
        }
      }
    });
    // Обновляем overlay сразу после изменения состояния
    if (_drawerButtonOverlay != null) {
      _drawerButtonOverlay!.markNeedsBuild();
    }
  }

  void _handleDoubleTap() {
    _showDrawerButtonTemporarily();
  }

  void _onDrawerStateChanged() {
    if (_drawerButtonOverlay != null) {
      _drawerButtonOverlay!.markNeedsBuild();
    }
  }

  void _onSearchChanged() {
    // Дебаунс для фильтрации - ждем 300мс после последнего изменения
    _filterDebounceTimer?.cancel();
    _filterDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      _filterChannels();
    });
  }

  void _filterChannels() {
    final query = _searchController.text.toLowerCase().trim();
    
    // Выполняем фильтрацию в микрозадаче для неблокирующей работы
    scheduleMicrotask(() {
      if (!mounted) return;
      
      List<IptvChannel> filteredLoaded;
      List<IptvChannel> filteredFavorite;
      
      if (query.isEmpty) {
        filteredLoaded = _loadedChannels;
        filteredFavorite = _favoriteChannels;
      } else if (query.length >= 4) {
        filteredLoaded = _loadedChannels
            .where((channel) =>
                channel.name.toLowerCase().contains(query) ||
                (channel.group?.toLowerCase().contains(query) ?? false))
            .toList();
        filteredFavorite = _favoriteChannels
            .where((channel) =>
                channel.name.toLowerCase().contains(query) ||
                (channel.group?.toLowerCase().contains(query) ?? false))
            .toList();
      } else {
        filteredLoaded = [];
        filteredFavorite = [];
      }
      
      if (mounted) {
        setState(() {
          _filteredLoadedChannels = filteredLoaded;
          _filteredFavoriteChannels = filteredFavorite;
        });
      }
    });
  }

  Future<void> _loadFavorites() async {
    // Загружаем избранное в фоне
    _favoritesService.getFavorites().then((favorites) {
      if (!mounted) return;
      
      // Обновляем кэш
      _favoritesCache.clear();
      for (final fav in favorites) {
        _favoritesCache[fav.url] = true;
      }
      _isFavoritesLoaded = true;
      
      if (mounted) {
        setState(() {
          _favoriteChannels = favorites;
          _filteredFavoriteChannels = favorites;
          // Кнопка drawer должна быть видна всегда
          _showDrawerButton = true;
        });
        _filterChannels();
        // Обновляем overlay после загрузки
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _drawerButtonOverlay == null) {
            _showDrawerButtonOverlay();
          } else if (mounted && _drawerButtonOverlay != null) {
            _drawerButtonOverlay!.markNeedsBuild();
          }
        });
      }
    }).catchError((error) {
      debugPrint('Ошибка загрузки избранного: $error');
    });
  }

  Future<void> _loadSavedPlaylist() async {
    try {
      final hasSaved = await _playlistStorageService.hasSavedPlaylist();
      if (hasSaved) {
        final savedChannels = await _playlistStorageService.loadSavedPlaylist();
        if (savedChannels.isNotEmpty) {
          setState(() {
            _loadedChannels = savedChannels;
            _filteredLoadedChannels = savedChannels;
            _loadedFileName = 'Сохраненный плейлист';
            if (savedChannels.isNotEmpty || _favoriteChannels.isNotEmpty) {
              _showDrawerButton = true;
            }
          });
          _filterChannels();
          // Обновляем overlay после загрузки
          if (mounted) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _showDrawerButtonOverlay();
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Ошибка загрузки сохраненного плейлиста: $e');
    }
  }

  Future<void> _loadM3u8File() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['m3u', 'm3u8'],
        dialogTitle: 'Выберите файл m3u8',
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        _loadedFileName = result.files.single.name;
        
        final channels = await _parserService.parseM3u8File(file);
        
        // Сохраняем плейлист локально
        try {
          await _playlistStorageService.savePlaylist(channels);
        } catch (e) {
          // Не прерываем загрузку, если сохранение не удалось
          debugPrint('Ошибка сохранения плейлиста: $e');
        }
        
        setState(() {
          _loadedChannels = channels;
          _filteredLoadedChannels = channels;
          _isLoading = false;
          // Показываем кнопку drawer при загрузке файла
          if (channels.isNotEmpty || _favoriteChannels.isNotEmpty) {
            _showDrawerButton = true;
          }
        });

        _filterChannels();
        
        // Обновляем overlay после загрузки
        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showDrawerButtonOverlay();
          });
        }

        if (channels.isEmpty) {
          setState(() {
            _errorMessage = 'В файле не найдено каналов';
            _showDrawerButton = true; // Показываем кнопку drawer при ошибке
          });
          if (_drawerButtonOverlay != null) {
            _drawerButtonOverlay!.markNeedsBuild();
          }
        } else if (mounted) {
          // Показываем pop-up уведомление об успешной загрузке
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _showSuccessNotification(channels.length);
            }
          });
        }
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Ошибка: ${e.toString()}';
        _showDrawerButton = true; // Показываем кнопку drawer при ошибке
      });
      if (_drawerButtonOverlay != null) {
        _drawerButtonOverlay!.markNeedsBuild();
      }
    }
  }

  Future<void> _toggleFavorite(IptvChannel channel) async {
    // Обновляем UI сразу для лучшего UX
    final currentIsFavorite = _favoritesCache[channel.url] ?? false;
    final newIsFavorite = !currentIsFavorite;
    
    // Оптимистичное обновление UI
    setState(() {
      _favoritesCache[channel.url] = newIsFavorite;
    });
    
    // Выполняем операцию в фоне
    Future.microtask(() async {
      try {
        if (newIsFavorite) {
          await _favoritesService.addFavorite(channel);
        } else {
          await _favoritesService.removeFavorite(channel);
        }
        
        // Обновляем список избранного в фоне
        _loadFavorites();
      } catch (e) {
        // Откатываем изменение при ошибке
        if (mounted) {
          setState(() {
            _favoritesCache[channel.url] = currentIsFavorite;
          });
        }
        debugPrint('Ошибка изменения избранного: $e');
      }
    });
  }

  Future<void> _selectChannel(IptvChannel channel) async {
    // Закрываем drawer сразу, не дожидаясь загрузки канала
    if (mounted) {
      Navigator.of(context).pop();
    }
    
    // Запускаем воспроизведение в фоне
    _playerService.playChannel(channel).catchError((error) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Ошибка воспроизведения: ${error.toString()}';
          _showDrawerButton = true; // Показываем кнопку drawer при ошибке
        });
        if (_drawerButtonOverlay != null) {
          _drawerButtonOverlay!.markNeedsBuild();
        }
      }
    });
  }

  Widget _buildChannelItem(IptvChannel channel, bool isSelected) {
    // Используем кэш вместо FutureBuilder для избежания блокировки
    final isFavorite = _favoritesCache[channel.url] ?? false;
    
    // Если кэш не загружен, загружаем асинхронно без setState
    if (!_isFavoritesLoaded && !_favoritesCache.containsKey(channel.url)) {
      _favoritesService.isFavorite(channel).then((value) {
        if (mounted) {
          // Обновляем кэш без setState, чтобы не перестраивать весь список
          _favoritesCache[channel.url] = value;
        }
      });
    }
    
    return RepaintBoundary(
      key: ValueKey(channel.url), // Уникальный ключ для каждого элемента
      child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected ? Colors.grey[700] : Colors.grey[800],
            borderRadius: BorderRadius.circular(8),
            border: isSelected
                ? Border.all(color: Colors.blue, width: 2)
                : null,
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 4,
            ),
            leading: ChannelLogo(
              logoUrl: channel.logo,
              width: 48,
              height: 48,
            ),
            title: Text(
              channel.name,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.grey[200],
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    isFavorite ? Icons.star : Icons.star_border,
                    color: isFavorite ? Colors.amber : Colors.grey[500],
                    size: 22,
                  ),
                  onPressed: () => _toggleFavorite(channel),
                  tooltip: isFavorite ? 'Удалить из избранного' : 'Добавить в избранное',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.play_circle_filled,
                  color: isSelected ? Colors.blue : Colors.grey[500],
                  size: 24,
                ),
              ],
            ),
            onTap: () => _selectChannel(channel),
          ),
        ),
    );
  }


  Widget _buildChannelList() {
    final query = _searchController.text.trim();
    final channels = _selectedTabIndex == 0
        ? _filteredLoadedChannels
        : _filteredFavoriteChannels;
    
    if (query.isNotEmpty && query.length < 4) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.search,
                size: 48,
                color: Colors.grey[500],
              ),
              const SizedBox(height: 16),
              Text(
                'Введите минимум 4 символа\nдля поиска каналов',
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    
    if (channels.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _selectedTabIndex == 0 ? Icons.tv_off : Icons.star_border,
                size: 48,
                color: Colors.grey[500],
              ),
              const SizedBox(height: 16),
              Text(
                _selectedTabIndex == 0
                    ? (query.length >= 4 
                        ? 'Каналы не найдены'
                        : 'Загрузите файл m3u8\nдля просмотра каналов')
                    : (query.length >= 4
                        ? 'Избранные каналы не найдены'
                        : 'Нет избранных каналов'),
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // Группируем каналы по группам
    return StreamBuilder<PlayerState>(
      stream: _playerService.playerStateStream,
      builder: (context, snapshot) {
        final currentChannel = snapshot.data?.currentChannel;
        
        // Префикс для ключей групп в зависимости от вкладки
        final tabPrefix = _selectedTabIndex == 0 ? 'loaded_' : 'favorite_';
        
        // Группируем каналы по группам
        final Map<String, List<IptvChannel>> groupedChannels = {};
        final List<IptvChannel> ungroupedChannels = [];
        
        for (final channel in channels) {
          if (channel.group != null && channel.group!.isNotEmpty) {
            final groupKey = channel.group!;
            if (!groupedChannels.containsKey(groupKey)) {
              groupedChannels[groupKey] = [];
              // По умолчанию все группы раскрыты
              final expandedKey = '$tabPrefix$groupKey';
              if (!_expandedGroupsNotifier.value.containsKey(expandedKey)) {
                _expandedGroupsNotifier.value = {
                  ..._expandedGroupsNotifier.value,
                  expandedKey: true,
                };
              }
            }
            groupedChannels[groupKey]!.add(channel);
          } else {
            ungroupedChannels.add(channel);
          }
        }
        
        // Сортируем группы по алфавиту
        final sortedGroups = groupedChannels.keys.toList()..sort();
        final hasGroups = sortedGroups.isNotEmpty;
        
        // Если нет групп, показываем простой список
        if (!hasGroups && ungroupedChannels.isNotEmpty) {
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            cacheExtent: 500, // Увеличиваем кэш для плавной прокрутки
            addAutomaticKeepAlives: true, // Сохраняем состояние элементов
            addRepaintBoundaries: true, // Изолируем перерисовки
            itemCount: ungroupedChannels.length,
            itemBuilder: (context, index) {
              final channel = ungroupedChannels[index];
              final isSelected = currentChannel?.url == channel.url;
              return _buildChannelItem(channel, isSelected);
            },
          );
        }
        
        // Инициализируем состояние для группы "Без группы"
        final ungroupedKey = '${tabPrefix}ungrouped';
        if (ungroupedChannels.isNotEmpty && !_expandedGroupsNotifier.value.containsKey(ungroupedKey)) {
          _expandedGroupsNotifier.value = {
            ..._expandedGroupsNotifier.value,
            ungroupedKey: true,
          };
        }
        
        // Создаем список виджетов для групп - используем ValueListenableBuilder для изоляции перестроек
        return ValueListenableBuilder<Map<String, bool>>(
          valueListenable: _expandedGroupsNotifier,
          builder: (context, expandedGroups, child) {
            return ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              cacheExtent: 500, // Увеличиваем кэш для плавной прокрутки
              addAutomaticKeepAlives: true, // Сохраняем состояние элементов
              addRepaintBoundaries: true, // Изолируем перерисовки
              itemCount: sortedGroups.length + (ungroupedChannels.isNotEmpty ? 1 : 0),
              itemBuilder: (context, index) {
                // Обрабатываем группы с каналами
                if (index < sortedGroups.length) {
                  final groupName = sortedGroups[index];
                  final groupChannels = groupedChannels[groupName]!;
                  final expandedKey = '$tabPrefix$groupName';
                  
                  return ExpansionTile(
                    key: ValueKey('${tabPrefix}group_$groupName'),
                    initiallyExpanded: expandedGroups[expandedKey] ?? true,
                    maintainState: false,
                    onExpansionChanged: (expanded) {
                      // Обновляем состояние через ValueNotifier без setState
                      _expandedGroupsNotifier.value = {
                        ..._expandedGroupsNotifier.value,
                        expandedKey: expanded,
                      };
                    },
                    title: Row(
                      children: [
                        Icon(
                          Icons.folder,
                          color: Colors.grey[400],
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            groupName,
                            style: TextStyle(
                              color: Colors.grey[300],
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey[700],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${groupChannels.length}',
                            style: TextStyle(
                              color: Colors.grey[300],
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    iconColor: Colors.grey[400],
                    collapsedIconColor: Colors.grey[500],
                    backgroundColor: Colors.grey[850],
                    collapsedBackgroundColor: Colors.grey[850],
                    childrenPadding: const EdgeInsets.only(left: 16),
                    children: [
                      // Используем ListView.builder внутри для виртуализации больших групп
                      if (groupChannels.length > 50)
                        SizedBox(
                          height: (groupChannels.length * 64.0).clamp(0.0, 2000.0), // Ограничиваем высоту
                          child: ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            cacheExtent: 200,
                            addRepaintBoundaries: true,
                            itemCount: groupChannels.length,
                            itemBuilder: (context, idx) {
                              final channel = groupChannels[idx];
                              final isSelected = currentChannel?.url == channel.url;
                              return _buildChannelItem(channel, isSelected);
                            },
                          ),
                        )
                      else
                        ...groupChannels.map((channel) {
                          final isSelected = currentChannel?.url == channel.url;
                          return _buildChannelItem(channel, isSelected);
                        }).toList(),
                    ],
                  );
                }
                
                // Обрабатываем каналы без группы
                if (ungroupedChannels.isNotEmpty) {
                  final ungroupedKey = '${tabPrefix}ungrouped';
                  return ExpansionTile(
                    key: ValueKey('${tabPrefix}ungrouped'),
                    initiallyExpanded: expandedGroups[ungroupedKey] ?? true,
                    maintainState: false,
                    onExpansionChanged: (expanded) {
                      // Обновляем состояние через ValueNotifier без setState
                      _expandedGroupsNotifier.value = {
                        ..._expandedGroupsNotifier.value,
                        ungroupedKey: expanded,
                      };
                    },
                    title: Row(
                      children: [
                        Icon(
                          Icons.folder_outlined,
                          color: Colors.grey[400],
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Без группы',
                            style: TextStyle(
                              color: Colors.grey[300],
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey[700],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${ungroupedChannels.length}',
                            style: TextStyle(
                              color: Colors.grey[300],
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    iconColor: Colors.grey[400],
                    collapsedIconColor: Colors.grey[500],
                    backgroundColor: Colors.grey[850],
                    collapsedBackgroundColor: Colors.grey[850],
                    childrenPadding: const EdgeInsets.only(left: 16),
                    children: [
                      // Используем ListView.builder внутри для виртуализации больших групп
                      if (ungroupedChannels.length > 50)
                        SizedBox(
                          height: (ungroupedChannels.length * 64.0).clamp(0.0, 2000.0), // Ограничиваем высоту
                          child: ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            cacheExtent: 200,
                            addRepaintBoundaries: true,
                            itemCount: ungroupedChannels.length,
                            itemBuilder: (context, idx) {
                              final channel = ungroupedChannels[idx];
                              final isSelected = currentChannel?.url == channel.url;
                              return _buildChannelItem(channel, isSelected);
                            },
                          ),
                        )
                      else
                        ...ungroupedChannels.map((channel) {
                          final isSelected = currentChannel?.url == channel.url;
                          return _buildChannelItem(channel, isSelected);
                        }).toList(),
                    ],
                  );
                }
                
                return const SizedBox.shrink();
              },
            );
          },
        );
      },
    );
  }


  Widget _buildVideoPlayer() {
    return MouseRegion(
      onEnter: (_) {
        if (mounted) {
          setState(() {
            _isMouseOverPlayer = true;
          });
          // Показываем кнопку drawer при наведении
          if (!_showDrawerButton) {
            setState(() {
              _showDrawerButton = true;
            });
          }
          // Отменяем таймер скрытия
          _hideDrawerButtonTimer?.cancel();
          _hideDrawerButtonTimer = null;
          // Обновляем overlay
          if (_drawerButtonOverlay != null) {
            _drawerButtonOverlay!.markNeedsBuild();
          }
        }
      },
      onExit: (_) {
        if (mounted) {
          setState(() {
            _isMouseOverPlayer = false;
          });
          // Обновляем overlay
          if (_drawerButtonOverlay != null) {
            _drawerButtonOverlay!.markNeedsBuild();
          }
          // Если видео играет и нет ошибок - скрываем кнопку через задержку
          final hasError = _playerService.errorMessage != null || _errorMessage != null;
          final isVideoPlaying = _playerService.isPlaying && _playerService.currentChannel != null;
          
          if (isVideoPlaying && !hasError) {
            _hideDrawerButtonTimer?.cancel();
            _hideDrawerButtonTimer = Timer(const Duration(seconds: 2), () {
              if (mounted && !_isMouseOverPlayer && _showDrawerButton) {
                setState(() {
                  _showDrawerButton = false;
                });
                if (_drawerButtonOverlay != null) {
                  _drawerButtonOverlay!.markNeedsBuild();
                }
              }
            });
          }
        }
      },
      child: StreamBuilder<PlayerState>(
        stream: _playerService.playerStateStream,
        initialData: PlayerState(
          isInitialized: false,
          isPlaying: false,
        ),
        builder: (context, snapshot) {
          final state = snapshot.data!;
          final videoController = _playerService.videoController;
          final currentChannel = state.currentChannel;


          // Показываем loader только если есть текущий канал, но плеер не инициализирован
          if (currentChannel != null && (!state.isInitialized || videoController == null)) {
            return Container(
              color: Colors.black,
              child: const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            );
          }

          if (state.errorMessage != null && currentChannel != null) {
            return Container(
              color: Colors.black,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Colors.red[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        state.errorMessage!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.red[300],
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          if (currentChannel == null) {
            return Container(
              color: Colors.black,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.play_circle_outline,
                      size: 80,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Выберите канал для воспроизведения',
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          // Проверяем что videoController не null перед использованием
          if (videoController == null) {
            return Container(
              color: Colors.black,
              child: const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            );
          }

          // Только Video виджет с родными контролами, без кастомных оверлеев
          // RepaintBoundary оптимизирует перерисовки при движении ползунка
          // Key предотвращает перестройку при изменениях состояния других виджетов
          return RepaintBoundary(
            key: const ValueKey('video_player'),
            child: GestureDetector(
              onDoubleTap: _handleDoubleTap,
              child: Video(
                controller: videoController!,
                fill: Colors.black,
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _clearPlaylist() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          'Очистить плейлист?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Это действие удалит все загруженные каналы из памяти. Продолжить?',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Очистить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() {
        _loadedChannels = [];
        _filteredLoadedChannels = [];
        _loadedFileName = null;
      });
      _filterChannels();
      Navigator.of(context).pop(); // Закрываем drawer
      // Пересоздаем overlay после закрытия drawer
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showDrawerButtonOverlay();
        }
      });
    }
  }

  void _showSuccessNotification(int channelCount) {
    if (!mounted) return;
    
    // Закрываем предыдущее уведомление, если оно есть
    _hideSuccessNotification();
    
    // Создаем overlay entry для уведомления
    _successNotificationOverlay = OverlayEntry(
      builder: (context) => Positioned(
        top: 50,
        left: 16,
        right: 16,
        child: Material(
          color: Colors.transparent,
          child: TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 300),
            tween: Tween(begin: 0.0, end: 1.0),
            builder: (context, value, child) {
              return Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, 20 * (1 - value)),
                  child: child,
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.green[700],
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle,
                    color: Colors.white,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Плейлист загружен успешно\n$channelCount ${_getChannelWord(channelCount)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    
    // Добавляем overlay в контекст
    final overlay = Overlay.of(context);
    if (overlay != null) {
      overlay.insert(_successNotificationOverlay!);
      
      // Убираем уведомление через 5 секунд
      _successNotificationTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) {
          _hideSuccessNotification();
        }
      });
    }
  }
  
  String _getChannelWord(int count) {
    final lastDigit = count % 10;
    final lastTwoDigits = count % 100;
    
    if (lastTwoDigits >= 11 && lastTwoDigits <= 14) {
      return 'каналов';
    }
    
    if (lastDigit == 1) {
      return 'канал';
    } else if (lastDigit >= 2 && lastDigit <= 4) {
      return 'канала';
    } else {
      return 'каналов';
    }
  }
  
  void _hideSuccessNotification() {
    if (_successNotificationOverlay != null) {
      _successNotificationOverlay!.remove();
      _successNotificationOverlay = null;
    }
    if (_successNotificationTimer != null) {
      _successNotificationTimer!.cancel();
      _successNotificationTimer = null;
    }
  }

  void _openSettings(BuildContext context) {
    Navigator.of(context).pop(); // Закрываем drawer
    // Открываем экран настроек с именем маршрута для отслеживания
    setState(() {
      _isSettingsOpen = true;
    });
    // Обновляем overlay сразу, чтобы скрыть кнопку
    if (_drawerButtonOverlay != null) {
      _drawerButtonOverlay!.markNeedsBuild();
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: '/settings'),
        builder: (context) => const SettingsScreen(),
      ),
    ).then((result) {
      // Обновляем флаг и overlay после закрытия настроек
      if (mounted) {
        setState(() {
          _isSettingsOpen = false;
        });
        
        // Если плейлист был удален - очищаем drawer
        if (result == true) {
          setState(() {
            _loadedChannels = [];
            _filteredLoadedChannels = [];
            _loadedFileName = null;
          });
          _filterChannels();
          
          // Показываем уведомление об удалении плейлиста
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Плейлист удален'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
        
        if (_drawerButtonOverlay != null) {
          _drawerButtonOverlay!.markNeedsBuild();
        }
      }
    });
    // Пересоздаем overlay после закрытия drawer
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _showDrawerButtonOverlay();
      }
    });
  }

  void _startDrawerStateChecking() {
    _drawerStateCheckTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final scaffoldState = _scaffoldKey.currentState;
      if (scaffoldState != null) {
        final isDrawerOpen = scaffoldState.isDrawerOpen;
        if (_isDrawerOpen != isDrawerOpen) {
          setState(() {
            _isDrawerOpen = isDrawerOpen;
          });
          _drawerNotifier.value = isDrawerOpen;
        }
      }
    });
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: Colors.grey[900],
      width: 350,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[800],
                border: Border(
                  bottom: BorderSide(
                    color: Colors.grey[700]!,
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.tv,
                    color: Colors.blue[400],
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'IPTV Плеер',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Поиск (мин. 4 символа)...',
                  hintStyle: TextStyle(color: Colors.grey[500]),
                  prefixIcon: Icon(Icons.search, color: Colors.grey[500]),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear, color: Colors.grey[500], size: 20),
                          onPressed: () {
                            _searchController.clear();
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.grey[800],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                style: TextStyle(color: Colors.grey[200], fontSize: 14),
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                controller: _tabController,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.grey[500],
                indicatorColor: Colors.blue[400],
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.grey[700],
                ),
                dividerColor: Colors.transparent,
                onTap: (index) {
                  setState(() {
                    _selectedTabIndex = index;
                  });
                },
                tabs: const [
                  Tab(
                    icon: Icon(Icons.list, size: 20),
                    text: 'Загружено',
                  ),
                  Tab(
                    icon: Icon(Icons.star, size: 20),
                    text: 'Избранное',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (_loadedChannels.isNotEmpty || _favoriteChannels.isNotEmpty)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[800],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      _selectedTabIndex == 0 ? Icons.info_outline : Icons.star,
                      color: _selectedTabIndex == 0 ? Colors.blue[400] : Colors.amber,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _selectedTabIndex == 0
                          ? 'Каналов: ${_loadedChannels.length}'
                          : 'Избранных: ${_favoriteChannels.length}',
                      style: TextStyle(
                        color: Colors.grey[300],
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: _buildChannelList(),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[800],
                border: Border(
                  top: BorderSide(
                    color: Colors.grey[700]!,
                    width: 1,
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _loadM3u8File,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(Icons.folder_open, size: 20),
                      label: Text(
                        _isLoading ? 'Загрузка...' : 'Загрузить m3u8',
                        style: const TextStyle(fontSize: 14),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[600],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _openSettings(context),
                      icon: const Icon(Icons.settings, size: 20),
                      label: const Text(
                        'Настройки',
                        style: TextStyle(fontSize: 14),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey[300],
                        side: BorderSide(color: Colors.grey[600]!),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Гарантируем создание overlay при первом build
    if (!_overlayInitialized && _drawerButtonOverlay == null) {
      _overlayInitialized = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _drawerButtonOverlay == null) {
          _showDrawerButtonOverlay();
        }
      });
    }
    
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.black,
      drawer: _buildDrawer(),
      body: Stack(
        children: [
          _buildVideoPlayer(),
          SafeArea(
            child: Column(
              children: [
                if (_errorMessage != null)
                  Container(
                    margin: const EdgeInsets.all(12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red[900]?.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.red[700]!,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: Colors.red[400],
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(
                              color: Colors.red[300],
                              fontSize: 12,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          color: Colors.red[300],
                          onPressed: () {
                            setState(() {
                              _errorMessage = null;
                            });
                            // Обновляем overlay после закрытия ошибки
                            if (_drawerButtonOverlay != null) {
                              _drawerButtonOverlay!.markNeedsBuild();
                            }
                          },
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          // Кнопка drawer отображается через Overlay API и скрывается при воспроизведении видео
        ],
      ),
    );
  }
}

class _DrawerButton extends StatefulWidget {
  final VoidCallback onTap;

  const _DrawerButton({
    required this.onTap,
  });

  @override
  State<_DrawerButton> createState() => _DrawerButtonState();
}

class _DrawerButtonState extends State<_DrawerButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(_isHovered ? 0.85 : 0.7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withOpacity(_isHovered ? 0.3 : 0.15),
            width: _isHovered ? 2 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(_isHovered ? 0.5 : 0.3),
              blurRadius: _isHovered ? 12 : 8,
              offset: Offset(0, _isHovered ? 3 : 2),
            ),
          ],
        ),
        transform: Matrix4.identity()..scale(_isHovered ? 1.05 : 1.0),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(12),
            splashColor: Colors.white.withOpacity(0.1),
            highlightColor: Colors.white.withOpacity(0.05),
            child: Container(
              padding: const EdgeInsets.all(14),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  Icons.menu_rounded,
                  key: ValueKey(_isHovered),
                  color: Colors.white,
                  size: _isHovered ? 28 : 26,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
