class LocalFileItem {
  const LocalFileItem({
    required this.path,
    required this.name,
    required this.size,
    this.mimeType,
  });

  final String path;
  final String name;
  final int size;
  final String? mimeType;
}
