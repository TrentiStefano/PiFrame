import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'language_settings.dart';

/// Extension on [AppStrings] providing localized strings for the transcript and tool timeline features.
extension TranscriptStrings on AppStrings {
  // Tool card
  String get toolCardExecutedCommand =>
      isItalian ? 'Comando lanciato' : 'Executed command';
  String get toolCardCommandParams =>
      isItalian ? 'Parametri comando' : 'Command parameters';
  String toolCardRequestedTimeout(String timeout) =>
      isItalian ? 'Timeout richiesto: $timeout' : 'Requested timeout: $timeout';
  String get toolCardCopiedToClipboard =>
      isItalian ? 'Comando copiato negli appunti' : 'Command copied to clipboard';
  String get toolCardCopyCommand =>
      isItalian ? 'Copia comando' : 'Copy command';

  // Chat drop target
  String get dropTargetTitle =>
      isItalian ? 'Rilascia i file qui per allegarli' : 'Drop files here to attach';
  String get dropTargetSubtitle => isItalian
      ? 'Supporta file del repository, file locali e immagini'
      : 'Supports repository files, local files, and images';

  // Rich content
  String get richContentOpenFileTooltip => isItalian
      ? 'CTRL+clic per aprire in esplora file'
      : 'Ctrl+Click to open in File Explorer';

  // Thinking block
  String get transcriptReasoning => isItalian ? 'Ragionamento' : 'Reasoning';
  String transcriptWordsCount(int words) => isItalian
      ? '$words parole'
      : (words == 1 ? '1 word' : '$words words');

  // Task notification card
  String get taskNotifSubagentNotification =>
      isItalian ? 'Notifica subagente' : 'Subagent Notification';
  String taskNotifContextPercent(int pct) =>
      isItalian ? '$pct% contesto' : '$pct% context';
  String get taskNotifOperationResult =>
      isItalian ? 'Risultato operazione' : 'Operation result';
  String get taskNotifOpenFullTranscript =>
      isItalian ? 'Apri trascrizione completa' : 'Open full transcript';

  // Todo panel & provider
  String get todoAgentTasksTitle =>
      isItalian ? 'Task agente' : 'Agent Tasks (Todo)';
  String todoCompletedCount(int completed, int total) =>
      isItalian ? '$completed / $total completati' : '$completed / $total completed';
  String todoInProgressCount(int inProgress) =>
      isItalian ? '$inProgress in corso' : '$inProgress in progress';
  String get todoAddTaskTooltip => isItalian ? 'Aggiungi task' : 'Add task';
  String get todoCancelTooltip => isItalian ? 'Annulla' : 'Cancel';
  String get todoHideTasksTooltip =>
      isItalian ? 'Nascondi attività' : 'Hide tasks';
  String get todoAddTaskHint =>
      isItalian ? 'Aggiungi task e premi Invio...' : 'Add task and press Enter...';
  String get todoAddButton => isItalian ? 'Aggiungi' : 'Add';
  String get todoNoTasksYet => isItalian
      ? 'Nessun task ancora pianificato per questa sessione.'
      : 'No tasks planned for this session yet.';
  String get todoNoDetailedDescription => isItalian
      ? 'Nessuna descrizione dettagliata disponibile per questo task.'
      : 'No detailed description available for this task.';
  String todoPeekTab(int completed, int total) =>
      isItalian ? 'Attività ($completed/$total)' : 'Tasks ($completed/$total)';
  String get todoBadgeCompleted => isItalian ? 'COMPLETATO' : 'COMPLETED';
  String get todoBadgeInProgress => isItalian ? 'IN CORSO' : 'IN PROGRESS';
  String get todoBadgePending => isItalian ? 'IN ATTESA' : 'PENDING';
  String todoNewTaskSubject(int id) =>
      isItalian ? 'Nuovo task #$id' : 'New task #$id';
  String todoSteerPrompt(int id, String subject, String verb) => isItalian
      ? 'Nota utente: il task #$id "$subject" è stato contrassegnato come $verb.'
      : 'User note: task #$id "$subject" has been marked as $verb.';
  String get todoVerbCompleted => isItalian ? 'completato' : 'completed';
  String get todoVerbPending =>
      isItalian ? 'da fare (pending)' : 'pending';

  // Subagents & Workflows panel
  String subagentsStripActive(int count) =>
      isItalian ? 'AGENTI · $count ATTIVI' : 'AGENTS · $count ACTIVE';
  String get subagentsStripIdle => isItalian ? 'AGENTI' : 'AGENTS';
  String get subagentsPanelTitle => isItalian ? 'Agenti' : 'Agents';
  String get subagentsPartialCostPrefix => isItalian ? 'Parziale ' : 'Partial ';
  String subagentsRunningCount(int count) =>
      isItalian ? '$count in esecuzione' : '$count running';
  String get subagentsCloseTooltip =>
      isItalian ? 'Chiudi pannello agenti' : 'Close agents panel';
  String get subagentStatusInProgress => isItalian ? 'In corso' : 'In progress';
  String get subagentStatusError => isItalian ? 'Errore' : 'Error';
  String get subagentStatusStopped => isItalian ? 'Fermato' : 'Stopped';
  String get subagentStatusCompleted => isItalian ? 'Completato' : 'Completed';
  String get subagentStatusSteered => isItalian ? 'Guidato' : 'Steered';
  String get subagentMainSession =>
      isItalian ? 'Sessione principale' : 'Main session';
  String subagentsCount(int count) =>
      isItalian ? '$count agenti' : (count == 1 ? '1 agent' : '$count agents');
  String get subagentsAllIdle => isItalian ? 'tutti fermi' : 'all idle';
  String subagentsWorking(int count) =>
      isItalian ? '$count al lavoro' : '$count working';
  String subagentsFinishedWorking(int done, int total, int working) => isItalian
      ? '$done/$total agenti finiti${working > 0 ? ' · $working al lavoro' : ''}'
      : '$done/$total agents finished${working > 0 ? ' · $working working' : ''}';
  String get workflowStarting => isItalian ? 'In avvio…' : 'Starting…';
  String get transcriptNotAvailable => isItalian ? 'N/D' : 'N/A';
  String workflowJournalAgent(int index, String text) => isItalian
      ? 'Agente #${index + 1}${text.isEmpty ? '' : ': $text'}'
      : 'Agent #${index + 1}${text.isEmpty ? '' : ': $text'}';
  String get workflowWaitingFirstAgent =>
      isItalian ? 'In attesa del primo agente…' : 'Waiting for the first agent…';
  String get workflowNoResultsRecorded =>
      isItalian ? 'Nessun risultato registrato.' : 'No results recorded.';
  String get subagentSteerClose => isItalian ? 'Chiudi guida' : 'Close steering';
  String get subagentSteer => isItalian ? 'Guida' : 'Steer';
  String get subagentStop => isItalian ? 'Interrompi' : 'Stop';
  String get subagentFinished => isItalian ? 'Terminato' : 'Finished';
  String get subagentSteerInputHint =>
      isItalian ? 'Nuova istruzione per l\'agente…' : 'New instruction for agent…';
  String get subagentWorkingOutput =>
      isItalian ? 'L\'agente sta lavorando…' : 'The agent is working…';
  String get subagentNoOutputRecorded =>
      isItalian ? 'Nessun output registrato.' : 'No output recorded.';
  String get subagentManualSteeringTitle =>
      isItalian ? 'Guida manuale subagente' : 'Manual subagent steering';
  String get subagentManualSteeringHint => isItalian
      ? 'Invia istruzioni per guidare il subagente...'
      : 'Send instructions to steer the subagent...';
  String get subagentSendButton => isItalian ? 'Invia' : 'Send';
  String subagentWaitingWithTask(String desc) => isItalian
      ? 'Attività: $desc\n\nIn attesa di output dal subagente...'
      : 'Task: $desc\n\nWaiting for subagent output...';
  String get subagentWaitingOutput => isItalian
      ? 'In attesa di output dal subagente...'
      : 'Waiting for subagent output...';
  String subagentCompletedWithTask(String desc) => isItalian
      ? 'Attività: $desc\n\nCompletato.'
      : 'Task: $desc\n\nCompleted.';
  String get subagentNoOutputForThis => isItalian
      ? 'Nessun output registrato per questo subagente.'
      : 'No output recorded for this subagent.';
  String get subagentDefaultName => isItalian ? 'Subagente' : 'Subagent';
  String subagentSteeringNote(String text) =>
      isItalian ? '[Guida utente]: $text' : '[User steer]: $text';
  String get subagentStoppedNote =>
      isItalian ? '[Interrotto dall\'utente]' : '[Stopped by user]';

  // Steps group
  String get stepsGroupInputCopied =>
      isItalian ? 'Input copiato' : 'Input copied';
  String get stepsGroupOutputCopied =>
      isItalian ? 'Output copiato' : 'Output copied';
  String get stepsGroupCopy => isItalian ? 'Copia' : 'Copy';

  // Transcript view
  String transcriptRenameError(String e) =>
      isItalian ? 'Errore durante la rinomina: $e' : 'Error renaming session: $e';
  String get transcriptNotification => isItalian ? 'Notifica' : 'Notification';
  String get transcriptContextTokensTitle =>
      isItalian ? 'Contesto & Token' : 'Context & Tokens';
  String get transcriptUsageLabel => isItalian ? 'Utilizzo:' : 'Usage:';
  String get transcriptTokenInput =>
      isItalian ? 'Token input' : 'Input Tokens';
  String get transcriptTokenOutput =>
      isItalian ? 'Token output' : 'Output Tokens';
  String get transcriptTokenCache =>
      isItalian ? 'Token cache' : 'Cache Tokens';
  String get transcriptEstimatedCost =>
      isItalian ? 'Costo stimato' : 'Estimated Cost';
  String get transcriptCompacting =>
      isItalian ? 'Compattazione...' : 'Compacting...';
  String get transcriptCompactContext =>
      isItalian ? 'Compatta contesto' : 'Compact Context';
  String get transcriptCompactionCompleted =>
      isItalian ? 'Compattazione completata!' : 'Compaction completed!';
  String transcriptCompactionError(String e) =>
      isItalian ? 'Errore compattazione: $e' : 'Compaction error: $e';
  String get transcriptAgentModelCosts =>
      isItalian ? 'Costi modelli agente' : 'Agent Model Costs';
  String get transcriptCostReportedByPi =>
      isItalian ? 'Costo riportato da Pi' : 'Cost reported by Pi';
  String get transcriptModelCostsUnavailable =>
      isItalian ? 'Costi per modello non disponibili' : 'Costs per model unavailable';
  String get transcriptSubagentModelCosts =>
      isItalian ? 'Costi subagenti & modelli' : 'Subagent & Model Costs';
  String transcriptChildSessionCosts(int count) => isItalian
      ? 'Costi sessioni figlie ($count agenti)'
      : 'Child session costs ($count agents)';
  String get transcriptNoSubagentsExecuted =>
      isItalian ? 'Nessun subagente eseguito.' : 'No subagents executed.';
  String transcriptUnattributedChildSession(
          String name, String model, String cost) =>
      isItalian
          ? 'Sessione figlia non attribuita: $name · $model · $cost'
          : 'Unattributed child session: $name · $model · $cost';
  String transcriptSubagentNumbered(int n) =>
      isItalian ? 'Subagente #$n' : 'Subagent #$n';
  String get transcriptSessionCostBreakdown =>
      isItalian ? 'Dettaglio costi sessione' : 'Session Cost Breakdown';
  String get transcriptPiCostDisclaimer => isItalian
      ? 'Il costo Pi può già includere i subagenti. Le cifre non vengono sommate.'
      : 'Pi cost may already include subagents. Values are not summed.';
  String get transcriptPiSession => isItalian ? 'Sessione Pi' : 'Pi Session';
  String get transcriptSessionModel =>
      isItalian ? 'Modello sessione' : 'Session model';
  String get transcriptSubagents => isItalian ? 'Subagenti' : 'Subagents';
  String transcriptIdentifiedSubagents(int count) => isItalian
      ? '$count subagenti identificati'
      : '$count subagents identified';
  String get transcriptUnavailable =>
      isItalian ? 'non disponibile' : 'unavailable';
  String get transcriptPostCompaction =>
      isItalian ? 'post-compattazione' : 'post-compaction';
  String get transcriptSaveTooltip => isItalian ? 'Salva' : 'Save';
  String get transcriptCancelTooltip => isItalian ? 'Annulla' : 'Cancel';
  String get transcriptDoubleClickToRename =>
      isItalian ? 'Doppio clic per rinominare' : 'Double click to rename';
  String get transcriptNoFolderOpened =>
      isItalian ? 'Nessuna cartella aperta' : 'No folder opened';
  String get transcriptContext => isItalian ? 'Contesto' : 'Context';
  String get transcriptCost => isItalian ? 'Costo' : 'Cost';
  String get transcriptProcessing =>
      isItalian ? 'Elaborazione in corso...' : 'Processing...';
  String get transcriptForkCancelledByExtension => isItalian
      ? 'Fork annullato dall\'extension'
      : 'Fork cancelled by extension';
  String transcriptNewBranchStarted(String sid) =>
      isItalian ? 'Nuovo ramo avviato: $sid' : 'New branch started: $sid';
  String transcriptForkError(String e) =>
      isItalian ? 'Errore fork: $e' : 'Fork error: $e';
  String get transcriptYou => isItalian ? 'Tu' : 'You';
  String get transcriptRestartFromHere =>
      isItalian ? 'Riparti da qui' : 'Restart from here';
  String transcriptSendFailed(String err) =>
      isItalian ? 'Invio non riuscito: $err' : 'Send failed: $err';
  String transcriptTurnFailed(String err) =>
      isItalian ? 'Risposta interrotta da un errore: $err' : 'Reply stopped by an error: $err';
  String get transcriptRetrySend => isItalian ? 'Riprova invio' : 'Retry send';
  String get transcriptAssistant => isItalian ? 'Assistente' : 'Assistant';
  String get transcriptCopyMessage =>
      isItalian ? 'Copia messaggio' : 'Copy message';
  String get transcriptMessageCopied => isItalian
      ? 'Messaggio copiato negli appunti'
      : 'Message copied to clipboard';
  String get transcriptCancelledBadge =>
      isItalian ? 'annullato' : 'cancelled';
  String get transcriptCopyOutput => isItalian ? 'Copia output' : 'Copy output';
  String get transcriptOutputCopied =>
      isItalian ? 'Output copiato' : 'Output copied';
  String get transcriptPartialOutputTruncated =>
      isItalian ? 'Output parziale (troncato)' : 'Partial output (truncated)';
  String transcriptBranchCreatedFrom(String from) =>
      isItalian ? 'Diramazione creata da $from' : 'Branch created from $from';
  String get transcriptContextCompacted =>
      isItalian ? 'Contesto compattato' : 'Context compacted';
  String transcriptInitialTokens(num tokens) =>
      isItalian ? '$tokens token iniziali' : '$tokens initial tokens';
  String get transcriptCustomTypeDefault =>
      isItalian ? 'Estensione' : 'Extension';
}

/// Resolves [AppStrings] safely, falling back to Italian if no [ProviderScope] exists.
AppStrings safeTranscriptStrings(BuildContext context) {
  final hasScope =
      context.findAncestorWidgetOfExactType<UncontrolledProviderScope>() != null;
  if (hasScope) {
    try {
      return ProviderScope.containerOf(context, listen: false)
          .read(appStringsProvider);
    } catch (_) {}
  }
  return const AppStrings(AppLanguage.it);
}
