import 'package:uuid/uuid.dart';
import '../database/app_database.dart';

/// Represents a configurable chat folder tab (e.g. "All", "Personal", "Groups", "Channels", or custom).
class ChatFolder {
  final String id;
  final String name;
  final String iconName;
  final List<String> includedTypes;
  final List<String> includedChatIds;
  final List<String> excludedChatIds;
  final int order;
  final bool isDefault;

  const ChatFolder({
    required this.id,
    required this.name,
    this.iconName = 'folder',
    this.includedTypes = const [],
    this.includedChatIds = const [],
    this.excludedChatIds = const [],
    this.order = 0,
    this.isDefault = false,
  });

  ChatFolder copyWith({
    String? id,
    String? name,
    String? iconName,
    List<String>? includedTypes,
    List<String>? includedChatIds,
    List<String>? excludedChatIds,
    int? order,
    bool? isDefault,
  }) {
    return ChatFolder(
      id: id ?? this.id,
      name: name ?? this.name,
      iconName: iconName ?? this.iconName,
      includedTypes: includedTypes ?? this.includedTypes,
      includedChatIds: includedChatIds ?? this.includedChatIds,
      excludedChatIds: excludedChatIds ?? this.excludedChatIds,
      order: order ?? this.order,
      isDefault: isDefault ?? this.isDefault,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'icon_name': iconName,
        'included_types': includedTypes,
        'included_chat_ids': includedChatIds,
        'excluded_chat_ids': excludedChatIds,
        'order': order,
        'is_default': isDefault,
      };

  factory ChatFolder.fromJson(Map<String, dynamic> json) {
    return ChatFolder(
      id: json['id'] as String? ?? const Uuid().v4(),
      name: json['name'] as String? ?? '',
      iconName: json['icon_name'] as String? ?? 'folder',
      includedTypes: (json['included_types'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      includedChatIds: (json['included_chat_ids'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      excludedChatIds: (json['excluded_chat_ids'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      order: (json['order'] as num?)?.toInt() ?? 0,
      isDefault: json['is_default'] as bool? ?? false,
    );
  }

  /// Determines if a chat matches this folder filter rules.
  bool matchesChat(Chat chat) {
    if (excludedChatIds.contains(chat.id)) return false;
    if (includedChatIds.contains(chat.id)) return true;

    if (id == 'all') return true;

    if (includedTypes.isEmpty && includedChatIds.isEmpty) {
      return false;
    }

    return includedTypes.contains(chat.chatType);
  }

  /// Default baseline folders for any user account.
  static List<ChatFolder> get defaults => [
        const ChatFolder(
          id: 'all',
          name: 'Все',
          iconName: 'chat',
          includedTypes: ['private', 'group', 'channel', 'saved', 'system'],
          order: 0,
          isDefault: true,
        ),
        const ChatFolder(
          id: 'personal',
          name: 'Личные',
          iconName: 'user',
          includedTypes: ['private', 'saved'],
          order: 1,
          isDefault: false,
        ),
        const ChatFolder(
          id: 'groups',
          name: 'Группы',
          iconName: 'group',
          includedTypes: ['group'],
          order: 2,
          isDefault: false,
        ),
        const ChatFolder(
          id: 'channels',
          name: 'Каналы',
          iconName: 'megaphone',
          includedTypes: ['channel'],
          order: 3,
          isDefault: false,
        ),
      ];
}
