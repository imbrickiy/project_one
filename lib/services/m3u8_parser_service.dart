import 'dart:io';
import 'dart:convert';
import '../models/iptv_channel.dart';

class M3u8ParserService {
  Future<List<IptvChannel>> parseM3u8File(File file) async {
    try {
      final content = await file.readAsString();
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
          // Парсинг метаданных канала
          final info = line.substring(8); // Убираем #EXTINF:
          
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

          // Извлекаем другие атрибуты
          final attributesMatch = RegExp(r'(\w+)="([^"]+)"').allMatches(info);
          for (final match in attributesMatch) {
            attributes[match.group(1)!] = match.group(2)!;
          }

          // Извлекаем название канала (последняя часть после всех атрибутов)
          final nameMatch = RegExp(r',(.+)$').firstMatch(info);
          channelName = nameMatch?.group(1)?.trim() ?? 'Без названия';
        } else if (line.isNotEmpty && 
                   !line.startsWith('#') && 
                   channelName != null) {
          // URL канала
          channelUrl = line;
          
          // Если группа не была определена в #EXTINF, используем группу из #EXTGRP
          if (group == null && extgrpGroup != null) {
            group = extgrpGroup;
          }
          
          // Создаем канал и добавляем в список
          channels.add(IptvChannel.fromM3u(
            name: channelName,
            url: channelUrl,
            logo: logo,
            group: group,
            attributes: attributes.isNotEmpty ? attributes : null,
          ));

          // Сбрасываем переменные для следующего канала
          // НЕ сбрасываем extgrpGroup - она должна применяться к следующим каналам
          channelName = null;
          channelUrl = null;
          logo = null;
          group = null;
          attributes = {};
        }
      }

      return channels;
    } catch (e) {
      throw Exception('Ошибка парсинга m3u8 файла: $e');
    }
  }

  Future<List<IptvChannel>> parseM3u8FromUrl(String url) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      
      final content = await response.transform(utf8.decoder).join();
      
      final tempFile = File('${Directory.systemTemp.path}/temp_playlist.m3u8');
      await tempFile.writeAsString(content);
      
      final channels = await parseM3u8File(tempFile);
      
      await tempFile.delete();
      
      return channels;
    } catch (e) {
      throw Exception('Ошибка загрузки m3u8 файла: $e');
    } finally {
      client.close();
    }
  }
}

