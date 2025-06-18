// ignore_for_file: library_private_types_in_public_api, unnecessary_import, avoid_print

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:intl/intl.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:simple_animations/simple_animations.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart'; // Using FontAwesome

// --- Project Imports ---
// (Ensure these paths are accurate for your project structure)
import '../models/worker.dart';
import '../models/job.dart';
import '../models/user.dart'; // ** NEEDS 'profileComplete' field **
import '../services/firebase_service.dart';
import '../services/auth_service.dart';
import 'worker_detail_screen.dart';
import 'jobs/create_job_screen.dart';
import 'jobs/job_detail_screen.dart';
import 'notifications_screen.dart';
import 'job_history_screen.dart';
import 'professional_setup_screen.dart';

// ================================================
// ==          CORE CONFIG & CONSTANTS           ==
// ================================================

// --- Theme Constants ---
const Color kCyberBackgroundDeep = Color(0xFF03100B); // Darkest green-black
const Color kCyberBackgroundMedium = Color(0xFF081C10); // Medium dark green
const Color kCyberBackgroundSurface = Color(0xFF0F2A18); // Surface green
const Color kCyberPrimaryGreen =
    Color(0xFF00FF7F); // Bright Neon Green (Primary Accent)
const Color kCyberSecondaryAccent =
    Color(0xFF9D00FF); // Neon Purple (Secondary Accent)
const Color kCyberTertiaryCyan =
    Color(0xFF00EFFF); // Neon Cyan (Highlight/Glow)
const Color kCyberHighlight =
    Color(0xFFF0FFF0); // Very light, slightly green-tinted white
const Color kCyberMutedText = Color(0xFF6E8A7F); // Muted greenish-grey
const Color kCyberGlassColor = Color(0x5500FF7F); // Greenish translucent glass
const Color kCyberErrorColor = Color(0xFFFF410D); // Bright Orange/Red Error
const Color kCyberWarningColor = Color(0xFFFFAA00); // Amber/Yellow Warning
const Color kCyberInputBorderColor =
    Color(0x6600FF7F); // Translucent green border
const Color kCyberGlowColor = kCyberPrimaryGreen; // Main glow effect color
const Duration kDefaultAnimDuration = Duration(milliseconds: 400);
const Curve kDefaultAnimCurve = Curves.easeInOutCubic;

// --- State Enum ---
enum ScreenLoadState {
  initializing,
  loadingData,
  processing,
  loaded,
  errorOccurred
}

// ================================================
// ==              HOME SCREEN WIDGET            ==
// ================================================
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  // --- Dependencies ---
  final FirebaseService _firebaseService = FirebaseService();
  final AuthService _authService = AuthService();

  // --- Controllers ---
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late AnimationController _fabController;
  late Animation<double> _fabScaleAnimation;
  late AnimationController
      _backgroundPulseController; // For subtle background effects

  // --- State Variables ---
  ScreenLoadState _loadState = ScreenLoadState.initializing;
  String _userType = 'client'; // Assume client initially
  AppUser? _currentUser;
  String? _errorMessage;

  // --- Data Holders ---
  List<Worker> _allWorkers = []; // Complete fetched list
  List<Worker> _displayWorkers = []; // List currently displayed after filtering
  List<Job> _allJobs = []; // Complete fetched list
  List<Job> _displayJobs = []; // List currently displayed after filtering

  // --- Filtering State (Using ValueNotifiers for reactivity example) ---
  final ValueNotifier<String> _selectedLocationNotifier =
      ValueNotifier<String>('All');
  final ValueNotifier<String> _selectedJobStatusNotifier =
      ValueNotifier<String>('All');
  List<String> _availableLocations = [
    'All',
    'Addis Ababa',
    'Adama',
    'Bahir Dar',
    'Gondar',
    'Mekelle',
    'Hawassa'
  ]; // Example initial
  final List<String> _jobStatusOptions = const [
    'All',
    'Open',
    'Assigned',
    'Completed',
    'Pending'
  ];

  // --- UI / Interaction State ---
  Timer? _searchDebounce;
  bool _isCurrentlySearching = false; // For subtle search UI changes
  double _appBarScrollOffset = 0.0; // To track scroll for parallax/opacity

  // ================================================
  // ==           LIFECYCLE METHODS              ==
  // ================================================
  @override
  void initState() {
    super.initState();
    print("[HomeScreen] Initializing State...");
    _setupAnimations();
    _attachScrollListener();
    _addFilterChangeListeners(); // Listen to filter changes
    // Defer heavy work slightly
    WidgetsBinding.instance.addPostFrameCallback((_) => _initializeScreen());
    _searchController.addListener(_handleSearchInput);
  }

  @override
  void dispose() {
    print("[HomeScreen] Disposing State...");
    _searchController.removeListener(_handleSearchInput);
    _searchController.dispose();
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    _fabController.dispose();
    _backgroundPulseController.dispose();
    _selectedLocationNotifier.dispose();
    _selectedJobStatusNotifier.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  // ================================================
  // ==           ANIMATION & LISTENERS          ==
  // ================================================
  void _setupAnimations() {
    _fabController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..forward();
    _fabScaleAnimation =
        CurvedAnimation(parent: _fabController, curve: Curves.elasticOut);
    _backgroundPulseController =
        AnimationController(vsync: this, duration: const Duration(seconds: 5))
          ..repeat(reverse: true);
    print("[HomeScreen] Animations Setup.");
  }

  void _attachScrollListener() {
    _scrollController.addListener(_scrollListener);
  }

  void _scrollListener() {
    double offset = _scrollController.hasClients ? _scrollController.offset : 0;
    // Update state based on scroll (e.g., for parallax, hiding/showing elements)
    setStateIfMounted(() {
      _appBarScrollOffset = offset;
      // print("Scroll Offset: $offset"); // Debug logging
    });
  }

  void _addFilterChangeListeners() {
    // When a filter changes, log it and trigger a data reload/refilter
    _selectedLocationNotifier.addListener(() {
      print("[Filter Change] Location: ${_selectedLocationNotifier.value}");
      if (_userType == 'client') {
        _applyFilters(); // Refilter client-side for location
      }
    });
    _selectedJobStatusNotifier.addListener(() {
      print("[Filter Change] Job Status: ${_selectedJobStatusNotifier.value}");
      if (_userType == 'worker') {
        _loadData(); // Refetch worker jobs based on status
      }
    });
  }

  void setStateIfMounted(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  // ================================================
  // ==            CORE DATA OPERATIONS          ==
  // ================================================
  Future<void> _initializeScreen() async {
    print("[HomeScreen] Starting Initialization...");
    if (!mounted) return;
    setStateIfMounted(() => _loadState = ScreenLoadState.loadingData);
    _errorMessage = null; // Reset error message
    try {
      _currentUser = await _authService.getCurrentUserProfile();
      _userType = (_currentUser?.role == 'worker') ? 'worker' : 'client';
      print(
          "[Auth] User Identified: $_userType ${_currentUser != null ? '(ID: ${_currentUser!.id})' : '(Guest)'}");
      await _loadData(isInitial: true);
      if (mounted) setStateIfMounted(() => _loadState = ScreenLoadState.loaded);
      print("[HomeScreen] Initialization Complete.");
    } catch (e, s) {
      print("[Error] Initialization Failed!\nError: $e\nStack: $s");
      if (mounted) {
        setStateIfMounted(() {
          _errorMessage = 'System Core Failure. Check Network.';
          _loadState = ScreenLoadState.errorOccurred;
        });
      }
    }
  }

  Future<void> _loadData(
      {bool isRefresh = false, bool isInitial = false}) async {
    if (!mounted) return;
    if (!isRefresh) {
      setStateIfMounted(() => _loadState = ScreenLoadState.loadingData);
    }
    _errorMessage = null;

    try {
      print(
          "[Data Sync] Loading for $_userType (Initial: $isInitial, Refresh: $isRefresh)...");
      if (_userType == 'client') {
        await _loadWorkers(isInitial: isInitial);
      } else {
        await _loadJobs(isInitial: isInitial);
      }
      if (mounted) setStateIfMounted(() => _loadState = ScreenLoadState.loaded);
      print("[Data Sync] Success for $_userType.");
    } catch (e, s) {
      print("[Error] Data Sync Failed!\nError: $e\nStack: $s");
      if (mounted) {
        setStateIfMounted(() {
          _errorMessage = 'Data Stream Disrupted.';
          _loadState = ScreenLoadState.errorOccurred;
        });
      }
    }
  }

  Future<void> _loadWorkers({bool isInitial = false}) async {
    setStateIfMounted(() =>
        _loadState = ScreenLoadState.processing); // Indicate processing stage
    final String? locFilter = _selectedLocationNotifier.value == 'All'
        ? null
        : _selectedLocationNotifier.value;
    _allWorkers = await _firebaseService.getWorkers(
        location: locFilter); // Backend filtering for location
    print(
        "[Data Load] Fetched ${_allWorkers.length} Workers. Filter: $locFilter");

    // Update available locations based on FULL list, only if needed
    if (isInitial ||
        _availableLocations.length <= 1 ||
        !_availableLocations.contains(_selectedLocationNotifier.value)) {
      print("[Filter Update] Recalculating available locations...");
      // Fetch all workers ONLY if necessary for location options
      List<Worker> allWorkersForLocs =
          locFilter == null ? _allWorkers : await _firebaseService.getWorkers();
      _availableLocations = [
        'All',
        ...allWorkersForLocs
            .map((w) => w.location)
            .where((l) => l.isNotEmpty)
            .toSet()
            .toList()
          ..sort()
      ];
      if (!_availableLocations.contains(_selectedLocationNotifier.value)) {
        _selectedLocationNotifier.value = 'All'; // Reset if selection invalid
      }
      print("[Filter Update] Locations set: ${_availableLocations.length}");
    }

    _applyFilters(); // Apply search filter client-side
  }

  Future<void> _loadJobs({bool isInitial = false}) async {
    setStateIfMounted(() => _loadState = ScreenLoadState.processing);
    final userId = _currentUser?.id;
    if (userId == null && _userType == 'worker') {
      throw Exception("Operative ID not found.");
    }
    String? statusFilter = _selectedJobStatusNotifier.value == 'All'
        ? null
        : _selectedJobStatusNotifier.value.toLowerCase();
    // Fetch only open jobs if 'All' selected for worker, otherwise use filter
    String fetchStatus = statusFilter ?? (_userType == 'worker' ? 'open' : '');
    print(
        "[Data Load] Fetching Jobs. Status: ${fetchStatus.isEmpty ? 'ANY' : fetchStatus}");
    _allJobs = await _firebaseService.getJobs(
        status: fetchStatus.isEmpty ? null : fetchStatus);
    print("[Data Load] Fetched ${_allJobs.length} Jobs.");
    _applyFilters(); // Apply search filter client-side
  }

  // Placeholder sample data creation (should live in service layer ideally)
  Future<void> _createSampleWorkersIfNeeded() async {
    /* ... Placeholder ... */
  }

  // ================================================
  // ==          FILTERING & SEARCH LOGIC         ==
  // ================================================
  void _handleSearchInput() {
    _searchDebounce?.cancel();
    setStateIfMounted(
        () => _isCurrentlySearching = _searchController.text.isNotEmpty);
    _searchDebounce = Timer(const Duration(milliseconds: 750), () {
      // Longer debounce
      if (mounted) {
        _applyFilters();
        FocusScope.of(context)
            .unfocus(); // Dismiss keyboard after search debounce
      }
    });
  }

  void _applyFilters() {
    if (!mounted) return;
    final query = _searchController.text.toLowerCase();
    final selectedLocation = _selectedLocationNotifier.value;
    final selectedJobStatus = _selectedJobStatusNotifier.value;
    print(
        "[Filter Apply] Q:'$query' | Loc:'$selectedLocation' | Stat:'$selectedJobStatus'");

    if (_userType == 'client') {
      // Client side filtering: Location filtered backend, search+other client-side
      _displayWorkers = _allWorkers.where((w) {
        final queryMatch = query.isEmpty ||
            w.name.toLowerCase().contains(query) ||
            w.profession.toLowerCase().contains(query) ||
            w.skills.any((s) => s.toLowerCase().contains(query));
        // Add more client-side filters here? Rating? Experience?
        return queryMatch; // Location filter is already applied in _loadWorkers
      }).toList();
      print("[Filter Apply] Displaying ${_displayWorkers.length} workers.");
    } else {
      // Worker side filtering: Status filtered backend (partially), search client-side
      _displayJobs = _allJobs.where((j) {
        final queryMatch = query.isEmpty ||
            j.title.toLowerCase().contains(query) ||
            j.description.toLowerCase().contains(query);
        // Add other client-side job filters? Budget range? Posted date?
        return queryMatch;
      }).toList();
      print("[Filter Apply] Displaying ${_displayJobs.length} jobs.");
    }
    setStateIfMounted(() => _isCurrentlySearching = false);
  }

  void _setFilterLocation(String location) =>
      _selectedLocationNotifier.value = location;
  void _setFilterJobStatus(String status) =>
      _selectedJobStatusNotifier.value = status;

  // ================================================
  // ==              NAVIGATION                  ==
  // ================================================
  void _navigateTo(Widget screen) =>
      Navigator.push(context, _createRoute(screen))
          .then((_) => _loadData(isRefresh: true));
  void _navigateToWorkerDetail(Worker w) =>
      _navigateTo(WorkerDetailScreen(worker: w));
  void _navigateToJobDetail(Job j) => _navigateTo(JobDetailScreen(job: j));
  void _navigateToNotifications() => _navigateTo(const NotificationsScreen());
  void _navigateToHistory() => _navigateTo(const JobHistoryScreen());
  void _navigateToCreateJob() => _navigateTo(const CreateJobScreen());
  void _navigateToProfileSetup() =>
      _navigateTo(const ProfessionalSetupScreen());

  // Custom route for futuristic transition (e.g., Fade)
  Route _createRoute(Widget screen) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => screen,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
      transitionDuration: const Duration(milliseconds: 600), // Slower fade
    );
  }

  // ================================================
  // ==            BUILD METHOD & THEME            ==
  // ================================================
  @override
  Widget build(BuildContext context) {
    print("[Build] HomeScreen build triggered. State: $_loadState");
    return Theme(
      data: _buildCyberTheme(),
      child: Scaffold(
        // Background structure using Stack for potential layers
        body: Stack(
          children: [
            _buildBackgroundLayers(), // Background elements (gradient, particles?)
            SafeArea(
              bottom: false,
              child: CustomScrollView(
                /* Main Scroll */
                controller: _scrollController,
                physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics()),
                slivers: <Widget>[
                  _buildCyberSliverAppBar(), // Themed AppBar
                  _buildStickyFilterHeader(), // Sticky Filter Area
                  _buildMainContentAreaSliver(), // Dynamic list area
                  const SliverPadding(
                      padding:
                          EdgeInsets.only(bottom: 100)), // Space for large FAB
                ],
              ),
            ),
          ],
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        floatingActionButton: _buildFuturisticAnimatedFAB(), // Enhanced FAB
      ),
    );
  }

  ThemeData _buildCyberTheme() => ThemeData(
      /* ... Full theme as before ... */
      brightness: Brightness.dark,
      primaryColor: kCyberPrimaryGreen,
      scaffoldBackgroundColor: kCyberBackgroundDeep,
      fontFamily: 'Quantico',
      colorScheme: const ColorScheme.dark(
          primary: kCyberPrimaryGreen,
          secondary: kCyberSecondaryAccent,
          tertiary: kCyberTertiaryCyan,
          surface: kCyberBackgroundSurface,
          error: kCyberErrorColor,
          onPrimary: kCyberBackgroundDeep,
          onSecondary: kCyberHighlight,
          onSurface: kCyberHighlight,
          onError: kCyberHighlight),
      appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          titleTextStyle: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              fontFamily: 'Quantico'),
          iconTheme: IconThemeData(color: kCyberPrimaryGreen)),
      cardTheme: CardTheme(
          elevation: 8,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: kCyberPrimaryGreen.withOpacity(0.2))),
          color: kCyberBackgroundSurface.withOpacity(0.85),
          shadowColor: kCyberPrimaryGreen.withOpacity(0.1)),
      chipTheme: ChipThemeData(
          backgroundColor: kCyberBackgroundSurface.withOpacity(0.7),
          selectedColor: kCyberPrimaryGreen,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          labelStyle: TextStyle(
              color: kCyberMutedText,
              fontSize: 12,
              fontWeight: FontWeight.w500),
          secondaryLabelStyle: TextStyle(
              color: kCyberBackgroundDeep,
              fontWeight: FontWeight.bold,
              fontSize: 12),
          brightness: Brightness.dark,
          side: BorderSide(color: kCyberPrimaryGreen.withOpacity(0.3)),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: kCyberPrimaryGreen,
          foregroundColor: kCyberBackgroundDeep),
      inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: kCyberBackgroundSurface.withOpacity(0.6),
          hintStyle: TextStyle(
              color: kCyberMutedText.withOpacity(0.7),
              fontStyle: FontStyle.italic,
              fontSize: 14),
          prefixIconColor: kCyberPrimaryGreen.withOpacity(0.8),
          suffixIconColor: kCyberPrimaryGreen.withOpacity(0.8),
          contentPadding:
              const EdgeInsets.symmetric(vertical: 18, horizontal: 22),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: kCyberInputBorderColor)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide:
                  const BorderSide(color: kCyberPrimaryGreen, width: 1.5))),
      textTheme: ThemeData.dark()
          .textTheme
          .apply(
            bodyColor: kCyberHighlight,
            displayColor: kCyberHighlight,
            fontFamily: 'Quantico',
          )
          .copyWith(
              headlineSmall: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: kCyberHighlight,
                  fontSize: 24,
                  letterSpacing: 1.0),
              titleLarge: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: kCyberHighlight,
                  fontSize: 18),
              titleMedium: TextStyle(
                  color: kCyberHighlight.withOpacity(0.9),
                  fontSize: 16,
                  fontWeight: FontWeight.w500),
              bodyMedium: TextStyle(
                  color: kCyberHighlight.withOpacity(0.85),
                  fontSize: 14,
                  height: 1.5),
              bodySmall: const TextStyle(color: kCyberMutedText, fontSize: 12),
              labelLarge: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8)),
      elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
              foregroundColor: kCyberBackgroundDeep,
              backgroundColor: kCyberPrimaryGreen,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 16),
              textStyle: const TextStyle(
                  fontFamily: 'Quantico',
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  letterSpacing: 0.8))),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
              foregroundColor: kCyberPrimaryGreen,
              side: BorderSide(
                  color: kCyberPrimaryGreen.withOpacity(0.7), width: 1.5),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 16),
              textStyle: const TextStyle(
                  fontFamily: 'Quantico',
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  letterSpacing: 0.8))));

  // ================================================
  // ==            UI WIDGET BUILDERS             ==
  // ================================================

  // --- Background Layers ---
  Widget _buildBackgroundLayers() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Base Gradient
        Container(
            decoration: const BoxDecoration(
                gradient: LinearGradient(
                    colors: [
                      Color(0xFF03100B),
                      Color(0xFF0B1F10),
                      kCyberBackgroundDeep
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    stops: [0.0, 0.4, 1.0]))),
        // Placeholder for Particle Effect - Requires a package or CustomPainter
        // Positioned.fill(child: Opacity(opacity: 0.3, child: ParticlesWidget())),
        // Subtle pulsing background glow?
        _buildBackgroundPulse(),
      ],
    );
  }

  Widget _buildBackgroundPulse() {
    return PlayAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.05, end: 0.15), // Control opacity range
      duration: const Duration(seconds: 6),
      delay: const Duration(seconds: 1),
      curve: Curves.easeInOut,
      // Loop back and forth
      builder: (context, value, child) {
        return Container(
            decoration: BoxDecoration(
                gradient: RadialGradient(
                    center: Alignment.bottomCenter,
                    radius: 2.0, // Large radius
                    colors: [
              kCyberPrimaryGreen.withOpacity(value), // Animated opacity
              kCyberBackgroundDeep.withOpacity(0.0), // Fade to transparent
            ],
                    stops: const [
              0.0,
              0.7
            ])));
      },
      child: const SizedBox
          .expand(), // Child is not strictly needed for this effect
    );
  }

  // --- App Bar ---
  Widget _buildCyberSliverAppBar() {
    // Example of using AppBar transparency based on scroll
    double currentOpacity = (1.0 - (_appBarScrollOffset / 100.0))
        .clamp(0.6, 1.0); // Fade out faster

    return SliverAppBar(
      expandedHeight: 130.0,
      floating: false,
      pinned: true,
      snap: false,
      elevation: 0,
      backgroundColor: kCyberBackgroundSurface.withOpacity(0.5 *
          _appBarScrollOffset.clamp(0, 100) /
          100), // More opaque as you scroll down
      leading: _buildLeadingAction(), // Custom leading if needed
      flexibleSpace: FlexibleSpaceBar(
        centerTitle: true,
        titlePadding: const EdgeInsets.only(bottom: 15),
        title: Opacity(
          opacity: currentOpacity,
          child: Text(_userType == 'client' ? 'CYBER // HIRE' : 'GIG // GRID',
              style: TextStyle(
                  fontFamily: 'Quantico',
                  fontWeight: FontWeight.w900, // Heavier weight
                  fontSize: 17,
                  color: kCyberHighlight.withOpacity(0.95),
                  letterSpacing: 3.5,
                  shadows: [
                    Shadow(
                        color: kCyberPrimaryGreen.withOpacity(0.6),
                        blurRadius: 12)
                  ])),
        ),
        background: _buildAppBarBackground(),
        collapseMode: CollapseMode.pin, // Keep title visible
      ),
      actions: _buildAppBarActions(),
    );
  }

  Widget _buildLeadingAction() {
    // Example: Could show a profile avatar or custom icon
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: CircleAvatar(
        backgroundColor: kCyberPrimaryGreen.withOpacity(0.2),
        // backgroundImage: _currentUser?.profileImage != null ? CachedNetworkImageProvider(_currentUser!.profileImage!) : null,
        child: FaIcon(FontAwesomeIcons.userAstronaut,
            size: 18, color: kCyberPrimaryGreen), // Placeholder icon
      ),
    );
  }

  Widget _buildAppBarBackground() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          kCyberBackgroundMedium.withOpacity(0.9),
          kCyberBackgroundSurface.withOpacity(0.7)
        ], begin: Alignment.topCenter, end: Alignment.bottomCenter),
      ),
      child: Opacity(
          opacity: 0.05,
          child:
              Container()) // Add texture/pattern Image placeholder: Image.asset('assets/patterns/hex_pattern.png', fit: BoxFit.cover) ),
      ,
    );
  }

  List<Widget> _buildAppBarActions() => [
        _AppBarActionButton(
            icon: FontAwesomeIcons.solidBell,
            tooltip: 'Alerts',
            onPressed: _navigateToNotifications), // Changed icon
        _AppBarActionButton(
            icon: FontAwesomeIcons.clockRotateLeft,
            tooltip: 'Logs',
            onPressed: _navigateToHistory),
        _AppBarActionButton(
            icon: FontAwesomeIcons.arrowsRotate,
            tooltip: 'Refresh Grid',
            onPressed: () => _loadData(isRefresh: true)),
        const SizedBox(width: 4), // Padding
      ];

  // --- Filter Area ---
  Widget _buildStickyFilterHeader() => SliverPersistentHeader(
      delegate: _FilterHeaderDelegate(
          minHeight: 145, // Increased min height
          maxHeight: 145, // Fixed height now
          child: _buildGlassmorphicFilterArea()),
      pinned: true);

  Widget _buildGlassmorphicFilterArea() {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18.0, sigmaY: 18.0),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          decoration: BoxDecoration(
              color: kCyberBackgroundSurface.withOpacity(0.1),
              border: Border(
                  bottom: BorderSide(
                      color: kCyberPrimaryGreen.withOpacity(0.3), width: 1.0))),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildCyberSearchBar(),
              const SizedBox(height: 12), // Reduced spacing
              const Padding(
                  padding: EdgeInsets.only(left: 4, bottom: 4),
                  child: Text("FILTERS ::",
                      style: TextStyle(
                          fontSize: 11,
                          color: kCyberMutedText,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1))),
              _buildCyberFilterChipsRow(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCyberSearchBar() {
    /* ... same as previous ... */ return TextField(
      controller: _searchController,
      style: const TextStyle(color: kCyberHighlight, fontSize: 15),
      decoration: InputDecoration(
          hintText: _userType == 'client'
              ? 'Target Sector: Operatives...'
              : 'Scan Directives...',
          hintStyle: TextStyle(
              color: kCyberMutedText.withOpacity(0.6),
              fontSize: 14,
              fontStyle: FontStyle.italic),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 18, right: 10),
            child: FaIcon(FontAwesomeIcons.searchengin,
                color: kCyberPrimaryGreen.withOpacity(0.8), size: 18),
          ),
          suffixIcon: _isCurrentlySearching
              ? Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          valueColor:
                              AlwaysStoppedAnimation(kCyberPrimaryGreen))))
              : (_searchController.text.isNotEmpty
                  ? IconButton(
                      icon: FaIcon(FontAwesomeIcons.xmark,
                          size: 16, color: kCyberMutedText),
                      onPressed: () {
                        _searchController.clear();
                        _applyFilters();
                      })
                  : null),
          filled: true,
          fillColor: kCyberBackgroundSurface.withOpacity(0.7),
          contentPadding:
              const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  BorderSide(color: kCyberInputBorderColor.withOpacity(0.5))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  const BorderSide(color: kCyberPrimaryGreen, width: 1))),
      onChanged: (_) =>
          _handleSearchInput(), // Changed from _onSearchChanged to match method name
    );
  }

  Widget _buildCyberFilterChipsRow() {
    /* ... same as previous ... */ return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 2),
        children:
            (_userType == 'client' ? _availableLocations : _jobStatusOptions)
                .map((label) => _buildCyberChip(label))
                .toList(),
      ),
    );
  }

  Widget _buildCyberChip(String label) {
    /* ... Uses ValueNotifier ... */ return ValueListenableBuilder<String>(
        valueListenable: _userType == 'client'
            ? _selectedLocationNotifier
            : _selectedJobStatusNotifier,
        builder: (context, selectedValue, _) {
          bool isSelected = selectedValue == label;
          VoidCallback onSelect = _userType == 'client'
              ? () => _setFilterLocation(label)
              : () => _setFilterJobStatus(label);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: ChoiceChip(
              label: Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 0.4,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal)),
              selected: isSelected,
              onSelected: (_) => onSelect(),
              labelStyle: TextStyle(
                  color: isSelected
                      ? kCyberBackgroundDeep
                      : kCyberPrimaryGreen.withOpacity(0.9)),
              avatar: isSelected
                  ? FaIcon(FontAwesomeIcons.check,
                      size: 11, color: kCyberBackgroundDeep)
                  : null,
              backgroundColor: kCyberBackgroundSurface.withOpacity(0.5),
              selectedColor: kCyberPrimaryGreen,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                      color: kCyberPrimaryGreen
                          .withOpacity(isSelected ? 0.7 : 0.25))),
              elevation: isSelected ? 2 : 0,
              showCheckmark: false,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          );
        });
  }

  // --- Content Area ---
  Widget _buildMainContentAreaSliver() {
    return SliverPadding(
      padding: const EdgeInsets.only(left: 12, right: 12, top: 24, bottom: 24),
      sliver: _buildCurrentStateSliverWidget(),
    );
  } // Padding added

  Widget _buildCurrentStateSliverWidget() {
    /* ... Logic as before ... */ switch (_loadState) {
      case ScreenLoadState.initializing:
      case ScreenLoadState.loadingData:
      case ScreenLoadState.processing:
        return _buildCyberShimmerSliverList();
      case ScreenLoadState.errorOccurred:
        return _buildCyberErrorSliverWidget();
      case ScreenLoadState.loaded:
        bool empty = (_userType == 'client' && _displayWorkers.isEmpty) ||
            (_userType == 'worker' && _displayJobs.isEmpty);
        if (empty) return _buildCyberEmptySliverState();
        return AnimationLimiter(
          key: ValueKey(
              "content_${_userType}_${_selectedLocationNotifier.value}_${_selectedJobStatusNotifier.value}"),
          child: SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) => AnimationConfiguration.staggeredList(
                position: i,
                duration: const Duration(milliseconds: 650),
                child: SlideAnimation(
                  verticalOffset: 90.0,
                  child: FadeInAnimation(
                    duration: const Duration(milliseconds: 750),
                    child: _userType == 'client'
                        ? UltraCyberWorkerCard(
                            worker: _displayWorkers[i],
                            onTap: () =>
                                _navigateToWorkerDetail(_displayWorkers[i]))
                        : UltraCyberJobCard(
                            job: _displayJobs[i],
                            onTap: () => _navigateToJobDetail(_displayJobs[i])),
                  ),
                ),
              ),
              childCount: _userType == 'client'
                  ? _displayWorkers.length
                  : _displayJobs.length,
            ),
          ),
        );
      default:
        return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
  }

  // --- Shimmer, Error, Empty ---
  Widget _buildCyberShimmerSliverList() {
    /* ... Returns SliverList of Shimmers ... */ bool cli =
        _userType == 'client';
    return SliverList(
        delegate: SliverChildBuilderDelegate(
            (ctx, i) => cli ? _CyberWorkerShimmer() : _CyberJobShimmer(),
            childCount: 4));
  }

  Widget _CyberWorkerShimmer() {
    /* ... Worker shimmer UI ... */ return Shimmer.fromColors(
        baseColor: kCyberBackgroundSurface,
        highlightColor: kCyberBackgroundMedium,
        period: const Duration(milliseconds: 900),
        child: Container(
            margin: const EdgeInsets.only(bottom: 22),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: kCyberPrimaryGreen.withOpacity(0.05))),
            child: Row(children: [
              const CircleAvatar(radius: 40, backgroundColor: Colors.black),
              const SizedBox(width: 16),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Container(
                        height: 22,
                        width: 160,
                        decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.circular(6))),
                    const SizedBox(height: 10),
                    Container(
                        height: 18,
                        width: 110,
                        decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.circular(6))),
                    const SizedBox(height: 14),
                    Row(
                        children: List.generate(
                            3,
                            (_) => Padding(
                                padding: const EdgeInsets.only(right: 10.0),
                                child: Container(
                                    height: 25,
                                    width: math.Random().nextDouble() * 25 + 45,
                                    decoration: BoxDecoration(
                                        color: Colors.black,
                                        borderRadius:
                                            BorderRadius.circular(15))))))
                  ]))
            ])));
  }

  Widget _CyberJobShimmer() {
    /* ... Job shimmer UI ... */ return Shimmer.fromColors(
        baseColor: kCyberBackgroundSurface,
        highlightColor: kCyberBackgroundMedium,
        period: const Duration(milliseconds: 1000),
        child: Container(
            margin: const EdgeInsets.only(bottom: 22),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: kCyberPrimaryGreen.withOpacity(0.05))),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Container(
                    height: 22,
                    width: math.Random().nextDouble() * 120 + 160,
                    decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(6))),
                Container(
                    height: 30,
                    width: 85,
                    decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(20))),
              ]),
              const SizedBox(height: 15),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Container(
                    height: 16,
                    width: 90,
                    decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(6))),
                Container(
                    height: 16,
                    width: 70,
                    decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(6))),
                Container(
                    height: 16,
                    width: 60,
                    decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(6)))
              ]),
              const SizedBox(height: 22),
              Center(
                  child: Container(
                      height: 48,
                      width: 160,
                      decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(8))))
            ])));
  }

  Widget _buildCyberErrorSliverWidget() {
    /* ... SliverFillRemaining error UI ... */ return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 35, vertical: 45),
          decoration: BoxDecoration(
              color: kCyberErrorColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                  color: kCyberErrorColor.withOpacity(0.6), width: 1.5)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const FaIcon(FontAwesomeIcons.circleExclamation,
                  color: kCyberErrorColor, size: 55),
              const SizedBox(height: 25),
              Text("TRANSMISSION ERROR",
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: kCyberErrorColor,
                      letterSpacing: 1.8,
                      fontSize: 20)),
              const SizedBox(height: 12),
              Text(_errorMessage ?? 'Network anomaly detected.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: kCyberMutedText),
                  textAlign: TextAlign.center),
              const SizedBox(height: 35),
              ElevatedButton.icon(
                  icon: const FaIcon(FontAwesomeIcons.arrowsRotate, size: 14),
                  label: const Text("RECONNECT"),
                  onPressed: () => _loadData(),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: kCyberErrorColor.withOpacity(0.8),
                      foregroundColor: kCyberHighlight)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCyberEmptySliverState() {
    /* ... SliverFillRemaining empty UI ... */ bool isClient =
        _userType == 'client';
    String title = isClient ? "// SECTOR CLEAR" : "// QUEUE EMPTY";
    String msg = isClient
        ? "No operatives match current parameters."
        : "Awaiting new directives.";
    IconData icon =
        isClient ? FontAwesomeIcons.userSlash : FontAwesomeIcons.folderMinus;
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Opacity(
          opacity: 0.4,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FaIcon(icon, color: kCyberPrimaryGreen, size: 65),
              const SizedBox(height: 30),
              Text(title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      letterSpacing: 3.0,
                      color: kCyberMutedText,
                      fontSize: 20)),
              const SizedBox(height: 15),
              Text(msg,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: kCyberMutedText.withOpacity(0.6)),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  // --- Animated FAB ---
  Widget? _buildFuturisticAnimatedFAB() {
    // Corrected: Use ScreenLoadState enum
    if (_loadState != ScreenLoadState.loaded) return null;

    bool showFab = false;
    String fabLabel = '';
    IconData fabIcon = FontAwesomeIcons.plus;
    VoidCallback onPressed = () {};
    Color fabColor = kCyberPrimaryGreen;
    double elevation = 12;

    // FIXME: Ensure AppUser model HAS `profileComplete` bool? field or REMOVE THIS BLOCK
    bool isProfileIncomplete = false; // Default assumption
    if (_currentUser != null) {
      // Check if profileComplete exists and handle null
      // Ensure your AppUser model actually has this field!
      isProfileIncomplete = true; // Assuming true if null/missing
      // print("DEBUG: profileComplete value: ${_currentUser!.profileComplete}"); // Debug print
    }
    // END FIXME block check

    if (_userType == 'client') {
      showFab = true;
      fabLabel = 'Initiate Task';
      fabIcon = FontAwesomeIcons.fileCirclePlus;
      onPressed = _navigateToCreateJob;
    } else if (isProfileIncomplete) {
      showFab = true;
      fabLabel = 'Register ID';
      fabIcon = FontAwesomeIcons.idCard;
      onPressed = _navigateToProfileSetup;
      fabColor = kCyberSecondaryAccent;
      elevation = 16; // More prominent
    }

    if (!showFab) return null;

    // FAB wrapped in Scale animation and potential Outer Glow (placeholder)
    return ScaleTransition(
      scale: _fabScaleAnimation,
      child: Container(
        // Outer container for potential glow effect
        decoration: BoxDecoration(
          shape: BoxShape.circle, // Use circle for glow
          boxShadow: [
            BoxShadow(
                color: fabColor.withOpacity(0.4),
                blurRadius: 18,
                spreadRadius: 2)
          ],
        ),
        child: FloatingActionButton.extended(
          onPressed: onPressed,
          label: Text(fabLabel,
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  fontFamily: 'Quantico',
                  fontSize: 13)),
          icon: FaIcon(fabIcon, size: 16),
          backgroundColor: fabColor,
          foregroundColor: kCyberBackgroundDeep,
          elevation: elevation,
          highlightElevation: elevation + 4,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16.0)), // Squarish FAB
          tooltip: _userType == 'client'
              ? 'New Job Directive'
              : 'Complete Operative Profile',
        ),
      ),
    );
  }
} // ============== END OF _HomeScreenState ==============

// ================================================================
// ==           EXTRA WIDGETS (DELEGATE, BUTTON)             ==
// ================================================================

// --- Helper Widget for AppBar Action Buttons ---
class _AppBarActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _AppBarActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: FaIcon(icon, size: 19, color: kCyberPrimaryGreen.withOpacity(0.9)),
      tooltip: tooltip,
      splashRadius: 22,
      hoverColor: kCyberPrimaryGreen.withOpacity(0.1),
      highlightColor: kCyberPrimaryGreen.withOpacity(0.15),
      onPressed: onPressed,
    );
  }
}

// --- Delegate for Sticky Filter Header ---
class _FilterHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double minHeight;
  final double maxHeight;
  final Widget child;

  _FilterHeaderDelegate({
    required this.minHeight,
    required this.maxHeight,
    required this.child,
  });

  @override
  double get minExtent => minHeight;
  @override
  double get maxExtent => math.max(maxHeight, minHeight);

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    // You could add effects based on shrinkOffset here if desired
    return SizedBox.expand(child: child);
  }

  @override
  bool shouldRebuild(_FilterHeaderDelegate oldDelegate) {
    return maxHeight != oldDelegate.maxHeight ||
        minHeight != oldDelegate.minHeight ||
        child != oldDelegate.child;
  }
}

// ================================================================
// ==         EXTRA COMPLEX / STYLIZED CARD WIDGETS           ==
// ================================================================
// NOTE: These are highly detailed examples to increase complexity/lines.
// Placeholder Color - Replace if needed
const Color kSuccessColorFuturistic =
    Color(0xFF00E676); // A bright green for success

// --- ULTRA CYBER WORKER CARD ---
class UltraCyberWorkerCard extends StatefulWidget {
  final Worker worker;
  final VoidCallback onTap;
  const UltraCyberWorkerCard(
      {required this.worker, required this.onTap, super.key});
  @override
  _UltraCyberWorkerCardState createState() => _UltraCyberWorkerCardState();
}

class _UltraCyberWorkerCardState extends State<UltraCyberWorkerCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _hoverController;
  late Animation<double> _glowAnimation;
  bool _isHovering = false;

  @override
  void initState() {
    super.initState();
    _hoverController =
        AnimationController(vsync: this, duration: kDefaultAnimDuration);
    _glowAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _hoverController, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _hoverController.dispose();
    super.dispose();
  }

  void _handleHover(bool hovering) {
    if (hovering != _isHovering) {
      setState(() => _isHovering = hovering);
      if (_isHovering) {
        _hoverController.forward();
      } else {
        _hoverController.reverse();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Encapsulating card structure for potential reuse/modification
    return MouseRegion(
      onEnter: (_) => _handleHover(true),
      onExit: (_) => _handleHover(false),
      cursor: SystemMouseCursors.click, // Indicate interactivity
      child: AnimatedBuilder(
          animation: _glowAnimation,
          builder: (context, child) {
            // Apply dynamic styling based on hover state via _glowAnimation.value
            double glowIntensity =
                _glowAnimation.value * 0.3; // Control max glow
            return Card(
                /* Card Base */
                margin: const EdgeInsets.only(bottom: 22),
                elevation: 6 + (_glowAnimation.value * 6), // Dynamic elevation
                clipBehavior: Clip.antiAlias,
                shape: _buildCardShape(
                    _glowAnimation.value), // Animated Shape/Border
                shadowColor:
                    kCyberPrimaryGreen.withOpacity(0.1 + glowIntensity * 0.2),
                child: InkWell(
                    /* Interaction Layer */
                    onTap: widget.onTap,
                    splashColor: kCyberPrimaryGreen.withOpacity(0.15),
                    highlightColor: kCyberPrimaryGreen.withOpacity(0.1),
                    child: Container(
                      /* Content Container */
                      decoration: _buildCardDecoration(_glowAnimation.value),
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        mainAxisSize:
                            MainAxisSize.min, // Important for Column height
                        children: [
                          _buildWorkerCardHeader(context, widget.worker),
                          _buildDivider(),
                          _buildWorkerStatsRow(context, widget.worker),
                          const SizedBox(height: 10),
                          _buildWorkerSkillsSection(
                              context, widget.worker.skills),
                          // Maybe add 'About' snippet conditionally?
                          // if (widget.worker.about.isNotEmpty) ...[
                          //    _buildDivider(height: 15),
                          //   _buildAboutSnippet(context, widget.worker.about),
                          //  ],
                          // Possibly add action buttons directly on card (less common for list view)
                        ],
                      ),
                    )));
          }),
    );
  }

  // --- Card Sub-Builders ---
  ShapeBorder _buildCardShape(double animValue) {
    // Animate border radius or shape? Example: slight rounding change on hover
    double borderRadius = 10.0 + (animValue * 4.0);
    return RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        side: BorderSide(
            color: kCyberPrimaryGreen.withOpacity(0.1 + animValue * 0.3),
            width: 1.0 + animValue * 0.5)); // Animated border
  }

  Decoration _buildCardDecoration(double animValue) {
    return BoxDecoration(
      gradient: LinearGradient(colors: [
        kCyberBackgroundSurface.withOpacity(0.9 - animValue * 0.1),
        kCyberBackgroundMedium.withOpacity(0.8 - animValue * 0.1)
      ], begin: Alignment.topLeft, end: Alignment.bottomRight),
    );
  }

  Widget _buildWorkerCardHeader(BuildContext context, Worker worker) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _buildWorkerAvatar(worker),
      const SizedBox(width: 14),
      Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(worker.name,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(color: kCyberHighlight, fontSize: 17),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: 5),
        _buildIconAndText(FontAwesomeIcons.userNinja, worker.profession,
            kCyberPrimaryGreen.withOpacity(0.8), context,
            size: 14),
        const SizedBox(height: 5),
        _buildIconAndText(FontAwesomeIcons.locationCrosshairs, worker.location,
            kCyberMutedText, context),
      ])),
      _buildWorkerRatingBadge(worker.rating), // Top right rating
    ]);
  }

  Widget _buildWorkerAvatar(Worker worker) {
    return Hero(
        tag: 'worker-${worker.id}',
        child: Container(
            width: 70,
            height: 70,
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: kCyberPrimaryGreen.withOpacity(0.5), width: 1.5)),
            child: CircleAvatar(
                radius: 35,
                backgroundColor: kCyberBackgroundSurface,
                backgroundImage: worker.profileImage.isNotEmpty
                    ? CachedNetworkImageProvider(worker.profileImage)
                    : null,
                child: worker.profileImage.isEmpty
                    ? FaIcon(FontAwesomeIcons.ghost,
                        size: 25, color: kCyberMutedText.withOpacity(0.8))
                    : null)));
  }

  Widget _buildWorkerRatingBadge(double rating) {
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: Colors.amberAccent[700]!.withOpacity(0.2),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: Colors.amberAccent[700]!.withOpacity(0.5), width: 0.5)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          FaIcon(FontAwesomeIcons.solidStar,
              size: 10, color: Colors.amberAccent[700]),
          const SizedBox(width: 4),
          Text(rating.toStringAsFixed(1),
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  color: Colors.amberAccent[100]))
        ]));
  }

  Widget _buildWorkerStatsRow(BuildContext context, Worker worker) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem(context, Icons.check_circle_outline_rounded,
              '${worker.completedJobs}', 'Jobs Done', kCyberPrimaryGreen),
          _buildStatItem(context, Icons.military_tech_outlined,
              '${worker.experience}', 'Years Exp', kCyberSecondaryAccent),
          _buildStatItem(context, Icons.account_balance_wallet_outlined,
              '${worker.priceRange.toInt()}', 'Credits/Hr', kCyberTertiaryCyan),
        ],
      ),
    );
  }

  Widget _buildStatItem(BuildContext context, IconData icon, String value,
      String label, Color color) {
    return Column(
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(value,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: kCyberHighlight, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 3),
        Text(label,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(fontSize: 10, color: kCyberMutedText)),
      ],
    );
  }

  Widget _buildWorkerSkillsSection(BuildContext context, List<String> skills) {
    if (skills.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("SKILL MATRIX ::",
            style: TextStyle(
                fontSize: 11,
                color: kCyberMutedText,
                fontWeight: FontWeight.bold,
                letterSpacing: 1)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: skills
              .take(5)
              .map((skill) => _buildSkillTagWithProficiency(
                  skill, math.Random().nextDouble()))
              .toList(), // Show max 5 with random proficiency
        )
      ],
    );
  }

  Widget _buildSkillTagWithProficiency(String skill, double proficiency) {
    // Proficiency 0.0 to 1.0
    Color profColor =
        Color.lerp(Colors.redAccent, kCyberPrimaryGreen, proficiency)!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: kCyberBackgroundSurface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: kCyberMutedText.withOpacity(0.3))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(skill,
              style: TextStyle(
                  fontSize: 11, color: kCyberHighlight.withOpacity(0.9))),
          const SizedBox(height: 4),
          /* Proficiency Bar */ Container(
            width: 60, // Fixed width for bar alignment
            height: 4,
            decoration: BoxDecoration(
                color: kCyberMutedText.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2)),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 60 * proficiency,
                decoration: BoxDecoration(
                    color: profColor,
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: [
                      BoxShadow(
                          color: profColor.withOpacity(0.5), blurRadius: 4)
                    ]),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildDivider({double height = 12}) => Padding(
        padding: EdgeInsets.symmetric(vertical: height),
        child: Divider(
            color: kCyberPrimaryGreen.withOpacity(0.15),
            thickness: 1,
            height: 1),
      );

  Widget _buildIconAndText(
      IconData icon, String text, Color color, BuildContext context,
      {double size = 13}) {
    // Updated helper
    return Row(mainAxisSize: MainAxisSize.min, children: [
      FaIcon(icon, size: size, color: color),
      const SizedBox(width: 8),
      Flexible(
          child: Text(text,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: color, fontSize: 12.5),
              overflow: TextOverflow.ellipsis))
    ]);
  }
} // End UltraCyberWorkerCard

// --- ULTRA CYBER JOB CARD ---
class UltraCyberJobCard extends StatelessWidget {
  final Job job;
  final VoidCallback onTap;
  const UltraCyberJobCard({required this.job, required this.onTap, super.key});
  @override
  Widget build(BuildContext context) {
    final statusColor = _getJobStatusColor(job.status);
    final statusIcon = _getJobStatusIcon(job.status);
    final timeAgo = _getTimeAgoLabel(job.createdAt);
    return Card(
        margin: const EdgeInsets.only(bottom: 20),
        elevation: 5,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: statusColor.withOpacity(0.4))),
        child: InkWell(
            onTap: onTap,
            splashColor: statusColor.withOpacity(0.2),
            highlightColor: statusColor.withOpacity(0.1),
            child: Container(
                decoration: BoxDecoration(
                    /* Maybe angled gradient or texture? */ gradient:
                        LinearGradient(colors: [
                  kCyberBackgroundSurface,
                  kCyberBackgroundMedium
                ], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      /* Header */ Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                              color: kCyberBackgroundSurface.withOpacity(0.5),
                              border: Border(
                                  bottom: BorderSide(
                                      color: kCyberPrimaryGreen
                                          .withOpacity(0.2)))),
                          child: Row(children: [
                            Expanded(
                                child: Text(job.title,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(color: kCyberHighlight),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis)),
                            const SizedBox(width: 10),
                            /* Status Chip */ Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                    color: statusColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                        color: statusColor, width: 0.5)),
                                child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      FaIcon(statusIcon,
                                          size: 10, color: statusColor),
                                      const SizedBox(width: 5),
                                      Text(job.status.toUpperCase(),
                                          style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                              color: statusColor,
                                              letterSpacing: 0.7))
                                    ]))
                          ])),
                      /* Body */ Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(children: [
                            /* Description Snippet */ Text(job.description,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: kCyberMutedText),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 15),
                            /* Key Info Grid */ _buildJobInfoGrid(
                                job, timeAgo, context)
                          ])),
                      /* Action Footer */ Container(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                          decoration: BoxDecoration(
                              color: kCyberBackgroundMedium.withOpacity(0.6),
                              border: Border(
                                  top: BorderSide(
                                      color: kCyberPrimaryGreen
                                          .withOpacity(0.1)))),
                          child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                /* Placeholder for maybe quick apply/save */
                                /* TextButton(onPressed: (){}, child: Text("SAVE", style: TextStyle(color: kCyberMutedText, fontSize: 11))), SizedBox(width: 15), */
                                ElevatedButton(
                                    onPressed: onTap,
                                    style: ElevatedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 24, vertical: 8),
                                        backgroundColor:
                                            statusColor.withOpacity(0.85),
                                        foregroundColor:
                                            _getTextColorForStatusBg(
                                                statusColor),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(6)),
                                        textStyle: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.5)),
                                    child: Text(_getJobButtonText(job.status)))
                              ])),
                    ]))));
  }

  // Card Sub-builders
  Widget _buildJobInfoGrid(Job job, String timeAgo, BuildContext context) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      _buildJobInfoItem(context, FontAwesomeIcons.coins,
          '${job.budget.toInt()} Credits', kSuccessColorFuturistic),
      _buildJobInfoItem(context, FontAwesomeIcons.mapMarkerAlt, job.location,
          kCyberSecondaryAccent),
      _buildJobInfoItem(
          context, FontAwesomeIcons.clock, timeAgo, kCyberMutedText),
    ]);
  }

  Widget _buildJobInfoItem(
      BuildContext context, IconData icon, String text, Color color) {
    return Expanded(
        // Use expanded for even spacing
        child: Row(mainAxisSize: MainAxisSize.min, children: [
      FaIcon(icon, size: 13, color: color),
      const SizedBox(width: 6),
      Flexible(
          child: Text(text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 11.5, color: kCyberHighlight.withOpacity(0.9)),
              overflow: TextOverflow.ellipsis))
    ]));
  }

  // Helper Functions for Job Card
  Color _getJobStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'open':
        return kCyberPrimaryGreen;
      case 'pending':
        return kCyberWarningColor;
      case 'assigned':
      case 'in_progress':
        return kCyberSecondaryAccent;
      case 'completed':
        return kSuccessColorFuturistic;
      default:
        return kCyberMutedText;
    }
  }

  IconData _getJobStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'open':
        return FontAwesomeIcons.folderTree;
      case 'pending':
        return FontAwesomeIcons.hourglassHalf;
      case 'assigned':
      case 'in_progress':
        return FontAwesomeIcons.gears;
      case 'completed':
        return FontAwesomeIcons.circleCheck;
      default:
        return FontAwesomeIcons.circleQuestion;
    }
  }

  String _getJobButtonText(String status) {
    switch (status.toLowerCase()) {
      case 'open':
        return 'Apply//Engage';
      case 'assigned':
      case 'in_progress':
        return 'View//Interface';
      case 'completed':
        return 'Review//Log';
      default:
        return 'Query//Details';
    }
  }

  String _getTimeAgoLabel(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 3) return DateFormat('yy.MM.dd').format(dt);
    if (diff.inDays > 0) return '${diff.inDays}d Cycle';
    if (diff.inHours > 0) return '${diff.inHours}h Cycle';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m Cycle';
    return '<1m Cycle';
  }

  Color _getTextColorForStatusBg(Color bgColor) =>
      bgColor.computeLuminance() > 0.5
          ? kCyberBackgroundDeep
          : kCyberHighlight; // Ensure contrast
}
