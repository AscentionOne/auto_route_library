part of 'routing_controller.dart';

class AutoRouterDelegate extends RouterDelegate<UrlState> with ChangeNotifier {
  final List<PageRouteInfo>? initialRoutes;
  final StackRouter controller;
  final String? initialDeepLink;
  final String? navRestorationScopeId;
  final NavigatorObserversBuilder navigatorObservers;

  /// A builder for the placeholder page that is shown
  /// before the first route can be rendered. Defaults to
  /// an empty page with [Theme.scaffoldBackgroundColor].
  WidgetBuilder? placeholder;

  static List<NavigatorObserver> defaultNavigatorObserversBuilder() => const [];

  static AutoRouterDelegate of(BuildContext context) {
    final delegate = Router.of(context).routerDelegate;
    assert(delegate is AutoRouterDelegate);
    return delegate as AutoRouterDelegate;
  }

  static reportUrlChanged(BuildContext context, String url) {
    Router.of(context)
        .routeInformationProvider
        ?.routerReportsNewRouteInformation(
          RouteInformation(
            location: url,
          ),
          type: RouteInformationReportingType.navigate, // added line
        );
  }

  @override
  Future<bool> popRoute() => controller.topMostRouter().pop();

  late List<NavigatorObserver> _navigatorObservers;

  AutoRouterDelegate(
    this.controller, {
    this.initialRoutes,
    this.placeholder,
    this.navRestorationScopeId,
    this.initialDeepLink,
    this.navigatorObservers = defaultNavigatorObserversBuilder,
  }) : assert(initialDeepLink == null || initialRoutes == null) {
    _navigatorObservers = navigatorObservers();
    controller.navigationHistory.addListener(_handleRebuild);
  }

  factory AutoRouterDelegate.declarative(
    RootStackRouter controller, {
    required RoutesBuilder routes,
    String? navRestorationScopeId,
    RoutePopCallBack? onPopRoute,
    OnNavigateCallBack? onNavigate,
    NavigatorObserversBuilder navigatorObservers,
  }) = _DeclarativeAutoRouterDelegate;

  UrlState get urlState => controller.navigationHistory.urlState;

  @override
  UrlState? get currentConfiguration => urlState;

  @override
  Future<void> setInitialRoutePath(UrlState state) {
    // setInitialRoutePath is re-fired on enabling
    // select widget mode from flutter inspector,
    // this check is preventing it from rebuilding the app
    if (controller.hasEntries) {
      return SynchronousFuture(null);
    }

    if (initialRoutes?.isNotEmpty == true) {
      return controller.pushAll(initialRoutes!);
    } else if (initialDeepLink != null) {
      return controller.pushNamed(initialDeepLink!, includePrefixMatches: true);
    } else if (state.hasSegments) {
      _onNewUrlState(state);
      return controller.navigateAll(state.segments);
    } else {
      throw FlutterError("Can not resolve initial route");
    }
  }

  @override
  Future<void> setNewRoutePath(UrlState state) {
    final topMost = controller.topMostRouter();
    if (topMost is StackRouter && topMost.hasPagelessTopRoute) {
      topMost.popUntil((route) => route.settings is Page);
    }

    if (state.hasSegments) {
      _onNewUrlState(state);
      return controller.navigateAll(state.segments);
    }

    notifyListeners();
    return SynchronousFuture(null);
  }

  void _onNewUrlState(UrlState state) {
    final pathInBrowser = state.uri.path;
    var matchedUrlState = state.flatten;
    if (pathInBrowser != matchedUrlState.path) {
      matchedUrlState = matchedUrlState.copyWith(replace: true);
    }
    controller.navigationHistory._onNewUrlState(matchedUrlState);
  }

  @override
  Widget build(BuildContext context) => _AutoRootRouter(
        router: controller,
        navigatorObservers: _navigatorObservers,
        navigatorObserversBuilder: navigatorObservers,
        navRestorationScopeId: navRestorationScopeId,
        placeholder: placeholder,
      );

  void _handleRebuild() {
    notifyListeners();
  }

  @override
  void dispose() {
    super.dispose();
    removeListener(_handleRebuild);
    controller.dispose();
  }

  void notifyUrlChanged() => _handleRebuild();
}

class _AutoRootRouter extends StatefulWidget {
  _AutoRootRouter({
    Key? key,
    required this.router,
    this.navRestorationScopeId,
    this.navigatorObservers = const [],
    required this.navigatorObserversBuilder,
    this.placeholder,
  }) : super(key: key);
  final StackRouter router;
  final String? navRestorationScopeId;
  final List<NavigatorObserver> navigatorObservers;
  final NavigatorObserversBuilder navigatorObserversBuilder;

  /// A builder for the placeholder page that is shown
  /// before the first route can be rendered. Defaults to
  /// an empty page with [Theme.scaffoldBackgroundColor].
  final WidgetBuilder? placeholder;

  @override
  _AutoRootRouterState createState() => _AutoRootRouterState();
}

class _AutoRootRouterState extends State<_AutoRootRouter> {
  StackRouter get router => widget.router;

  @override
  void initState() {
    super.initState();
    router.addListener(_handleRebuild);
  }

  @override
  void dispose() {
    super.dispose();
    router.removeListener(_handleRebuild);
  }

  void _handleRebuild() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final stateHash = router.stateHash;
    return RouterScope(
      controller: router,
      navigatorObservers: widget.navigatorObservers,
      inheritableObserversBuilder: widget.navigatorObserversBuilder,
      stateHash: stateHash,
      child: StackRouterScope(
        stateHash: stateHash,
        controller: router,
        child: AutoRouteNavigator(
          router: router,
          placeholder: widget.placeholder,
          navRestorationScopeId: widget.navRestorationScopeId,
          navigatorObservers: widget.navigatorObservers,
        ),
      ),
    );
  }
}

class _DeclarativeAutoRouterDelegate extends AutoRouterDelegate {
  final RoutesBuilder routes;
  final RoutePopCallBack? onPopRoute;
  final OnNavigateCallBack? onNavigate;

  _DeclarativeAutoRouterDelegate(
    RootStackRouter router, {
    required this.routes,
    String? navRestorationScopeId,
    this.onPopRoute,
    this.onNavigate,
    NavigatorObserversBuilder navigatorObservers =
        AutoRouterDelegate.defaultNavigatorObserversBuilder,
  }) : super(
          router,
          navRestorationScopeId: navRestorationScopeId,
          navigatorObservers: navigatorObservers,
        ) {
    router._managedByWidget = true;
  }

  @override
  Future<void> setInitialRoutePath(UrlState tree) {
    return _onNavigate(tree, true);
  }

  @override
  Future<void> setNewRoutePath(UrlState tree) async {
    return _onNavigate(tree);
  }

  Future<void> _onNavigate(UrlState tree, [bool initial = false]) {
    if (tree.hasSegments) {
      controller.navigateAll(tree.segments);
    }
    if (onNavigate != null) {
      onNavigate!(tree, true);
    }

    return SynchronousFuture(null);
  }

  @override
  Widget build(BuildContext context) {
    final stateHash = controller.stateHash;
    return RouterScope(
      controller: controller,
      inheritableObserversBuilder: navigatorObservers,
      stateHash: stateHash,
      navigatorObservers: _navigatorObservers,
      child: StackRouterScope(
        controller: controller,
        stateHash: stateHash,
        child: AutoRouteNavigator(
          router: controller,
          declarativeRoutesBuilder: routes,
          navRestorationScopeId: navRestorationScopeId,
          navigatorObservers: _navigatorObservers,
          didPop: onPopRoute,
        ),
      ),
    );
  }
}

class SimpleRouterDelegate extends RouterDelegate with ChangeNotifier {
  final WidgetBuilder builder;

  SimpleRouterDelegate(this.builder);

  @override
  Widget build(BuildContext context) {
    return builder(context);
  }

  @override
  Future<bool> popRoute() {
    return SynchronousFuture(false);
  }

  @override
  Future<void> setNewRoutePath(configuration) {
    throw UnimplementedError();
  }
}
