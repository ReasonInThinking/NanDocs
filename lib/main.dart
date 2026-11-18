import 'dart:convert';
import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const NanDocsApp());
}


// ==========================================
// ЕДИНЫЙ СТИЛЬ (ТЕМА)
// ==========================================
class DockTheme {
  static const Color bgMain = Color(0xFF0E1116);
  static const Color bgSurface = Color(0xFF161B22);
  static const Color bgHover = Color(0xFF1F2630);
  static const Color border = Color(0xFF30363D);
  static const Color accent = Color(0xFF3B82F6);
  static const Color textPrimary = Color(0xFFE6EDF3);
  static const Color textMuted = Color(0xFF8B949E);

  static const double radius = 12.0;
}

// ==========================================
// МОДЕЛЬ ЗАКРЕПЛЁННОГО ФАЙЛА
// ==========================================
class DockItem {
  String id;
  String name;
  String path;
  String category;
  bool isDirectory;

  DockItem({
    required this.id,
    required this.name,
    required this.path,
    required this.category,
    required this.isDirectory,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'path': path,
        'category': category,
        'isDirectory': isDirectory,
      };

  factory DockItem.fromJson(Map<String, dynamic> json) => DockItem(
        id: json['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
        name: json['name']?.toString() ?? 'Файл',
        path: json['path']?.toString() ?? '',
        category: json['category']?.toString() ?? 'Общее',
        isDirectory: json['isDirectory'] == true,
      );
}

class NanDocsApp extends StatelessWidget {
  const NanDocsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NanDocs',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: DockTheme.bgMain,
        cardColor: DockTheme.bgSurface,
        colorScheme: const ColorScheme.dark(
          primary: DockTheme.accent,
          surface: DockTheme.bgSurface,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: DockTheme.bgMain,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
      ),
      home: const DockHomeScreen(),
    );
  }
}



class DockHomeScreen extends StatefulWidget {
  const DockHomeScreen({super.key});

  @override
  State<DockHomeScreen> createState() => _DockHomeScreenState();
}

class _DockHomeScreenState extends State<DockHomeScreen> {
  List<DockItem> _items = [];
  List<String> _categories = ['Все', 'Программы', 'Документы', 'Проекты'];
  String _selectedCategory = 'Все';
  String _searchQuery = '';
  bool _isDragging = false;
  final TextEditingController _searchController = TextEditingController();

  String get _storagePath {
    final home = Platform.environment['HOME'] ?? '.';
    return '$home/.file_dock.json';
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final file = File(_storagePath);
      if (await file.exists()) {
        final content = await file.readAsString();
        final decoded = jsonDecode(content);
        if (decoded is Map<String, dynamic>) {
          final rawCats = decoded['categories'];
          final rawItems = decoded['items'];
          setState(() {
            if (rawCats is List) {
              _categories = rawCats.map((e) => e.toString()).toList();
              if (!_categories.contains('Все')) {
                _categories.insert(0, 'Все');
              }
            }
            if (rawItems is List) {
              _items = rawItems
                  .whereType<Map<String, dynamic>>()
                  .map((e) => DockItem.fromJson(e))
                  .toList();
            }
          });
        }
      }
    } catch (e) {
      _showToast('Ошибка загрузки данных: $e', isError: true);
    }
  }

  Future<void> _saveData() async {
    try {
      final file = File(_storagePath);
      final data = {
        'categories': _categories,
        'items': _items.map((e) => e.toJson()).toList(),
      };
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    } catch (e) {
      _showToast('Ошибка сохранения: $e', isError: true);
    }
  }

  void _showToast(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        width: 340,
        behavior: SnackBarBehavior.floating,
        backgroundColor: DockTheme.bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: isError ? Colors.redAccent : DockTheme.border,
          ),
        ),
        duration: const Duration(seconds: 2),
        content: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle,
              color: isError ? Colors.redAccent : Colors.greenAccent,
              size: 18,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                message,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: DockTheme.textPrimary, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addPaths(List<String> paths) async {
    if (paths.isEmpty) return;

    final targetCategory = _selectedCategory == 'Все'
        ? (_categories.length > 1 ? _categories[1] : 'Общее')
        : _selectedCategory;

    int addedCount = 0;

    setState(() {
      for (final rawPath in paths) {
        final cleanPath = rawPath.trim();
        if (cleanPath.isEmpty) continue;

        final alreadyExists = _items.any((item) => item.path == cleanPath);
        if (alreadyExists) continue;

        final isDir = FileSystemEntity.isDirectorySync(cleanPath);
        final name = cleanPath.split('/').where((s) => s.isNotEmpty).last;

        _items.insert(
          0,
          DockItem(
            id: '${DateTime.now().microsecondsSinceEpoch}_$addedCount',
            name: name,
            path: cleanPath,
            category: targetCategory,
            isDirectory: isDir,
          ),
        );
        addedCount++;
      }
    });

    if (addedCount > 0) {
      await _saveData();
      _showToast('Добавлено в «$targetCategory»: $addedCount');
    } else {
      _showToast('Этот файл уже есть в списке');
    }
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result != null) {
      final paths = result.paths.whereType<String>().toList();
      await _addPaths(paths);
    }
  }

  Future<void> _pickFolder() async {
    final selectedDir = await FilePicker.platform.getDirectoryPath();
    if (selectedDir != null) {
      await _addPaths([selectedDir]);
    }
  }

  Future<void> _launchItem(DockItem item) async {
    final exists = item.isDirectory
        ? await Directory(item.path).exists()
        : await File(item.path).exists();

    if (!exists) {
      _showToast('Файл не найден по старому пути!', isError: true);
      return;
    }

    try {
      if (!item.isDirectory && item.path.toLowerCase().endsWith('.appimage')) {
        await Process.run('chmod', ['+x', item.path]);
        await Process.start(
          item.path,
          [],
          environment: {'GDK_BACKEND': 'x11'},
          mode: ProcessStartMode.detached,
        );
      } else {
        await Process.start(
          'xdg-open',
          [item.path],
          mode: ProcessStartMode.detached,
        );
      }
      _showToast('Запуск: ${item.name}');
    } catch (e) {
      _showToast('Не удалось открыть файл', isError: true);
    }
  }

  Future<void> _openParentFolder(DockItem item) async {
    final parentPath = File(item.path).parent.path;
    if (await Directory(parentPath).exists()) {
      await Process.start(
        'xdg-open',
        [parentPath],
        mode: ProcessStartMode.detached,
      );
    } else {
      _showToast('Папка не найдена', isError: true);
    }
  }


  Future<void> _addCategoryDialog() async {
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: DockTheme.bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DockTheme.radius),
          side: const BorderSide(color: DockTheme.border),
        ),
        title: const Text('Новая категория'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Например: Игры, Музыка, Книги...',
            filled: true,
            fillColor: DockTheme.bgMain,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена', style: TextStyle(color: DockTheme.textMuted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: DockTheme.accent),
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty && !_categories.contains(name)) {
                setState(() {
                  _categories.add(name);
                  _selectedCategory = name;
                });
                await _saveData();
              }
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Создать', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _editItemDialog(DockItem item) async {
    final nameController = TextEditingController(text: item.name);
    String chosenCat = _categories.contains(item.category) && item.category != 'Все'
        ? item.category
        : (_categories.length > 1 ? _categories[1] : 'Общее');

    final availableCats = _categories.where((c) => c != 'Все').toList();
    if (!availableCats.contains(chosenCat)) {
      availableCats.add(chosenCat);
    }

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: DockTheme.bgSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DockTheme.radius),
            side: const BorderSide(color: DockTheme.border),
          ),
          title: const Text('Настройка ярлыка'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: 'Отображаемое имя',
                  filled: true,
                  fillColor: DockTheme.bgMain,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Категория:', style: TextStyle(color: DockTheme.textMuted)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: chosenCat,
                dropdownColor: DockTheme.bgSurface,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: DockTheme.bgMain,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                items: availableCats
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (val) {
                  if (val != null) setDialogState(() => chosenCat = val);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена', style: TextStyle(color: DockTheme.textMuted)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: DockTheme.accent),
              onPressed: () async {
                if (nameController.text.trim().isNotEmpty) {
                  setState(() {
                    item.name = nameController.text.trim();
                    item.category = chosenCat;
                  });
                  await _saveData();
                }
                if (mounted) Navigator.pop(context);
              },
              child: const Text('Сохранить', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  (IconData, Color) _getFileStyle(DockItem item) {
    if (item.isDirectory) {
      return (Icons.folder_rounded, const Color(0xFFF59E0B));
    }
    final lower = item.path.toLowerCase();
    if (lower.endsWith('.appimage') || lower.endsWith('.sh') || lower.endsWith('.bin')) {
      return (Icons.rocket_launch_rounded, const Color(0xFF10B981));
    }
    if (lower.endsWith('.pdf') || lower.endsWith('.doc') || lower.endsWith('.docx') || lower.endsWith('.txt')) {
      return (Icons.description_rounded, const Color(0xFF3B82F6));
    }
    if (lower.endsWith('.png') || lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.webp')) {
      return (Icons.image_rounded, const Color(0xFFEC4899));
    }
    if (lower.endsWith('.mp4') || lower.endsWith('.mkv') || lower.endsWith('.avi') || lower.endsWith('.mp3')) {
      return (Icons.play_circle_fill_rounded, const Color(0xFF8B5CF6));
    }
    if (lower.endsWith('.zip') || lower.endsWith('.tar.gz') || lower.endsWith('.rar') || lower.endsWith('.7z')) {
      return (Icons.archive_rounded, const Color(0xFFF97316));
    }
    return (Icons.insert_drive_file_rounded, DockTheme.textMuted);
  }


  @override
  Widget build(BuildContext context) {
    final q = _searchQuery.trim().toLowerCase();
    final filtered = _items.where((item) {
      final matchesCat =
          _selectedCategory == 'Все' || item.category == _selectedCategory;
      final matchesSearch = q.isEmpty ||
          item.name.toLowerCase().contains(q) ||
          item.path.toLowerCase().contains(q);
      return matchesCat && matchesSearch;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.widgets_rounded, color: DockTheme.accent, size: 24),
            SizedBox(width: 10),
            Text(
              'NanDocs',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
          ],
        ),
        actions: [
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: DockTheme.bgSurface,
              foregroundColor: DockTheme.textPrimary,
              side: const BorderSide(color: DockTheme.border),
            ),
            onPressed: _pickFolder,
            icon: const Icon(Icons.create_new_folder_outlined, size: 18),
            label: const Text('Добавить папку'),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: DockTheme.accent,
              foregroundColor: Colors.white,
            ),
            onPressed: _pickFiles,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Добавить файл'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: DropTarget(
    onDrop: (detail) async {
      setState(() => _isDragging = false);
      final paths = <String>[];
      for (final item in detail.items) {
        if (item is DropFileItem && item.localPath != null) {
          paths.add(item.localPath!);
        } else if (item is DropDirectoryItem && item.localPath != null) {
          paths.add(item.localPath!);
        }
      }
      await _addPaths(paths);
    },
    onEnter: (_) => setState(() => _isDragging = true),
    onLeave: () => setState(() => _isDragging = false),
    child: Stack(
          children: [
            Column(
              children: [
                // ПОИСК И ВКЛАДКИ КАТЕГОРИЙ
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              ..._categories.map((cat) {
                                final isSelected = cat == _selectedCategory;
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ChoiceChip(
                                    label: Text(cat),
                                    selected: isSelected,
                                    selectedColor: DockTheme.accent,
                                    backgroundColor: DockTheme.bgSurface,
                                    labelStyle: TextStyle(
                                      color: isSelected
                                          ? Colors.white
                                          : DockTheme.textPrimary,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                                    side: BorderSide(
                                      color: isSelected
                                          ? DockTheme.accent
                                          : DockTheme.border,
                                    ),
                                    onSelected: (_) =>
                                        setState(() => _selectedCategory = cat),
                                  ),
                                );
                              }),
                              IconButton(
                                tooltip: 'Создать категорию',
                                style: IconButton.styleFrom(
                                  backgroundColor: DockTheme.bgSurface,
                                  side: const BorderSide(color: DockTheme.border),
                                ),
                                icon: const Icon(Icons.add, size: 18),
                                onPressed: _addCategoryDialog,
                              ),
                              if (_selectedCategory != 'Все')
                                IconButton(
                                  tooltip: 'Удалить текущую категорию',
                                  icon: const Icon(Icons.delete_outline,
                                      size: 18, color: Colors.redAccent),
                                  onPressed: () async {
                                    final toRemove = _selectedCategory;
                                    setState(() {
                                      _categories.remove(toRemove);
                                      for (final item in _items) {
                                        if (item.category == toRemove) {
                                          item.category = 'Все';
                                        }
                                      }
                                      _selectedCategory = 'Все';
                                    });
                                    await _saveData();
                                  },
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: 260,
                        child: TextField(
                          controller: _searchController,
                          onChanged: (val) => setState(() => _searchQuery = val),
                          decoration: InputDecoration(
                            hintText: 'Быстрый поиск...',
                            hintStyle: const TextStyle(color: DockTheme.textMuted),
                            prefixIcon: const Icon(Icons.search,
                                size: 18, color: DockTheme.textMuted),
                            isDense: true,
                            filled: true,
                            fillColor: DockTheme.bgSurface,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: DockTheme.border),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // СЕТКА ПЛИТОК
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.file_download_outlined,
                                  size: 64,
                                  color: DockTheme.textMuted.withOpacity(0.5)),
                              const SizedBox(height: 16),
                              const Text(
                                'Перетащите сюда любые файлы или папки',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w500,
                                  color: DockTheme.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Или воспользуйтесь кнопками добавления в верхнем углу',
                                style: TextStyle(color: DockTheme.textMuted),
                              ),
                            ],
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.all(16),
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 280,
                            mainAxisExtent: 120,
                            crossAxisSpacing: 14,
                            mainAxisSpacing: 14,
                          ),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final item = filtered[index];
                            final (iconData, iconColor) = _getFileStyle(item);

                            return InkWell(
                              borderRadius: BorderRadius.circular(DockTheme.radius),
                              onTap: () => _launchItem(item),
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: DockTheme.bgSurface,
                                  borderRadius:
                                      BorderRadius.circular(DockTheme.radius),
                                  border: Border.all(color: DockTheme.border),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: iconColor.withOpacity(0.15),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Icon(iconData,
                                              color: iconColor, size: 22),
                                        ),
                                        const Spacer(),
                                        IconButton(
                                          tooltip: 'Открыть папку с файлом',
                                          icon: const Icon(
                                              Icons.folder_open_rounded,
                                              size: 18,
                                              color: DockTheme.textMuted),
                                          onPressed: () =>
                                              _openParentFolder(item),
                                        ),
                                        IconButton(
                                          tooltip: 'Изменить имя / категорию',
                                          icon: const Icon(Icons.edit_outlined,
                                              size: 18,
                                              color: DockTheme.textMuted),
                                          onPressed: () =>
                                              _editItemDialog(item),
                                        ),
                                        IconButton(
                                          tooltip: 'Убрать из избранного',
                                          icon: const Icon(Icons.close,
                                              size: 18,
                                              color: Colors.redAccent),
                                          onPressed: () async {
                                            setState(() => _items.remove(item));
                                            await _saveData();
                                          },
                                        ),
                                      ],
                                    ),
                                    const Spacer(),
                                    Text(
                                      item.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                        color: DockTheme.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      item.category,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: DockTheme.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),

            // ПОДСВЕТКА ПРИ ПЕРЕТАСКИВАНИИ ФАЙЛОВ В ОКНО
            if (_isDragging)
              Container(
                color: DockTheme.bgMain.withOpacity(0.85),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 24),
                    decoration: BoxDecoration(
                      color: DockTheme.bgSurface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: DockTheme.accent, width: 2),
                    ),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_circle_outline,
                            size: 48, color: DockTheme.accent),
                        SizedBox(height: 12),
                        Text(
                          'Отпустите, чтобы закрепить в NanDocs',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: DockTheme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
