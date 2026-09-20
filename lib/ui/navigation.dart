import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Sentinel distinguishing "leave [ChromeController.onBack] unchanged" from
/// "explicitly clear it back to the default pop" in [updateScreenChrome]/
/// [ChromeController.update].
const Object _unset = Object();

/// What the global [AppTitleBar] (see `widgets/app_title_bar.dart`) shows
/// for one screen -- attached to a pushed route's [RouteSettings.arguments]
/// by [pushScreen]/[pushReplacementScreen], and read back by
/// [ChromeRouteObserver] whenever the Navigator's current route changes.
class ScreenChrome {
  const ScreenChrome(this.title, {this.showBackButton = true, this.onBack});

  final String title;
  final bool showBackButton;

  /// Overrides the default `navigatorKey.currentState?.pop()` -- needed by
  /// a screen whose "back" resets its own internal state instead of
  /// popping the route (see `LoadSavedGameScreen`, which uses
  /// [updateScreenChrome] rather than this, since its back button's
  /// behavior changes without ever pushing a new route).
  final VoidCallback? onBack;
}

/// The single source of truth [AppTitleBar] renders from -- provided once,
/// app-wide, alongside `ThemeModeController` (see main.dart). Kept in sync
/// with the Navigator's current route by [ChromeRouteObserver]; a screen
/// whose chrome changes without a route push calls [updateScreenChrome]
/// instead, which updates this directly.
class ChromeController extends ChangeNotifier {
  String title = 'Cardflux';
  bool showBackButton = false;
  VoidCallback? onBack;

  void apply(ScreenChrome chrome) {
    title = chrome.title;
    showBackButton = chrome.showBackButton;
    onBack = chrome.onBack;
    notifyListeners();
  }

  /// Back to `HomeScreen`'s own chrome -- used whenever the Navigator's
  /// current route carries no [ScreenChrome] of its own (the initial
  /// `home:` route, or any route this app forgot to attach one to).
  void reset() => apply(const ScreenChrome('Cardflux', showBackButton: false));

  void update({String? title, bool? showBackButton, Object? onBack = _unset}) {
    if (title != null) this.title = title;
    if (showBackButton != null) this.showBackButton = showBackButton;
    if (!identical(onBack, _unset)) this.onBack = onBack as VoidCallback?;
    notifyListeners();
  }
}

/// Keeps [ChromeController] in sync with whatever the Navigator's current
/// route is -- reads [ScreenChrome] off [Route.settings.arguments] on every
/// push/pop/replace, falling back to [ChromeController.reset] for a route
/// that doesn't carry one (i.e. `HomeScreen`'s own `home:` route).
class ChromeRouteObserver extends NavigatorObserver {
  ChromeRouteObserver(this._controller);

  final ChromeController _controller;

  void _applyFor(Route<dynamic>? route) {
    final args = route?.settings.arguments;
    if (args is ScreenChrome) {
      _controller.apply(args);
    } else {
      _controller.reset();
    }
  }

  /// `showDialog`/`showMenu` push a route onto this same Navigator too (a
  /// `DialogRoute`/popup menu route, both [PopupRoute]s, never a
  /// [PageRoute]) -- opening/closing one must never touch the persistent
  /// title bar's chrome, so every callback below ignores anything that
  /// isn't a full-screen [PageRoute].
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) _applyFor(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) _applyFor(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute is PageRoute) _applyFor(newRoute);
  }
}

/// Pushes [builder] as a new screen, attaching a [ScreenChrome] so the
/// global title bar shows [title] (and a working back button, unless
/// [showBackButton] is false -- e.g. once gameplay starts, so a stray click
/// can't pop the route out from under a live match; see the Escape ->
/// Game Menu -> Leave Game flow in `table_screen.dart` instead).
Future<T?> pushScreen<T>(
  BuildContext context, {
  required String title,
  bool showBackButton = true,
  required WidgetBuilder builder,
}) {
  return Navigator.of(context).push<T>(
    MaterialPageRoute(
      builder: builder,
      settings: RouteSettings(arguments: ScreenChrome(title, showBackButton: showBackButton)),
    ),
  );
}

/// [pushScreen], but replacing the current route ([Navigator.pushReplacement]).
Future<T?> pushReplacementScreen<T, TO>(
  BuildContext context, {
  required String title,
  bool showBackButton = true,
  required WidgetBuilder builder,
  TO? result,
}) {
  return Navigator.of(context).pushReplacement<T, TO>(
    MaterialPageRoute(
      builder: builder,
      settings: RouteSettings(arguments: ScreenChrome(title, showBackButton: showBackButton)),
    ),
    result: result,
  );
}

/// Pushes [builder] and clears the whole stack back to it -- used by every
/// "return to the home screen" call site. Always `'Cardflux'`/no back
/// button, matching `HomeScreen`'s own default chrome.
Future<T?> pushAndRemoveUntilHome<T>(BuildContext context, WidgetBuilder builder) {
  return Navigator.of(context).pushAndRemoveUntil<T>(
    MaterialPageRoute(
      builder: builder,
      settings: const RouteSettings(arguments: ScreenChrome('Cardflux', showBackButton: false)),
    ),
    (route) => false,
  );
}

/// For a screen whose title/back-button state changes without pushing a new
/// route (`LoadSavedGameScreen`'s game-picked/not-picked states,
/// `PracticeLoadDecksScreen`'s current seat, `ClientGameScreen`'s
/// load-progress) -- updates [ChromeController] directly. Omit [onBack] to
/// leave it unchanged; pass `null` explicitly to clear it back to the
/// default pop.
void updateScreenChrome(
  BuildContext context, {
  String? title,
  bool? showBackButton,
  Object? onBack = _unset,
}) {
  context.read<ChromeController>().update(title: title, showBackButton: showBackButton, onBack: onBack);
}
