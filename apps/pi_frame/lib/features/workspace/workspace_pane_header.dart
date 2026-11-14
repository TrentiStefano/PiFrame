import 'package:flutter/material.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../data/language/language_settings.dart';
import '../../data/language/strings_workspace.dart';
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
                          cursor: isActive
                              ? SystemMouseCursors.basic
                              : SystemMouseCursors.click,
                          child: GestureDetector(
                            key: ValueKey('companion-tab-${tab.name}'),
                            behavior: HitTestBehavior.opaque,
                            onTap: isActive
                                ? null
                                : () => onSelectCompanionTab?.call(tab),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 140),
                              padding: EdgeInsets.symmetric(
                                horizontal: isActive ? 10 : 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: isActive
                                    ? tokens.surface
                                    : tokens.surface.withValues(alpha: 0),
                                borderRadius: BorderRadius.circular(
                                  tokens.radiusSm,
                                ),
                                border: isActive
                                    ? Border.all(
                                        color: tokens.borderStrong,
                                        width: 1,
                                      )
                                    : null,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    tabIcon,
                                    size: isActive ? 14 : 13,
                                    color: isActive
                                        ? tokens.accent
                                        : tokens.textMuted,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    isActive
                                        ? tabTitle.toUpperCase()
                                        : tabTitle,
                                    style: TextStyle(
                                      color: isActive
                                          ? tokens.textPrimary
                                          : tokens.textMuted,
                                      fontSize: 11.5,
                                      fontFamily: tokens.uiFontFamily,
                                      fontWeight: isActive
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ],
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
          Icon(icon, size: 16, color: tokens.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                color: tokens.textPrimary,
                fontSize: 11.5,
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
