import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/iptv_channel.dart';

class FavoritesService {
  static const String _favoritesKey = 'favorite_channels';

  Future<List<IptvChannel>> getFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final favoritesJson = prefs.getStringList(_favoritesKey);
    
    if (favoritesJson == null || favoritesJson.isEmpty) {
      return [];
    }

    return favoritesJson
        .map((json) => IptvChannel.fromJson(jsonDecode(json) as Map<String, dynamic>))
        .toList();
  }

  Future<void> addFavorite(IptvChannel channel) async {
    final favorites = await getFavorites();
    
    if (favorites.any((fav) => fav.url == channel.url && fav.name == channel.name)) {
      return;
    }

    favorites.add(channel);
    await _saveFavorites(favorites);
  }

  Future<void> removeFavorite(IptvChannel channel) async {
    final favorites = await getFavorites();
    favorites.removeWhere((fav) => fav.url == channel.url && fav.name == channel.name);
    await _saveFavorites(favorites);
  }

  Future<bool> isFavorite(IptvChannel channel) async {
    final favorites = await getFavorites();
    return favorites.any((fav) => fav.url == channel.url && fav.name == channel.name);
  }

  Future<void> _saveFavorites(List<IptvChannel> favorites) async {
    final prefs = await SharedPreferences.getInstance();
    final favoritesJson = favorites
        .map((channel) => jsonEncode(channel.toJson()))
        .toList();
    await prefs.setStringList(_favoritesKey, favoritesJson);
  }
}

