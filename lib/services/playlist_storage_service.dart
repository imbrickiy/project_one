import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import '../models/iptv_channel.dart';

class PlaylistStorageService {
  static const String _playlistFileName = 'saved_playlist.m3u8';
  static const String _channelsFileName = 'saved_channels.json';

  /// Получает директорию для сохранения файлов приложения
  Future<Directory> _getAppDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    return appDir;
  }

  /// Сохраняет плейлист в файл m3u8
  Future<void> savePlaylist(List<IptvChannel> channels) async {
    try {
      final appDir = await _getAppDirectory();
      final playlistFile = File('${appDir.path}/$_playlistFileName');
      
      final buffer = StringBuffer();
      buffer.writeln('#EXTM3U');
      
      for (final channel in channels) {
        // Формируем строку #EXTINF с метаданными
        final attributes = <String>[];
        
        if (channel.group != null) {
          attributes.add('group-title="${channel.group}"');
        }
        
        if (channel.logo != null && channel.logo!.isNotEmpty) {
          attributes.add('tvg-logo="${channel.logo}"');
        }
        
        // Добавляем другие атрибуты
        if (channel.attributes != null) {
          for (final entry in channel.attributes!.entries) {
            if (entry.key != 'group-title' && entry.key != 'tvg-logo') {
              attributes.add('${entry.key}="${entry.value}"');
            }
          }
        }
        
        final attrString = attributes.isNotEmpty ? ' ' + attributes.join(' ') : '';
        buffer.writeln('#EXTINF:-1$attrString,${channel.name}');
        buffer.writeln(channel.url);
      }
      
      await playlistFile.writeAsString(buffer.toString(), encoding: utf8);
      
      // Также сохраняем в JSON для быстрой загрузки
      await saveChannelsJson(channels);
    } catch (e) {
      throw Exception('Ошибка сохранения плейлиста: $e');
    }
  }

  /// Сохраняет каналы в JSON формате
  Future<void> saveChannelsJson(List<IptvChannel> channels) async {
    try {
      final appDir = await _getAppDirectory();
      final jsonFile = File('${appDir.path}/$_channelsFileName');
      
      final jsonData = channels.map((channel) => channel.toJson()).toList();
      await jsonFile.writeAsString(jsonEncode(jsonData), encoding: utf8);
    } catch (e) {
      throw Exception('Ошибка сохранения каналов: $e');
    }
  }

  /// Загружает сохраненный плейлист из файла m3u8
  Future<List<IptvChannel>> loadSavedPlaylist() async {
    try {
      final appDir = await _getAppDirectory();
      final playlistFile = File('${appDir.path}/$_playlistFileName');
      
      if (!await playlistFile.exists()) {
        return [];
      }
      
      final content = await playlistFile.readAsString(encoding: utf8);
      final lines = content.split('\n');

      final List<IptvChannel> channels = [];
      String? channelName;
      String? channelUrl;
      String? logo;
      String? group;
      String? extgrpGroup; // Группа из #EXTGRP - сохраняется между каналами
      Map<String, String> attributes = {};

      for (int i = 0; i < lines.length; i++) {
final line = lines[i].trim();

        if (line.startsWith('#EXTGRP:')) {
          // Извлекаем группу из #EXTGRP:
          final extgrpContent = line.substring(8).trim(); // Убираем #EXTGRP:
          extgrpGroup = extgrpContent.isNotEmpty ? extgrpContent : null;
        } else if (line.startsWith('#EXTGRP ')) {
          // Извлекаем группу из #EXTGRP (без двоеточия)
          final extgrpContent = line.substring(7).trim(); // Убираем #EXTGRP 
          extgrpGroup = extgrpContent.isNotEmpty ? extgrpContent : null;
        } else if (line.startsWith('#EXTINF:')) {
          final info = line.substring(8);
          
          // Извлекаем группу из group-title=""
          final groupMatch = RegExp(r'group-title="([^"]+)"').firstMatch(info);
          // Если group-title есть в EXTINF, используем его, иначе используем группу из #EXTGRP
          group = groupMatch?.group(1) ?? extgrpGroup;

          // Извлекаем логотип - поддерживаем разные варианты формата
          var logoMatch = RegExp(r'tvg-logo="([^"]+)"').firstMatch(info);
          if (logoMatch == null) {
            logoMatch = RegExp(r'tvg-logo=([^\s,]+)').firstMatch(info);
          }
          if (logoMatch == null) {
            logoMatch = RegExp(r'logo="([^"]+)"').firstMatch(info);
          }
          if (logoMatch == null) {
            logoMatch = RegExp(r'logo=([^\s,]+)').firstMatch(info);
          }
          logo = logoMatch?.group(1);
          
          // Очищаем URL логотипа от лишних символов
          if (logo != null) {
            logo = logo.trim();
            if (logo.startsWith('"') && logo.endsWith('"')) {
              logo = logo.substring(1, logo.length - 1);
            }
          }

          final attributesMatch = RegExp(r'(\w+)="([^"]+)"').allMatches(info);
          for (final match in attributesMatch) {
            attributes[match.group(1)!] = match.group(2)!;
          }

          final nameMatch = RegExp(r',(.+)$').firstMatch(info);
          channelName = nameMatch?.group(1)?.trim() ?? 'Без названия';
        } else if (line.isNotEmpty && 
                   !line.startsWith('#') && 
                   channelName != null) {
          channelUrl = line;
          
          // Если группа не была определена в #EXTINF, используем группу из #EXTGRP
          if (group == null && extgrpGroup != null) {
            group = extgrpGroup;
          }
          
          channels.add(IptvChannel.fromM3u(
            name: channelName,
            url: channelUrl,
            logo: logo,
            group: group,
            attributes: attributes.isNotEmpty ? attributes : null,
          ));

          channelName = null;
          channelUrl = null;
          logo = null;
          group = null;
          // НЕ сбрасываем extgrpGroup - она должна применяться к следующим каналам
          attributes = {};
        }
      }

      return channels;
    } catch (e) {
      // Пытаемся загрузить из JSON как fallback
      try {
        return await loadChannelsFromJson();
      } catch (_) {
        return [];
      }
    }
  }

  /// Загружает каналы из JSON файла
  Future<List<IptvChannel>> loadChannelsFromJson() async {
    try {
      final appDir = await _getAppDirectory();
      final jsonFile = File('${appDir.path}/$_channelsFileName');
      
      if (!await jsonFile.exists()) {
        return [];
      }
      
      final content = await jsonFile.readAsString(encoding: utf8);
      final jsonData = jsonDecode(content) as List<dynamic>;
      
      return jsonData.map((json) => IptvChannel.fromJson(json as Map<String, dynamic>)).toList();
    } catch (e) {
      return [];
    }
  }

  /// Проверяет наличие сохраненного плейлиста
  Future<bool> hasSavedPlaylist() async {
    try {
      final appDir = await _getAppDirectory();
      final playlistFile = File('${appDir.path}/$_playlistFileName');
      final jsonFile = File('${appDir.path}/$_channelsFileName');
      
      return await playlistFile.exists() || await jsonFile.exists();
    } catch (e) {
      return false;
    }
  }

  /// Удаляет сохраненный плейлист
  Future<void> deleteSavedPlaylist() async {
    try {
      final appDir = await _getAppDirectory();
      final playlistFile = File('${appDir.path}/$_playlistFileName');
      final jsonFile = File('${appDir.path}/$_channelsFileName');
      
      if (await playlistFile.exists()) {
        await playlistFile.delete();
      }
      
      if (await jsonFile.exists()) {
        await jsonFile.delete();
      }
    } catch (e) {
      throw Exception('Ошибка удаления плейлиста: $e');
    }
  }
}

