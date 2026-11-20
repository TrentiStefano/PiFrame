import 'package:flutter/material.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../data/language/language_settings.dart';
import '../../data/language/strings_workspace.dart';
import '../../ui/motion.dart';
import 'workspace_pane.dart';

/// Localized labels for the companion tabs shown in a workspace pane header.
Map<WorkspacePane, String> workspaceCompanionTabLabels(AppStrings strings) => {
  WorkspacePane.repository: strings.filePaneLabel,
  WorkspacePane.git: strings.gitChangesLabel,
  WorkspacePane.chat: strings.chatPaneLabel,
};

Widget workspacePaneHeader(
  BuildContext context,
  String title,
  IconData icon, {
  Widget? trailing,
  Widget? titleWidget,
  List<WorkspacePane>? companionTabs,
  WorkspacePane? activeCompanionTab,
  ValueChanged<WorkspacePane>? onSelectCompanionTab,
  required Map<WorkspacePane, String> companionTabLabels,
}) {
  final tokens = context.tokens;
  final hasTabs = companionTabs != null && companionTabs.length > 1;
  final decoration = BoxDecoration(
    color: tokens.surfaceElevated,
    borderRadius: BorderRadius.circular(tokens.radiusMd),
    border: Border.all(color: tokens.borderStrong),
  );

  // A plain title with actions: on a narrow pane the actions move to a second
  // line, so the title stays readable and every button stays reachable.
  if (!hasTabs && titleWidget == null && trailing != null) {
    final titleStyle = FrameText.of(context).label.copyWith(
      color: tokens.textPrimary,
      fontFamily: tokens.uiFontFamily,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.4,
    );
    return Container(
      key: const ValueKey('workspace-pane-header'),
      constraints: const BoxConstraints(minHeight: 38),
      margin: const EdgeInsets.fromLTRB(8, 6, 8, 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: decoration,
      child: LayoutBuilder(
        builder: (context, constraints) => Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: FrameSpace.x2,
          runSpacing: FrameSpace.x1,
          children: [
            ConstrainedBox(
              // Only the title shortens, and only when it cannot fit alone.
              constraints: BoxConstraints(minHeight: 28, maxWidth: constraints.maxWidth),
              child: Row(
                key: const ValueKey('workspace-pane-header-title'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: FrameSize.icon, color: tokens.accent),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      title.toUpperCase(),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: titleStyle,
                    ),
                  ),
                ],
              ),
            ),
            // On its own line the action row scrolls if even that is too
            // narrow, so every button stays reachable.
            ConstrainedBox(
              key: const ValueKey('workspace-pane-header-actions'),
              constraints: BoxConstraints(maxWidth: constraints.maxWidth),
              child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: trailing),
            ),
          ],
        ),
      ),
    );
  }

  return Container(
    height: 38,
    margin: const EdgeInsets.fromLTRB(8, 6, 8, 4),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: tokens.surfaceElevated,
      borderRadius: BorderRadius.circular(tokens.radiusMd),
      border: Border.all(color: tokens.borderStrong),
    ),
    child: Row(
      children: [
        if (hasTabs)
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final tab in companionTabs) ...[
                    Builder(
                      builder: (context) {
                        final isActive = tab == activeCompanionTab;
                        final tabTitle = companionTabLabels[tab]!;
                        final tabIcon = switch (tab) {
                          WorkspacePane.repository => Icons.folder_outlined,
                          WorkspacePane.git => Icons.source_outlined,
                          WorkspacePane.chat => Icons.chat_bubble_outline,
                        };
                        return MouseRegion(
                          cursor: isActive ? SystemMouseCursors.basic : SystemMouseCursors.click,
                          child: Semantics(
                            button: true,
                            selected: isActive,
                            label: tabTitle,
                            child: InkWell(
                              key: ValueKey('companion-tab-${tab.name}'),
                              borderRadius: BorderRadius.circular(tokens.radiusSm),
                              onTap: isActive ? null : () => onSelectCompanionTab?.call(tab),
                              child: AnimatedContainer(
                                duration: FrameMotion.fade(context, FrameMotion.micro),
                                padding: EdgeInsets.symmetric(horizontal: isActive ? 10 : 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isActive ? tokens.surface : tokens.surface.withValues(alpha: 0),
                                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                                  // Selected tab: a 2 px accent underline (10.3).
                                  border: isActive ? Border(bottom: BorderSide(color: tokens.accent, width: 2)) : null,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      tabIcon,
                                      size: isActive ? 14 : 13,
                                      color: isActive ? tokens.accent : tokens.textMuted,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      isActive ? tabTitle.toUpperCase() : tabTitle,
                                      style: FrameText.of(context).label.copyWith(
                                        color: isActive ? tokens.accent : tokens.textMuted,
                                        fontFamily: tokens.uiFontFamily,
                                        fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 4),
                  ],
                ],
              ),
            ),
          )
        else if (titleWidget != null) ...[
          Expanded(child: titleWidget),
        ] else ...[
          Icon(icon, size: FrameSize.icon, color: tokens.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: FrameText.of(context).label.copyWith(
                color: tokens.textPrimary,
                fontFamily: tokens.uiFontFamily,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ],
        ?trailing,
      ],
    ),
  );
}
