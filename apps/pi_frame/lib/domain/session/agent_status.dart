enum AgentStatus {
  idle,
  working,
  retrying,
  compacting,
  awaitingUser,
  settled,
  error,
  workerError,
}

extension AgentStatusExtension on AgentStatus {
  String get label {
    switch (this) {
      case AgentStatus.idle:
        return 'Inattivo';
      case AgentStatus.working:
        return 'In esecuzione';
      case AgentStatus.retrying:
        return 'Nuovo tentativo...';
      case AgentStatus.compacting:
        return 'Compattazione...';
      case AgentStatus.awaitingUser:
        return 'In attesa di input';
      case AgentStatus.settled:
        return 'Completato';
      case AgentStatus.error:
        return 'Errore';
      case AgentStatus.workerError:
        return 'Worker arrestato';
    }
  }
}
