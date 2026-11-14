import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../data/language/language_settings.dart';
import '../../data/language/strings_settings.dart';
import '../../data/theme/theme_providers.dart';
import '../../ui/frame_activity_indicator.dart';
import '../../ui/frame_dialog.dart';
import '../../ui/frame_list_row.dart';
import '../../ui/frame_pane_header.dart';
import '../../ui/frame_search_field.dart';
import '../../ui/frame_snack_bar.dart';
import '../../ui/frame_status_tag.dart';

class ThemeEditorDialog extends ConsumerStatefulWidget {
  final ThemeSpec? initialTheme;

  const ThemeEditorDialog({super.key, this.initialTheme});

  static Future<void> show(BuildContext context, {ThemeSpec? initialTheme}) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ThemeEditorDialog(initialTheme: initialTheme),
    );
  }

  @override
  ConsumerState<ThemeEditorDialog> createState() => _ThemeEditorDialogState();
}

class _ThemeEditorDialogState extends ConsumerState<ThemeEditorDialog> {
  late TextEditingController _nameController;
  late String _selectedBaseThemeId;
  late String _variant;
  final TextEditingController _tokenSearchController = TextEditingController();
  String _tokenQuery = '';
  late Map<String, dynamic> _customColors;
  late Map<String, dynamic> _customSyntax;
  String? _errorMessage;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final active = widget.initialTheme ??
        ref.read(activeThemeSpecProvider) ??
        ref.read(themeRepositoryProvider).activeTheme;
    _selectedBaseThemeId = active.id;
    _nameController = TextEditingController(text: '${active.name} (Custom)');
    _variant = active.variant;
    _customColors = Map<String, dynamic>.from(active.rawColors);
    _customSyntax = Map<String, dynamic>.from(active.rawSyntax);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _tokenSearchController.dispose();
    super.dispose();
  }

  void _onBaseThemeChanged(ThemeSpec baseTheme) {
    setState(() {
      _selectedBaseThemeId = baseTheme.id;
      _variant = baseTheme.variant;
      _nameController.text = '${baseTheme.name} (Custom)';
      _customColors = Map<String, dynamic>.from(baseTheme.rawColors);
      _customSyntax = Map<String, dynamic>.from(baseTheme.rawSyntax);
    });
  }

  Color _resolveColor(String key, {bool isSyntax = false, Color? fallback}) {
    final hex = isSyntax ? _customSyntax[key] : _customColors[key];
    if (hex != null) {
      final parsed = parseHexColor(hex);
      if (parsed != null) return parsed;
    }
    return fallback ?? context.tokens.textMuted;
  }

  void _setColor(String key, Color color, {bool isSyntax = false}) {
    final hex = '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
    setState(() {
      if (isSyntax) {
        _customSyntax[key] = hex;
      } else {
        _customColors[key] = hex;
      }
    });
  }

  Future<void> _openColorPicker(String key, String title, Color currentColor, {bool isSyntax = false}) async {
    final tokens = context.tokens;
    final strings = ref.read(appStringsProvider);
    final hexController = TextEditingController(
      text: '#${currentColor.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
    );

    // Curated palette of modern vibrant and neutral colors
    final palette = [
      '#0F141C', '#161B22', '#1E232A',
      '#262C36', '#323945', '#4A5568',
      '#8B949E', '#C9D1D9', '#F0F6FC',
      '#58A6FF', '#388BFD', '#1F6FEB',
      '#3FB950', '#2EA043', '#238636',
      '#D29922', '#E3B341', '#F0883E',
      '#F85149', '#DA3633', '#A371F7',
      '#BC8CFF', '#DB61A2', '#56D364',
    ].map((h) => parseHexColor(h)!).toList();

    Color selectedColor = currentColor;

    await showFrameDialogBuilder<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return FrameDialog<void>(
            title: title,
            body: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: selectedColor,
                          borderRadius: BorderRadius.circular(tokens.radiusSm),
                          border: Border.all(color: tokens.borderStrong, width: 2),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: hexController,
                          style: TextStyle(
                            fontFamily: tokens.monoFontFamily,
                            color: tokens.textPrimary,
                            fontSize: FrameText.fromTokens(tokens).bodyLarge.fontSize,
                          ),
                          decoration: InputDecoration(
                            labelText: strings.themeEditorHexLabel,
                            labelStyle: FrameText.fromTokens(tokens).label.copyWith(color: tokens.textSecondary),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                          onChanged: (val) {
                            final p = parseHexColor(val.trim());
                            if (p != null) {
                              setDialogState(() => selectedColor = p);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    strings.themeEditorSuggestedColors,
                    style: FrameText.fromTokens(tokens).caption.copyWith(color: tokens.textMuted),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: palette.map((color) {
                      final isSelected = color.toARGB32() == selectedColor.toARGB32();
                      return InkWell(
                        onTap: () {
                          setDialogState(() {
                            selectedColor = color;
                            hexController.text = '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
                          });
                        },
                        borderRadius: BorderRadius.circular(tokens.radiusSm),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(tokens.radiusSm),
                            border: Border.all(
                              color: isSelected ? tokens.accent : tokens.border,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            actions: [
              FrameDialogAction(
                label: strings.cancel,
                role: FrameDialogActionRole.cancel,
              ),
              FrameDialogAction(
                label: strings.themeEditorApplyColor,
                role: FrameDialogActionRole.primary,
                onPressed: () =>
                    _setColor(key, selectedColor, isSyntax: isSyntax),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _saveAndApplyTheme() async {
    final name = _nameController.text.trim();
    final strings = ref.read(appStringsProvider);
    if (name.isEmpty) {
      setState(() => _errorMessage = strings.themeEditorNameEmptyError);
      return;
    }

    final slug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');

    final id = 'custom-$slug';

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final spec = ThemeSpec(
        schemaVersion: 1,
        id: id,
        name: name,
        author: 'User',
        version: '1.0.0',
        variant: _variant,
        extendsTheme: _selectedBaseThemeId,
        rawColors: _customColors,
        rawSyntax: _customSyntax,
      );

      await ref.read(activeThemeSpecProvider.notifier).saveCustomTheme(spec);

      if (mounted) {
        Navigator.of(context).pop();
        FrameSnackBar.show(
          context,
          message: strings.themeEditorSavedSuccess(name),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = strings.themeEditorSaveError(e);
          _isSaving = false;
        });
      }
    }
  }

  Widget _buildColorRow(String key, String label, {bool isSyntax = false, required FrameTokens tokens, Color? fallback}) {
    // Token search matches the label, so a long list can be narrowed.
    if (_tokenQuery.trim().isNotEmpty &&
        !label.toLowerCase().contains(_tokenQuery.trim().toLowerCase())) {
      return const SizedBox.shrink();
    }
    final color = _resolveColor(key, isSyntax: isSyntax, fallback: fallback ?? tokens.textMuted);
    final hexString = '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

    return InkWell(
      key: ValueKey('theme-editor-color-$key'),
      onTap: () => _openColorPicker(key, label, color, isSyntax: isSyntax),
      borderRadius: BorderRadius.circular(tokens.radiusSm),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          border: Border.all(color: tokens.border.withValues(alpha: 0.7)),
        ),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(tokens.radiusSm),
                border: Border.all(color: tokens.borderStrong),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: FrameText.fromTokens(tokens).body.copyWith(color: tokens.textPrimary),
              ),
            ),
            Text(
              hexString,
              style: TextStyle(
                color: tokens.textMuted,
                fontFamily: tokens.monoFontFamily,
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.colorize_outlined, size: FrameSize.icon, color: tokens.textMuted),
          ],
        ),
      ),
    );
  }

  /// The edited theme as a full [ThemeSpec], built on the selected base theme.
  ThemeSpec _draftSpec() {
    final repo = ref.read(themeRepositoryProvider);
    final base = repo.availableThemes.firstWhere(
      (t) => t.id == _selectedBaseThemeId,
      orElse: () => repo.activeTheme,
    );
    return base.copyWith(rawColors: _customColors, rawSyntax: _customSyntax);
  }

  /// Live preview built from the real app widgets. The subtree is wrapped in
  /// a Theme made from the draft, so each component shows the edited colours.
  Widget _buildLivePreview(FrameTokens currentTokens, AppStrings strings) {
    return Theme(
      data: _draftSpec().toThemeData(),
      child: Builder(
        builder: (context) {
          final tokens = context.tokens;
          final text = FrameText.of(context);
          return Container(
            key: const ValueKey('theme-editor-preview'),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: tokens.background,
              borderRadius: BorderRadius.circular(tokens.radiusMd),
              border: Border.all(color: tokens.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FramePaneHeader(
                  title: strings.previewLabel,
                  subtitle: strings.themeEditorPreviewPaneSubtitle,
                ),
                // Git row, as in the changes list.
                FrameListRow(
                  name: strings.themeEditorPreviewGitFile,
                  secondary: strings.themeEditorPreviewGitStatus,
                  selected: true,
                  leading: Icon(
                    Icons.description_outlined,
                    size: FrameSize.icon,
                    color: tokens.textSecondary,
                  ),
                  trailing: FrameStatusTag(
                    label: strings.themeEditorPreviewGitBadge,
                    tone: FrameStatusTone.warning,
                  ),
                ),
                // Chat turn: a user message above the assistant reply.
                Padding(
                  padding: const EdgeInsets.all(FrameSpace.x3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        strings.themeEditorPreviewUserTurn,
                        style: text.body.copyWith(color: tokens.textSecondary),
                      ),
                      const SizedBox(height: FrameSpace.x2),
                      Container(
                        padding: const EdgeInsets.all(FrameSpace.x3),
                        decoration: BoxDecoration(
                          color: tokens.surfaceElevated,
                          borderRadius: BorderRadius.circular(tokens.radiusMd),
                          border: Border.all(color: tokens.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              strings.themeEditorPreviewAssistantTurn,
                              style: text.bodyLarge.copyWith(color: tokens.textPrimary),
                            ),
                            const SizedBox(height: FrameSpace.x2),
                            Wrap(
                              spacing: FrameSpace.x2,
                              runSpacing: FrameSpace.x2,
                              children: [
                                FilledButton(
                                  onPressed: () {},
                                  child: Text(strings.themeEditorPreviewAccentBtn),
                                ),
                                OutlinedButton(
                                  onPressed: () {},
                                  child: Text(strings.themeEditorPreviewSecondaryBtn),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: FrameSpace.x2),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(FrameSpace.x2),
                        decoration: BoxDecoration(
                          color: tokens.surfaceElevated,
                          borderRadius: BorderRadius.circular(tokens.radiusSm),
                          border: Border.all(color: tokens.border),
                        ),
                        child: RichText(
                          text: TextSpan(
                            style: text.monoBody,
                            children: [
                              TextSpan(
                                text: strings.themeEditorPreviewCodeComment,
                                style: TextStyle(color: tokens.syntaxComment),
                              ),
                              TextSpan(
                                text: 'const ',
                                style: TextStyle(
                                  color: tokens.syntaxKeyword,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              TextSpan(
                                text: 'answer',
                                style: TextStyle(color: tokens.syntaxFunction),
                              ),
                              TextSpan(
                                text: ' = ',
                                style: TextStyle(color: tokens.textPrimary),
                              ),
                              TextSpan(
                                text: '"42"',
                                style: TextStyle(color: tokens.syntaxString),
                              ),
                              TextSpan(
                                text: ';',
                                style: TextStyle(color: tokens.textPrimary),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final strings = ref.watch(appStringsProvider);
    final repo = ref.watch(themeRepositoryProvider);
    final availableThemes = repo.availableThemes;

    return Dialog(
      backgroundColor: tokens.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusLg),
        side: BorderSide(color: tokens.borderStrong),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(Icons.tune_outlined, color: tokens.accent, size: FrameSize.iconLg),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          strings.themeEditorTitle,
                          style: TextStyle(
                            color: tokens.displayText,
                            fontSize: FrameText.fromTokens(tokens).heading.fontSize,
                            fontWeight: FontWeight.bold,
                            fontFamily: tokens.headingFontFamily,
                          ),
                        ),
                        Text(
                          strings.themeEditorSubtitle,
                          style: FrameText.fromTokens(tokens).label.copyWith(color: tokens.textMuted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_outlined, color: tokens.textMuted),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              Divider(height: 24, thickness: 1, color: tokens.border),

              // Controls: Base Theme selection & Theme Name
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(strings.baseThemeLabel, style: FrameText.fromTokens(tokens).label.copyWith(color: tokens.textSecondary)),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: tokens.surface,
                            borderRadius: BorderRadius.circular(tokens.radiusSm),
                            border: Border.all(color: tokens.border),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              key: const ValueKey('theme-editor-base-dropdown'),
                              isExpanded: true,
                              value: _selectedBaseThemeId,
                              dropdownColor: tokens.surfaceElevated,
                              style: FrameText.fromTokens(tokens).body.copyWith(color: tokens.textPrimary),
                              items: availableThemes.map((t) {
                                return DropdownMenuItem<String>(
                                  value: t.id,
                                  child: Text('${t.name} (${t.variant})'),
                                );
                              }).toList(),
                              onChanged: (id) {
                                if (id != null) {
                                  final selected = availableThemes.firstWhere((t) => t.id == id);
                                  _onBaseThemeChanged(selected);
                                }
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(strings.themeNameLabel, style: FrameText.fromTokens(tokens).label.copyWith(color: tokens.textSecondary)),
                        const SizedBox(height: 4),
                        TextField(
                          key: const ValueKey('theme-editor-name-input'),
                          controller: _nameController,
                          style: FrameText.fromTokens(tokens).body.copyWith(color: tokens.textPrimary),
                          decoration: InputDecoration(
                            hintText: strings.themeNameHint,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(strings.themeVariantLabel, style: FrameText.fromTokens(tokens).label.copyWith(color: tokens.textSecondary)),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: tokens.surface,
                            borderRadius: BorderRadius.circular(tokens.radiusSm),
                            border: Border.all(color: tokens.border),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              key: const ValueKey('theme-editor-variant-dropdown'),
                              isExpanded: true,
                              value: _variant,
                              dropdownColor: tokens.surfaceElevated,
                              style: FrameText.fromTokens(tokens).body.copyWith(color: tokens.textPrimary),
                              items: [
                                DropdownMenuItem(value: 'dark', child: Text(strings.variantDark)),
                                DropdownMenuItem(value: 'light', child: Text(strings.variantLight)),
                              ],
                              onChanged: (v) {
                                if (v != null) setState(() => _variant = v);
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Main customization body: split into editor lists on left, live preview on right
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Color Pickers List
                    Expanded(
                      flex: 6,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: tokens.surface.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(tokens.radiusMd),
                          border: Border.all(color: tokens.border),
                        ),
                        child: ListView(
                          children: [
                            FrameSearchField(
                              keyPrefix: 'theme-editor-token-search',
                              strings: strings,
                              controller: _tokenSearchController,
                              hintText: strings.themeEditorTokenSearchHint,
                              onChanged: (v) => setState(() => _tokenQuery = v),
                              onClear: () => setState(() => _tokenQuery = ''),
                            ),
                            const SizedBox(height: 8),
                            Text(strings.catSurfaces, style: FrameText.fromTokens(tokens).label.copyWith(color: tokens.accent)),
                            const SizedBox(height: 4),
                            _buildColorRow('background', strings.colorLabelBackground, tokens: tokens, fallback: tokens.background),
                            _buildColorRow('surface', strings.colorLabelSurface, tokens: tokens, fallback: tokens.surface),
                            _buildColorRow('surfaceElevated', strings.colorLabelSurfaceElevated, tokens: tokens, fallback: tokens.surfaceElevated),
                            _buildColorRow('border', strings.colorLabelBorder, tokens: tokens, fallback: tokens.border),
                            _buildColorRow('borderStrong', strings.colorLabelBorderStrong, tokens: tokens, fallback: tokens.borderStrong),

                            const SizedBox(height: 12),
                            Text(strings.catAccents, style: FrameText.fromTokens(tokens).label.copyWith(color: tokens.accent)),
                            const SizedBox(height: 4),
                            _buildColorRow('accent', strings.colorLabelAccent, tokens: tokens, fallback: tokens.accent),
                            _buildColorRow('accentContrast', strings.colorLabelAccentContrast, tokens: tokens, fallback: tokens.accentContrast),
                            _buildColorRow('focusRing', strings.colorLabelFocusRing, tokens: tokens, fallback: tokens.focusRing),

                            const SizedBox(height: 12),
                            Text(strings.catText, style: FrameText.fromTokens(tokens).label.copyWith(color: tokens.accent)),
                            const SizedBox(height: 4),
                            _buildColorRow('textPrimary', strings.colorLabelTextPrimary, tokens: tokens, fallback: tokens.textPrimary),
                            _buildColorRow('textSecondary', strings.colorLabelTextSecondary, tokens: tokens, fallback: tokens.textSecondary),
                            _buildColorRow('textMuted', strings.colorLabelTextMuted, tokens: tokens, fallback: tokens.textMuted),

                            const SizedBox(height: 12),
                            Text(strings.catAgent, style: FrameText.fromTokens(tokens).label.copyWith(color: tokens.accent)),
                            const SizedBox(height: 4),
                            _buildColorRow('agentWorking', strings.colorLabelAgentWorking, tokens: tokens, fallback: tokens.agentWorking),
                            _buildColorRow('agentSettled', strings.colorLabelAgentSettled, tokens: tokens, fallback: tokens.agentSettled),
                            _buildColorRow('agentRetrying', strings.colorLabelAgentRetrying, tokens: tokens, fallback: tokens.agentRetrying),
                            _buildColorRow('agentCompacting', strings.colorLabelAgentCompacting, tokens: tokens, fallback: tokens.agentCompacting),
                            _buildColorRow('danger', strings.colorLabelDanger, tokens: tokens, fallback: tokens.danger),

                            const SizedBox(height: 12),
                            Text(strings.catSyntax, style: FrameText.fromTokens(tokens).label.copyWith(color: tokens.accent)),
                            const SizedBox(height: 4),
                            _buildColorRow('keyword', strings.colorLabelKeyword, isSyntax: true, tokens: tokens, fallback: tokens.syntaxKeyword),
                            _buildColorRow('function', strings.colorLabelFunction, isSyntax: true, tokens: tokens, fallback: tokens.syntaxFunction),
                            _buildColorRow('string', strings.colorLabelString, isSyntax: true, tokens: tokens, fallback: tokens.syntaxString),
                            _buildColorRow('number', strings.colorLabelNumber, isSyntax: true, tokens: tokens, fallback: tokens.syntaxNumber),
                            _buildColorRow('comment', strings.colorLabelComment, isSyntax: true, tokens: tokens, fallback: tokens.syntaxComment),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),

                    // Live Preview Column
                    Expanded(
                      flex: 5,
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildLivePreview(tokens, strings),
                            if (_errorMessage != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                _errorMessage!,
                                style: FrameText.fromTokens(tokens).label.copyWith(color: tokens.danger),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
              // Footer Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(strings.cancel),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    key: const ValueKey('theme-editor-save-btn'),
                    onPressed: _isSaving ? null : _saveAndApplyTheme,
                    icon: _isSaving
                        ? FrameActivityIndicator(size: FrameSize.icon, strokeWidth: 2, color: tokens.accentContrast)
                        : const Icon(Icons.check_outlined, size: FrameSize.icon),
                    label: Text(strings.saveThemeAction),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
