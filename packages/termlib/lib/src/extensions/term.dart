import 'package:termansi/termansi.dart' as ansi;
import 'package:termlib/termlib.dart';
import 'package:termparser/termparser_events.dart';

/// Support function that add some extra features to the terminal.
extension TermUtils on TermLib {
  /// Write a hyperlink to the terminal.
  void hyperlink(String link, String name) => write(ansi.Term.hyperLink(link, name));

  /// Write a notification to the terminal.
  void notify(String title, String message) => write(ansi.Term.notify(title, message));

  /// Enable Alternate Screen
  void enableAlternateScreen() => write(ansi.Term.enableAlternateScreen);

  /// Disable Alternate Screen
  void disableAlternateScreen() => write(ansi.Term.disableAlternateScreen);

  /// Set Terminal Title
  void setTerminalTitle(String title) => write(ansi.Term.setTerminalTitle(title));

  /// Start receiving mouse events
  void enableMouseEvents() =>
      write(zellijMouseMotionQuirk ? ansi.Term.enableZellijMouseEvents : ansi.Term.enableMouseEvents);

  /// Stop receiving mouse events
  void disableMouseEvents() =>
      write(zellijMouseMotionQuirk ? ansi.Term.disableZellijMouseEvents : ansi.Term.disableMouseEvents);

  /// Start receiving focus events
  void startFocusTracking() => write(ansi.Term.enableFocusTracking);

  /// End receiving focus events
  void endFocusTracking() => write(ansi.Term.disableFocusTracking);

  /// Enabled Line Wrapping
  void enableLineWrapping() => write(ansi.Term.enableLineWrapping);

  /// Disabled Line Wrapping
  void disableLineWrapping() => write(ansi.Term.disableLineWrapping);

  /// Scroll the terminal up by the specified number of rows.
  void scrollUp(int rows) => write(ansi.Term.scrollUp(rows));

  /// Scroll the terminal down by the specified number of rows.
  void scrollDown(int rows) => write(ansi.Term.scrollDown(rows));

  /// Start synchronous update mode
  void startSyncUpdate() => write(ansi.Term.enableSyncUpdate);

  /// End synchronous update mode
  void endSyncUpdate() => write(ansi.Term.disableSyncUpdate);

  /// Query Sync status
  Future<SyncUpdateStatus?> querySyncUpdate() async {
    write(ansi.Term.querySyncUpdate);
    final event = await readEvent<QuerySyncUpdateEvent>();
    return (event is QuerySyncUpdateEvent) ? event.value : null;
  }

  /// Request terminal name and version
  Future<String> queryTerminalVersion() async {
    write(ansi.Term.requestTermVersion);
    final event = await readEvent<NameAndVersionEvent>();
    return (event is NameAndVersionEvent) ? event.value : '';
  }

  /// Returns the current terminal status report.
  Future<TrueColor?> queryOSCStatus(int status) async {
    return withRawModeAsync<TrueColor?>(() async {
      write(ansi.Term.queryOSCColors(status));
      final event = await readEvent<ColorQueryEvent>();
      return (event is ColorQueryEvent) ? TrueColor(event.r, event.g, event.b) : null;
    });
  }

  /// Query Keyboard enhancement support
  Future<bool> queryKeyboardEnhancementSupport() async {
    write(ansi.Term.queryKeyboardEnhancementSupport);
    final event = await readEvent<KeyboardEnhancementFlagsEvent>(timeout: 500);
    return event is KeyboardEnhancementFlagsEvent;
  }

  /// Query Primary Device Attributes
  Future<PrimaryDeviceAttributesEvent?> queryPrimaryDeviceAttributes() async {
    write(ansi.Term.queryPrimaryDeviceAttributes);
    final event = await readEvent<PrimaryDeviceAttributesEvent>(timeout: 500);
    return (event is PrimaryDeviceAttributesEvent) ? event : null;
  }
}
