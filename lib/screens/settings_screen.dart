import 'package:flutter/material.dart';
import '../services/settings_service.dart';
import '../services/playlist_storage_service.dart';
import '../services/player_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SettingsService _settingsService = SettingsService();
  final PlaylistStorageService _playlistStorageService = PlaylistStorageService();
  final PlayerService _playerService = PlayerService();
  
  bool _cacheEnabled = true;
  int _cacheSize = 64;
  bool _autoPlay = true;
  int _connectionTimeout = 15;
  int _playbackTimeout = 10;
  double _volume = 1.0;
  bool _hardwareAcceleration = true;
  
  bool _isLoading = true;
  bool _hasSavedPlaylist = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _isLoading = true;
    });
    
    await _settingsService.init();
    
    final cacheEnabled = await _settingsService.getCacheEnabled();
    final cacheSize = await _settingsService.getCacheSize();
    final autoPlay = await _settingsService.getAutoPlay();
    final connectionTimeout = await _settingsService.getConnectionTimeout();
    final playbackTimeout = await _settingsService.getPlaybackTimeout();
    final volume = await _settingsService.getVolume();
    final hardwareAcceleration = await _settingsService.getHardwareAcceleration();
    final hasSavedPlaylist = await _playlistStorageService.hasSavedPlaylist();
    
    setState(() {
      _cacheEnabled = cacheEnabled;
      _cacheSize = cacheSize;
      _autoPlay = autoPlay;
      _connectionTimeout = connectionTimeout;
      _playbackTimeout = playbackTimeout;
      _volume = volume;
      _hardwareAcceleration = hardwareAcceleration;
      _hasSavedPlaylist = hasSavedPlaylist;
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    await _settingsService.setCacheEnabled(_cacheEnabled);
    await _settingsService.setCacheSize(_cacheSize);
    await _settingsService.setAutoPlay(_autoPlay);
    await _settingsService.setConnectionTimeout(_connectionTimeout);
    await _settingsService.setPlaybackTimeout(_playbackTimeout);
    await _settingsService.setVolume(_volume);
    await _settingsService.setHardwareAcceleration(_hardwareAcceleration);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Настройки сохранены'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _resetToDefaults() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          'Сбросить настройки?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Все настройки будут сброшены к значениям по умолчанию.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Сбросить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _settingsService.resetToDefaults();
      await _loadSettings();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Настройки сброшены'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        title: const Text('Настройки'),
        backgroundColor: Colors.grey[800],
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Сбросить настройки',
            onPressed: _resetToDefaults,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Настройки кэша
                _buildSectionHeader('Кэш плеера'),
                _buildSwitchTile(
                  title: 'Включить кэш',
                  value: _cacheEnabled,
                  onChanged: (value) {
                    setState(() {
                      _cacheEnabled = value;
                    });
                    _saveSettings();
                  },
                  icon: Icons.cached,
                ),
                if (_cacheEnabled)
                  _buildSliderTile(
                    title: 'Размер кэша (МБ)',
                    value: _cacheSize.toDouble(),
                    min: 16,
                    max: 512,
                    divisions: 31,
                    label: '$_cacheSize МБ',
                    onChanged: (value) {
                      setState(() {
                        _cacheSize = value.toInt();
                      });
                      _saveSettings();
                    },
                    icon: Icons.storage,
                  ),
                
                const SizedBox(height: 16),
                
                // Настройки воспроизведения
                _buildSectionHeader('Воспроизведение'),
                _buildSwitchTile(
                  title: 'Автоматическое воспроизведение',
                  value: _autoPlay,
                  onChanged: (value) {
                    setState(() {
                      _autoPlay = value;
                    });
                    _saveSettings();
                  },
                  icon: Icons.play_arrow,
                ),
                _buildSliderTile(
                  title: 'Громкость',
                  value: _volume,
                  min: 0.0,
                  max: 1.0,
                  divisions: 100,
                  label: '${(_volume * 100).toInt()}%',
                  onChanged: (value) {
                    setState(() {
                      _volume = value;
                    });
                    _saveSettings();
                  },
                  icon: Icons.volume_up,
                ),
                
                const SizedBox(height: 16),
                
                // Настройки таймаутов
                _buildSectionHeader('Таймауты'),
                _buildSliderTile(
                  title: 'Таймаут подключения (сек)',
                  value: _connectionTimeout.toDouble(),
                  min: 5,
                  max: 60,
                  divisions: 55,
                  label: '$_connectionTimeout сек',
                  onChanged: (value) {
                    setState(() {
                      _connectionTimeout = value.toInt();
                    });
                    _saveSettings();
                  },
                  icon: Icons.timer,
                ),
                _buildSliderTile(
                  title: 'Таймаут воспроизведения (сек)',
                  value: _playbackTimeout.toDouble(),
                  min: 5,
                  max: 30,
                  divisions: 25,
                  label: '$_playbackTimeout сек',
                  onChanged: (value) {
                    setState(() {
                      _playbackTimeout = value.toInt();
                    });
                    _saveSettings();
                  },
                  icon: Icons.timer_outlined,
                ),
                
                const SizedBox(height: 16),
                
                // Дополнительные настройки
                _buildSectionHeader('Дополнительно'),
                _buildSwitchTile(
                  title: 'Аппаратное ускорение',
                  value: _hardwareAcceleration,
                  onChanged: (value) {
                    setState(() {
                      _hardwareAcceleration = value;
                    });
                    _saveSettings();
                  },
                  icon: Icons.speed,
                  subtitle: 'Улучшает производительность воспроизведения',
                ),
                
                const SizedBox(height: 16),
                
                // Управление плейлистом
                _buildSectionHeader('Плейлист'),
                if (_hasSavedPlaylist)
                  _buildActionTile(
                    title: 'Удалить сохраненный плейлист',
                    icon: Icons.delete_outline,
                    subtitle: 'Удалить локально сохраненный плейлист',
                    onTap: _deletePlaylist,
                    color: Colors.red,
                  )
                else
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[800],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.grey[400], size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Нет сохраненного плейлиста',
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 12),
      child: Text(
        title,
        style: TextStyle(
          color: Colors.grey[400],
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
    required IconData icon,
    String? subtitle,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(12),
      ),
      child: SwitchListTile(
        title: Row(
          children: [
            Icon(icon, color: Colors.grey[400], size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
        subtitle: subtitle != null
            ? Padding(
                padding: const EdgeInsets.only(left: 32, top: 4),
                child: Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 12,
                  ),
                ),
              )
            : null,
        value: value,
        onChanged: onChanged,
        activeColor: Colors.blue[400],
        inactiveThumbColor: Colors.grey[600],
        inactiveTrackColor: Colors.grey[700],
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 8,
        ),
      ),
    );
  }

  Widget _buildSliderTile({
    required String title,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String label,
    required ValueChanged<double> onChanged,
    required IconData icon,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.grey[400], size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey[700],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
            activeColor: Colors.blue[400],
            inactiveColor: Colors.grey[700],
            label: label,
          ),
        ],
      ),
    );
  }

  Future<void> _deletePlaylist() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          'Удалить плейлист?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Локально сохраненный плейлист будет удален. Это действие нельзя отменить.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Удалить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        // Останавливаем воспроизведение плеера
        await _playerService.stop();
        
        // Удаляем плейлист
        await _playlistStorageService.deleteSavedPlaylist();
        await _loadSettings(); // Обновляем состояние
        
        if (mounted) {
          // Возвращаем результат, что плейлист был удален
          Navigator.of(context).pop(true);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка удаления плейлиста: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  Widget _buildActionTile({
    required String title,
    required IconData icon,
    String? subtitle,
    required VoidCallback onTap,
    Color? color,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(
          icon,
          color: color ?? Colors.grey[400],
          size: 20,
        ),
        title: Text(
          title,
          style: TextStyle(
            color: color ?? Colors.white,
            fontSize: 15,
          ),
        ),
        subtitle: subtitle != null
            ? Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 12,
                  ),
                ),
              )
            : null,
        trailing: Icon(
          Icons.chevron_right,
          color: Colors.grey[500],
        ),
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 8,
        ),
      ),
    );
  }
}

