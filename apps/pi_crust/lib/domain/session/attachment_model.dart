import 'dart:convert';

enum AttachmentType {
  repoFile,
  externalFile,
  webLink,
  image,
}

class ChatAttachment {
  final String id;
  final AttachmentType type;
  final String name;
  final String pathOrUrl;
  final int? sizeBytes;

  const ChatAttachment({
    required this.id,
    required this.type,
    required this.name,
    required this.pathOrUrl,
    this.sizeBytes,
  });

  bool get isImage => type == AttachmentType.image;
  bool get isWebLink => type == AttachmentType.webLink;
  bool get isFile =>
      type == AttachmentType.repoFile || type == AttachmentType.externalFile;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'name': name,
    'pathOrUrl': pathOrUrl,
    if (sizeBytes != null) 'sizeBytes': sizeBytes,
  };

  factory ChatAttachment.fromJson(Map<String, dynamic> json) {
    return ChatAttachment(
      id: json['id']?.toString() ?? '',
      type: AttachmentType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => AttachmentType.externalFile,
      ),
      name: json['name']?.toString() ?? '',
      pathOrUrl: json['pathOrUrl']?.toString() ?? '',
      sizeBytes: (json['sizeBytes'] as num?)?.toInt(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatAttachment &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          pathOrUrl == other.pathOrUrl;

  @override
  int get hashCode => id.hashCode ^ pathOrUrl.hashCode;
}

bool isImageExtension(String path) {
  final clean = path.toLowerCase().trim();
  return clean.endsWith('.png') ||
      clean.endsWith('.jpg') ||
      clean.endsWith('.jpeg') ||
      clean.endsWith('.gif') ||
      clean.endsWith('.webp') ||
      clean.endsWith('.bmp') ||
      clean.endsWith('.svg') ||
      clean.endsWith('.ico') ||
      clean.endsWith('.tiff');
}

/// Encodes attachments into a structured HTML/markdown comment tag:
/// `<!--pi-attachments:[{"id":"...","type":"image",...}]-->`
String encodeAttachmentsTag(List<ChatAttachment> attachments) {
  if (attachments.isEmpty) return '';
  final listJson = jsonEncode(attachments.map((a) => a.toJson()).toList());
  return '<!--pi-attachments:$listJson-->';
}

/// Parses attachments from message text and returns the clean text and list of attachments.
(String cleanText, List<ChatAttachment> attachments) parseAttachmentsFromText(
  String rawText,
) {
  if (rawText.isEmpty) return ('', const <ChatAttachment>[]);

  final regex = RegExp(r'<!--pi-attachments:(.*?)-->', dotAll: true);
  final match = regex.firstMatch(rawText);

  if (match == null) {
    return (rawText, const <ChatAttachment>[]);
  }

  final jsonStr = match.group(1)?.trim() ?? '';
  final attachments = <ChatAttachment>[];

  try {
    final decoded = jsonDecode(jsonStr);
    if (decoded is List) {
      for (final item in decoded) {
        if (item is Map) {
          attachments.add(
            ChatAttachment.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
  } catch (_) {
    // If invalid JSON, ignore parsing failure gracefully
  }

  // Remove the comment tag from the user text
  final cleanText = rawText.replaceAll(regex, '').trim();
  return (cleanText, attachments);
}
