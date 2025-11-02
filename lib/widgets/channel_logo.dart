import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class ChannelLogo extends StatefulWidget {
  final String? logoUrl;
  final double width;
  final double height;

  const ChannelLogo({
    super.key,
    this.logoUrl,
    this.width = 48,
    this.height = 48,
  });

  @override
  State<ChannelLogo> createState() => _ChannelLogoState();
}

class _ChannelLogoState extends State<ChannelLogo> {
  Future<ImageProvider?>? _imageFuture;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    if (widget.logoUrl != null && widget.logoUrl!.isNotEmpty) {
      _loadImage();
    }
  }

  @override
  void didUpdateWidget(ChannelLogo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.logoUrl != widget.logoUrl) {
      _hasError = false;
      if (widget.logoUrl != null && widget.logoUrl!.isNotEmpty) {
        _loadImage();
      }
    }
  }

  Future<void> _loadImage() async {
    if (widget.logoUrl == null || widget.logoUrl!.isEmpty) {
      return;
    }

    try {
      final uri = Uri.parse(widget.logoUrl!);
      
      // Проверяем, что это валидный URL
      if (!uri.hasScheme || (!uri.scheme.startsWith('http'))) {
        if (mounted) {
          setState(() => _hasError = true);
        }
        return;
      }

      // Создаем Future для загрузки изображения в отдельном изоляте
      _imageFuture = _loadImageAsync(uri);
      
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        setState(() => _hasError = true);
      }
    }
  }

  Future<ImageProvider?> _loadImageAsync(Uri uri) async {
    try {
      // Загружаем изображение асинхронно
      final response = await http.get(uri).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        return MemoryImage(response.bodyBytes);
      } else {
        return null;
      }
    } catch (e) {
      return null;
    }
  }

  Widget _buildNoLogo() {
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: Colors.grey[700],
        borderRadius: BorderRadius.circular(6),
      ),
      child: Center(
        child: Text(
          'no logo',
          style: TextStyle(
            color: Colors.grey[400],
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(6),
      ),
      child: Center(
        child: SizedBox(
          width: widget.width * 0.4,
          height: widget.height * 0.4,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(
              Colors.grey[400]!,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Если нет URL логотипа
    if (widget.logoUrl == null || widget.logoUrl!.isEmpty || _hasError) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: _buildNoLogo(),
      );
    }

    // Если Future еще не создан
    if (_imageFuture == null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: _buildLoading(),
      );
    }

    // Показываем результат загрузки
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: FutureBuilder<ImageProvider?>(
        future: _imageFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildLoading();
          }

          if (snapshot.hasError || snapshot.data == null) {
            return _buildNoLogo();
          }

          try {
            return Image(
              image: snapshot.data!,
              width: widget.width,
              height: widget.height,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return _buildNoLogo();
              },
            );
          } catch (e) {
            return _buildNoLogo();
          }
        },
      ),
    );
  }
}

