enum AppFailureKind {
  authentication,
  network,
  permission,
  configuration,
  unknown,
}

class AppFailure {
  const AppFailure(this.kind, this.safeMessage);
  final AppFailureKind kind;
  final String safeMessage;
}
