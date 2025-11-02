class IptvChannel {
  final String name;
  final String url;
  final String? logo;
  final String? group;
  final Map<String, String>? attributes;

  const IptvChannel({
    required this.name,
    required this.url,
    this.logo,
    this.group,
    this.attributes,
  });

  factory IptvChannel.fromM3u({
    required String name,
    required String url,
    String? logo,
    String? group,
    Map<String, String>? attributes,
  }) {
    return IptvChannel(
      name: name,
      url: url,
      logo: logo,
      group: group,
      attributes: attributes,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'url': url,
      'logo': logo,
      'group': group,
      'attributes': attributes,
    };
  }

  factory IptvChannel.fromJson(Map<String, dynamic> json) {
    return IptvChannel(
      name: json['name'] as String,
      url: json['url'] as String,
      logo: json['logo'] as String?,
      group: json['group'] as String?,
      attributes: json['attributes'] != null
          ? Map<String, String>.from(json['attributes'] as Map)
          : null,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is IptvChannel && other.url == url && other.name == name;
  }

  @override
  int get hashCode => url.hashCode ^ name.hashCode;
}

