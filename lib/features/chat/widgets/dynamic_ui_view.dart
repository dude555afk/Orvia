import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

typedef DynamicUiCallback = void Function(
  String event,
  Map<String, String> data,
);

class DynamicUiView extends StatefulWidget {
  const DynamicUiView({
    super.key,
    required this.payloadJson,
    this.onCallback,
    this.interactive = true,
  });

  final String payloadJson;
  final DynamicUiCallback? onCallback;
  final bool interactive;

  @override
  State<DynamicUiView> createState() => _DynamicUiViewState();
}

class _DynamicUiViewState extends State<DynamicUiView> {
  static const _maxDepth = 10;

  final Map<String, String> _values = <String, String>{};
  final Map<String, bool> _visibility = <String, bool>{};
  final Map<String, int> _tabIndexes = <String, int>{};
  final Map<String, bool> _expanded = <String, bool>{};

  Object? _decoded;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didUpdateWidget(covariant DynamicUiView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.payloadJson != widget.payloadJson) {
      _parse();
    }
  }

  void _parse() {
    try {
      _decoded = jsonDecode(widget.payloadJson);
      _failed = false;
      _seedValues(_decoded);
    } catch (_) {
      _decoded = null;
      _failed = true;
    }
  }

  void _seedValues(Object? node) {
    if (node is List) {
      for (final child in node) {
        _seedValues(child);
      }
      return;
    }
    if (node is! Map) return;
    final map = Map<String, dynamic>.from(node);
    final id = map['id']?.toString();
    final type = (map['type'] ?? map['kind'] ?? '').toString();
    if (id != null && id.isNotEmpty) {
      switch (type) {
        case 'text_input':
          _values.putIfAbsent(id, () => (map['value'] ?? '').toString());
        case 'checkbox':
        case 'switch':
          _values.putIfAbsent(id, () => (map['checked'] == true).toString());
        case 'select':
        case 'radio_group':
          _values.putIfAbsent(id, () => (map['selected'] ?? '').toString());
        case 'slider':
          _values.putIfAbsent(id, () => (map['value'] ?? 0).toString());
      }
    }
    for (final child in _childrenOf(map)) {
      _seedValues(child);
    }
    final tabs = map['tabs'];
    if (tabs is List) {
      for (final tab in tabs) {
        if (tab is Map) {
          for (final child in _asList(tab['children'])) {
            _seedValues(child);
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed || _decoded == null) {
      return Text(
        'Dynamic UI could not be rendered',
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      );
    }

    final root = _decoded is List
        ? <String, dynamic>{'type': 'column', 'children': _decoded}
        : Map<String, dynamic>.from(_decoded as Map);

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(
            alpha: 0.45,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: _buildNode(context, root, 0),
      ),
    );
  }

  Widget _buildNode(
    BuildContext context,
    Map<String, dynamic> node,
    int depth,
  ) {
    if (depth > _maxDepth) return const SizedBox.shrink();

    final id = node['id']?.toString();
    if (id != null && _visibility[id] == false) {
      return const SizedBox.shrink();
    }

    final type = (node['type'] ?? node['kind'] ?? '').toString();
    final children = _childrenOf(node);

    switch (type) {
      case 'column':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: _spaced(
            children.map((child) => _buildNode(context, child, depth + 1)),
          ),
        );

      case 'row':
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final child in children)
              _buildNode(context, child, depth + 1),
          ],
        );

      case 'card':
        return Card(
          elevation: 0,
          color: Theme.of(context).colorScheme.surfaceContainer,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: _spaced(
                children.map(
                  (child) => _buildNode(context, child, depth + 1),
                ),
              ),
            ),
          ),
        );

      case 'box':
        return Align(
          alignment: _alignment(node['contentAlignment']?.toString()),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final child in children)
                _buildNode(context, child, depth + 1),
            ],
          ),
        );

      case 'divider':
        return const Divider();

      case 'text':
        return Text(
          (node['value'] ?? '').toString(),
          style: _textStyle(context, node),
        );

      case 'quote':
        return Container(
          padding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                width: 3,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text((node['text'] ?? '').toString()),
              if ((node['source'] ?? '').toString().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    (node['source'] ?? '').toString(),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
            ],
          ),
        );

      case 'badge':
        return Align(
          alignment: Alignment.centerLeft,
          child: Chip(label: Text((node['value'] ?? '').toString())),
        );

      case 'stat':
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              (node['value'] ?? '').toString(),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(
              (node['label'] ?? '').toString(),
              style: Theme.of(context).textTheme.labelMedium,
            ),
            if ((node['description'] ?? '').toString().isNotEmpty)
              Text(
                (node['description'] ?? '').toString(),
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        );

      case 'button':
        return _button(node);

      case 'text_input':
        return TextFormField(
          key: ValueKey('dynamic-ui-input:$id'),
          initialValue: _values[id] ?? (node['value'] ?? '').toString(),
          enabled: widget.interactive,
          maxLines: node['multiline'] == true ? 5 : 1,
          decoration: InputDecoration(
            labelText: _nullIfEmpty(node['label']),
            hintText: _nullIfEmpty(node['placeholder']),
            border: const OutlineInputBorder(),
          ),
          onChanged: id == null ? null : (value) => _values[id] = value,
        );

      case 'checkbox':
        return CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text((node['label'] ?? '').toString()),
          value: _boolValue(id, node['checked']),
          onChanged: !widget.interactive || id == null
              ? null
              : (value) => setState(() {
                  _values[id] = (value ?? false).toString();
                }),
        );

      case 'switch':
        return SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text((node['label'] ?? '').toString()),
          value: _boolValue(id, node['checked']),
          onChanged: !widget.interactive || id == null
              ? null
              : (value) => setState(() {
                  _values[id] = value.toString();
                }),
        );

      case 'slider':
        final min = _number(node['min'], 0);
        final max = _number(node['max'], 100);
        final value = _number(_values[id] ?? node['value'], min)
            .clamp(min, max)
            .toDouble();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if ((node['label'] ?? '').toString().isNotEmpty)
              Text('${node['label']} · ${_formatNumber(value)}'),
            Slider(
              min: min,
              max: max <= min ? min + 1 : max,
              value: value,
              onChanged: !widget.interactive || id == null
                  ? null
                  : (next) => setState(() {
                      _values[id] = next.toString();
                    }),
            ),
          ],
        );

      case 'select':
        return _select(node);

      case 'radio_group':
        return _radioGroup(node);

      case 'chip_group':
        return _chipGroup(node);

      case 'progress':
        final raw = _number(node['value'], 0);
        final value = raw > 1 ? raw / 100 : raw;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if ((node['label'] ?? '').toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text((node['label'] ?? '').toString()),
              ),
            LinearProgressIndicator(value: value.clamp(0, 1).toDouble()),
          ],
        );

      case 'alert':
        final severity = (node['severity'] ?? 'info').toString();
        final color = switch (severity) {
          'error' => Theme.of(context).colorScheme.errorContainer,
          'warning' => Theme.of(context).colorScheme.tertiaryContainer,
          'success' => Theme.of(context).colorScheme.secondaryContainer,
          _ => Theme.of(context).colorScheme.primaryContainer,
        };
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if ((node['title'] ?? '').toString().isNotEmpty)
                Text(
                  (node['title'] ?? '').toString(),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              Text((node['message'] ?? '').toString()),
            ],
          ),
        );

      case 'image':
        final url = (node['url'] ?? '').toString();
        if (url.isEmpty) return const SizedBox.shrink();
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            url,
            height: _number(node['height'], 220),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        );

      case 'list':
        final items = _mapList(node['items']);
        final ordered = node['ordered'] == true;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (index, item) in items.indexed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ordered ? '${index + 1}. ' : '• '),
                    Expanded(child: _buildNode(context, item, depth + 1)),
                  ],
                ),
              ),
          ],
        );

      case 'table':
        final headers = _asList(node['headers']).map((e) => '$e').toList();
        final rows = _asList(node['rows']);
        if (headers.isEmpty) return const SizedBox.shrink();
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: [
              for (final header in headers)
                DataColumn(label: Text(header)),
            ],
            rows: [
              for (final row in rows)
                if (row is List)
                  DataRow(
                    cells: [
                      for (var i = 0; i < headers.length; i++)
                        DataCell(Text(i < row.length ? '${row[i]}' : '')),
                    ],
                  ),
            ],
          ),
        );

      case 'tabs':
        return _tabs(context, node, depth);

      case 'accordion':
        final key = id ?? 'accordion-${node.hashCode}';
        final open = _expanded[key] ?? (node['expanded'] == true);
        return ExpansionTile(
          initiallyExpanded: open,
          onExpansionChanged: (value) => _expanded[key] = value,
          title: Text((node['title'] ?? '').toString()),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                children: [
                  for (final child in children)
                    _buildNode(context, child, depth + 1),
                ],
              ),
            ),
          ],
        );

      case 'code':
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: SelectableText(
            (node['code'] ?? '').toString(),
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        );

      case 'avatar':
        final size = _number(node['size'], 44);
        final image = (node['imageUrl'] ?? '').toString();
        final name = (node['name'] ?? '').toString();
        return CircleAvatar(
          radius: size / 2,
          backgroundImage: image.isEmpty ? null : NetworkImage(image),
          child: image.isEmpty
              ? Text(name.isEmpty ? '?' : name.characters.first)
              : null,
        );

      case 'icon':
        return Icon(
          _icon((node['name'] ?? '').toString()),
          size: _number(node['size'], 24),
        );

      default:
        if (children.isNotEmpty) {
          return Column(
            children: [
              for (final child in children)
                _buildNode(context, child, depth + 1),
            ],
          );
        }
        return const SizedBox.shrink();
    }
  }

  Widget _button(Map<String, dynamic> node) {
    final label = (node['label'] ?? '').toString();
    final enabled = widget.interactive && node['enabled'] != false;
    final variant = (node['variant'] ?? 'filled').toString();
    final onPressed = enabled ? () => _runAction(node['action']) : null;
    return switch (variant) {
      'outlined' => OutlinedButton(onPressed: onPressed, child: Text(label)),
      'text' => TextButton(onPressed: onPressed, child: Text(label)),
      'tonal' => FilledButton.tonal(onPressed: onPressed, child: Text(label)),
      _ => FilledButton(onPressed: onPressed, child: Text(label)),
    };
  }

  Widget _select(Map<String, dynamic> node) {
    final id = node['id']?.toString();
    final options = _asList(node['options']).map((e) => '$e').toList();
    final selected = _values[id] ?? (node['selected'] ?? '').toString();
    final value = options.contains(selected) ? selected : null;
    return DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(
        labelText: _nullIfEmpty(node['label']),
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final option in options)
          DropdownMenuItem(value: option, child: Text(option)),
      ],
      onChanged: !widget.interactive || id == null
          ? null
          : (next) {
              if (next != null) setState(() => _values[id] = next);
            },
    );
  }

  Widget _radioGroup(Map<String, dynamic> node) {
    final id = node['id']?.toString();
    final options = _asList(node['options']).map((e) => '$e').toList();
    final selected = _values[id] ?? (node['selected'] ?? '').toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if ((node['label'] ?? '').toString().isNotEmpty)
          Text(
            (node['label'] ?? '').toString(),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        for (final option in options)
          RadioListTile<String>(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(option),
            value: option,
            groupValue: selected,
            onChanged: !widget.interactive || id == null
                ? null
                : (next) {
                    if (next != null) setState(() => _values[id] = next);
                  },
          ),
      ],
    );
  }

  Widget _chipGroup(Map<String, dynamic> node) {
    final id = node['id']?.toString();
    final selection = (node['selection'] ?? 'single').toString();
    final chips = _asList(node['chips'])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final current = (_values[id] ?? '')
        .split(',')
        .where((e) => e.isNotEmpty)
        .toSet();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final chip in chips)
          FilterChip(
            label: Text((chip['label'] ?? '').toString()),
            selected: current.contains((chip['value'] ?? '').toString()),
            onSelected:
                !widget.interactive || id == null || selection == 'none'
                ? null
                : (selected) => setState(() {
                    final value = (chip['value'] ?? '').toString();
                    if (selection == 'multi') {
                      if (selected) {
                        current.add(value);
                      } else {
                        current.remove(value);
                      }
                      _values[id] = current.join(',');
                    } else {
                      _values[id] = selected ? value : '';
                    }
                  }),
          ),
      ],
    );
  }

  Widget _tabs(
    BuildContext context,
    Map<String, dynamic> node,
    int depth,
  ) {
    final key = node['id']?.toString() ?? 'tabs-${node.hashCode}';
    final tabs = _asList(node['tabs'])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    if (tabs.isEmpty) return const SizedBox.shrink();
    final index = (_tabIndexes[key] ?? _int(node['selectedIndex'], 0))
        .clamp(0, tabs.length - 1);
    final selected = tabs[index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          children: [
            for (var i = 0; i < tabs.length; i++)
              ChoiceChip(
                label: Text((tabs[i]['label'] ?? '').toString()),
                selected: i == index,
                onSelected: widget.interactive
                    ? (_) => setState(() => _tabIndexes[key] = i)
                    : null,
              ),
          ],
        ),
        const SizedBox(height: 8),
        for (final child in _mapList(selected['children']))
          _buildNode(context, child, depth + 1),
      ],
    );
  }

  Future<void> _runAction(Object? raw) async {
    if (!widget.interactive || raw is! Map) return;
    final action = Map<String, dynamic>.from(raw);
    final type = (action['type'] ?? action['kind'] ?? '').toString();

    switch (type) {
      case 'callback':
        final event = (action['event'] ?? '').toString();
        if (event.isEmpty) return;
        final data = <String, String>{};
        final rawData = action['data'];
        if (rawData is Map) {
          for (final entry in rawData.entries) {
            data['${entry.key}'] = '${entry.value}';
          }
        }
        final collectFrom = _asList(action['collectFrom']).map((e) => '$e');
        for (final id in collectFrom) {
          final value = _values[id];
          if (value != null) data[id] = value;
        }
        widget.onCallback?.call(event, data);

      case 'toggle':
        final target = (action['targetId'] ?? '').toString();
        if (target.isNotEmpty) {
          setState(() {
            _visibility[target] = !(_visibility[target] ?? true);
          });
        }

      case 'open_url':
        final rawUrl = (action['url'] ?? '').toString();
        final uri = Uri.tryParse(rawUrl);
        if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }

      case 'copy_to_clipboard':
        await Clipboard.setData(
          ClipboardData(text: (action['text'] ?? '').toString()),
        );
    }
  }

  List<Widget> _spaced(Iterable<Widget> widgets) {
    final out = <Widget>[];
    for (final child in widgets) {
      if (out.isNotEmpty) out.add(const SizedBox(height: 8));
      out.add(child);
    }
    return out;
  }

  List<Map<String, dynamic>> _childrenOf(Map<String, dynamic> node) =>
      _mapList(node['children']);

  List<Map<String, dynamic>> _mapList(Object? value) => [
        for (final item in _asList(value))
          if (item is Map) Map<String, dynamic>.from(item),
      ];

  List<Object?> _asList(Object? value) =>
      value is List ? List<Object?>.from(value) : const <Object?>[];

  bool _boolValue(String? id, Object? fallback) {
    final value = id == null ? null : _values[id];
    return value == null ? fallback == true : value == 'true';
  }

  double _number(Object? value, double fallback) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? fallback;
  }

  int _int(Object? value, int fallback) {
    if (value is int) return value;
    return int.tryParse('$value') ?? fallback;
  }

  String? _nullIfEmpty(Object? value) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty ? null : text;
  }

  String _formatNumber(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(2);

  Alignment _alignment(String? raw) => switch (raw) {
        'topStart' => Alignment.topLeft,
        'topEnd' => Alignment.topRight,
        'centerStart' => Alignment.centerLeft,
        'centerEnd' => Alignment.centerRight,
        'bottomStart' => Alignment.bottomLeft,
        'bottomEnd' => Alignment.bottomRight,
        'topCenter' => Alignment.topCenter,
        'bottomCenter' => Alignment.bottomCenter,
        _ => Alignment.center,
      };

  TextStyle _textStyle(BuildContext context, Map<String, dynamic> node) {
    final style = (node['style'] ?? 'body').toString();
    var base = switch (style) {
      'headline' => Theme.of(context).textTheme.headlineSmall,
      'title' => Theme.of(context).textTheme.titleMedium,
      'caption' => Theme.of(context).textTheme.bodySmall,
      _ => Theme.of(context).textTheme.bodyMedium,
    };
    base ??= const TextStyle();
    return base.copyWith(
      fontWeight: node['bold'] == true ? FontWeight.w700 : base.fontWeight,
      fontStyle: node['italic'] == true ? FontStyle.italic : base.fontStyle,
    );
  }

  IconData _icon(String raw) => switch (raw) {
        'home' => Icons.home,
        'search' => Icons.search,
        'settings' => Icons.settings,
        'favorite' => Icons.favorite,
        'star' => Icons.star,
        'check' => Icons.check,
        'close' => Icons.close,
        'warning' => Icons.warning,
        'info' => Icons.info,
        'edit' => Icons.edit,
        'delete' => Icons.delete,
        'refresh' => Icons.refresh,
        'download' => Icons.download,
        'upload' => Icons.upload,
        'share' => Icons.share,
        'code' => Icons.code,
        'terminal' => Icons.terminal,
        'email' => Icons.email,
        'person' => Icons.person,
        'school' => Icons.school,
        'science' => Icons.science,
        'work' => Icons.work,
        _ => Icons.circle_outlined,
      };
}
