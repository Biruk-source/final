// lib/screens/home_screen.dart

import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui; // Required for ImageFilter
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:animate_do/animate_do.dart';
import 'package:liquid_pull_to_refresh/liquid_pull_to_refresh.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:provider/provider.dart'; // Import Provider

// --- Models, Services, Screens & Localization ---
import '../models/worker.dart';
import '../models/job.dart';
import '../models/user.dart';
import '../services/firebase_service.dart';
import '../services/auth_service.dart';
import '../services/app_string.dart'; // ** Import AppLocalizations (for strings) **
import '../providers/locale_provider.dart'; // ** Import LocaleProvider **
import '../providers/theme_provider.dart'; // ** Import ThemeProvider **
import 'worker_detail_screen.dart';
import 'jobs/create_job_screen.dart';
import 'jobs/job_detail_screen.dart';
import 'notifications_screen.dart';
import 'job_history_screen.dart';
import 'professional_setup_screen.dart';

// ============================================================
//               HomeScreen Widget - FULL POWER!
// ============================================================
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  // --- Services & Controllers ---
  final FirebaseService _firebaseService = FirebaseService();
  final AuthService _authService = AuthService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final CarouselSliderController _carouselController =
      CarouselSliderController();
  late AnimationController _fabAnimationController;

  // --- State Variables ---
  bool _isLoading = true;
  String _userType = 'client';
  AppUser? _currentUser;
  double _appBarOpacity = 1.0;
  int _currentGradientIndex = 0;
  Timer? _gradientTimer;
  final Random _random = Random();

  // --- Data Lists ---
  List<Worker> _workers = [];
  List<Worker> _filteredWorkers = [];
  List<Worker> _featuredWorkers = [];
  List<Job> _jobs = [];
  List<Job> _filteredJobs = [];
  List<Job> _featuredJobs = [];

  // --- Filter States ---
  String _filterSelectedLocation = 'All';
  String _filterSelectedCategory = 'All';
  String _tempSelectedLocation = 'All';
  String _tempSelectedCategory = 'All';
  List<String> _locations = ['All'];
  final List<String> _baseCategories = [
    'All',
    'Plumbing',
    'Electrical',
    'Carpentry',
    'Painting',
    'Cleaning',
    'Gardening',
    'Handyman',
    'Tech Repair',
    'Tutoring',
    'Other'
  ];
  List<String> _availableCategories = ['All'];
  String _filterSelectedJobStatus = 'All';
  String _tempSelectedJobStatus = 'All';
  final List<String> _jobStatuses = ['All', 'Open', 'Assigned', 'Completed'];
  final Set<String> _dynamicLocations = {'All'};

  // --- Constants & Configuration ---
  final Duration _shimmerDuration = const Duration(milliseconds: 1500);
  final Duration _animationDuration = const Duration(milliseconds: 450);
  final Curve _animationCurve = Curves.easeInOutCubic;

  // Dark Mode Specific Gradients
  static const List<List<Color>> _gentleAnimatedBgGradients = [
    [Color(0xFF232526), Color(0xFF414345)], // Existing: charcoal
    [Color(0xFF141E30), Color(0xFF243B55)], // Existing: navy steel
    [Color(0xFF360033), Color(0xFF0B8793)], // Existing: purple teal
    [Color(0xFF2E3141), Color(0xFF4E546A)], // Existing: smoky night
    [Color(0xFF16222A), Color(0xFF3A6073)], // Existing: night ocean
    [Color(0xFF3E404E), Color(0xFF646883)], // Existing: twilight grey
    // === NEW & BEAUTIFUL DARK GRADIENTS ===
    [Color(0xFF0F2027), Color(0xFF2C5364)], // deep space blue
    [Color(0xFF1F1C2C), Color(0xFF928DAB)], // violet mist
    [Color(0xFF2C3E50), Color(0xFF4CA1AF)], // midnight ice
    [Color(0xFF373B44), Color(0xFF4286f4)], // cobalt grey-blue
    [Color(0xFF1A2980), Color(0xFF26D0CE)], // galaxy ocean
    [
      Color(0xFF1D2B64),
      Color(0xFFF8CDDA)
    ], // elegant indigo (fades to pink mist)
    [Color(0xFF0F0C29), Color(0xFF302B63)], // purple abyss
    [Color(0xFF000000), Color(0xFF434343)], // true black to soft black
    [Color(0xFF1B1B2F), Color(0xFF16213E)], // dark royal blue blend
    [Color(0xFF3A1C71), Color(0xFFD76D77)], // luxury violet-pink
  ];

  // Light Mode Gradients
  static const List<List<Color>> _gentleAnimatedBgGradient = [
    // === DARKER THEMED GRADIENTS ===
    [Color(0xFFB8860B), Color(0xFF8B8000)], // darker gold sunrise
    [Color(0xFF8B3A62), Color(0xFF4682B4)], // deep pink to steel blue
    [Color(0xFF7B68EE), Color(0xFF4169E1)], // dark lavender to royal blue
    [Color(0xFFB8860B), Color(0xFF8B4513)], // goldenrod to saddle brown
    [Color(0xFF8B5F65), Color(0xFF4B0082)], // dusty rose to indigo
    [Color(0xFF2E8B57), Color(0xFF228B22)], // sea green to forest green
    [Color(0xFFDAA520), Color(0xFFCD853F)], // goldenrod to peru
    [Color(0xFF8B7500), Color(0xFFCD5C5C)], // dark gold to indian red
    [Color(0xFF5F9EA0), Color(0xFF4682B4)], // cadet blue to steel blue
    [Color(0xFFB22222), Color(0xFF8B0000)], // firebrick to dark red
    [Color(0xFF8B6969), Color(0xFF3C3C3C)], // dusty rose to charcoal
    [Color(0xFF556B2F), Color(0xFF6B8E23)], // dark olive to olive drab
  ];

  @override
  void initState() {
    super.initState();
    _fabAnimationController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _scrollController.addListener(_scrollListener);
    _searchController.addListener(_onSearchChanged);
    _determineUserTypeAndLoadData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateBackgroundAnimationBasedOnTheme();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Update background animation if theme changes while screen is active
    _updateBackgroundAnimationBasedOnTheme();
  }

  @override
  void dispose() {
    _gradientTimer?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    _fabAnimationController.dispose();
    super.dispose();
  }

  // --- Core Logic & Data Fetching ---

  void _startBackgroundAnimation() {
    if (!mounted) return;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final gradientList =
        isDarkMode ? _gentleAnimatedBgGradients : _gentleAnimatedBgGradient;

    _gradientTimer?.cancel(); // Cancel previous timer
    _gradientTimer = Timer.periodic(const Duration(seconds: 12), (timer) {
      // Check theme hasn't changed since timer started
      if (mounted &&
          Theme.of(context).brightness ==
              (isDarkMode ? Brightness.dark : Brightness.light)) {
        setState(() {
          _currentGradientIndex =
              (_currentGradientIndex + 1) % gradientList.length;
        });
      } else {
        // Theme changed or widget unmounted, stop this timer
        timer.cancel();
      }
    });
  }

  void _updateBackgroundAnimationBasedOnTheme() {
    if (!mounted) return;
    final bool isTimerActive =
        _gradientTimer != null && _gradientTimer!.isActive;
    final currentThemeBrightness = Theme.of(context).brightness;

    // Start animation only if not already running for the current theme
    if (!isTimerActive) {
      _startBackgroundAnimation();
    }
    // If timer is running for the WRONG theme, cancel it and start new one
    else {
      // A bit complex: need to know which theme the *timer* was started for.
      // Simplification: If brightness changed, just restart the timer.
      // This might cause a brief flicker but ensures correctness.
      // A more robust way would involve storing the timer's intended theme.
      // Let's assume the timer gets cancelled correctly by its internal check.
      // If not, we might need a more explicit check here. For now, let's rely
      // on the internal check and the didChangeDependencies call.
    }
  }

  void _scrollListener() {
    if (!mounted) return;
    double offset = _scrollController.offset;
    double maxOffset = 150; // Threshold for AppBar opacity change
    double newOpacity = (1.0 - (offset / maxOffset)).clamp(0.0, 1.0);
    if (_appBarOpacity != newOpacity) {
      setStateIfMounted(() {
        _appBarOpacity = newOpacity;
      });
    }
  }

  void _onSearchChanged() {
    if (!mounted) return;
    if (_userType == 'client') {
      _applyWorkerFilters();
    } else {
      _applyJobFilters();
    }
  }

  Future<void> _determineUserTypeAndLoadData() async {
    if (!mounted) return;
    setStateIfMounted(() {
      _isLoading = true;
    });
    _fabAnimationController.forward(); // Animate FAB in

    try {
      final userProfile = await _authService.getCurrentUserProfile();
      if (!mounted) return; // Check mount status after async call

      if (userProfile == null) {
        // Handle case where user profile might not exist (e.g., guest or error)
        setStateIfMounted(() {
          _userType = 'client'; // Default to client view
          _currentUser = null;
        });
      } else {
        setStateIfMounted(() {
          _currentUser = userProfile;
          _userType =
              userProfile.role.toLowerCase() == 'worker' ? 'worker' : 'client';
        });
      }

      // Reset filters on user type determination or initial load
      _filterSelectedLocation = _tempSelectedLocation = 'All';
      _filterSelectedCategory = _tempSelectedCategory = 'All';
      _filterSelectedJobStatus = _tempSelectedJobStatus = 'All';

      await _refreshData(
          isInitialLoad:
              true); // Load initial data based on determined user type
    } catch (e, s) {
      print('FATAL ERROR: Determining user type failed: $e\n$s');
      if (mounted) {
        // Use context safely only if mounted
        final strings = AppLocalizations.of(context);
        _showErrorSnackbar(
            strings?.snackErrorLoadingProfile ?? 'Error loading profile.',
            isCritical: true);
        // Default to client view on critical error
        setStateIfMounted(() {
          _userType = 'client';
          _isLoading = false; // Ensure loading stops on error
        });
      }
    } finally {
      // Ensure loading indicator hides even if there was an error during loading
      await Future.delayed(const Duration(
          milliseconds: 300)); // Small delay for smoother transition
      if (mounted && _isLoading) {
        setStateIfMounted(() => _isLoading = false);
      }
    }
  }

  Future<void> _refreshData({bool isInitialLoad = false}) async {
    if (!mounted) return;
    // Only set loading if not already loading or if it's the initial load
    if (isInitialLoad || !_isLoading) {
      setStateIfMounted(() => _isLoading = true);
    }

    try {
      if (_userType == 'client') {
        await _loadWorkers();
      } else {
        await _loadJobs();
      }
    } catch (e, s) {
      print('ERROR: Refreshing data failed: $e\n$s');
      if (mounted) {
        final strings = AppLocalizations.of(context);
        _showErrorSnackbar(strings?.snackErrorLoading ?? 'Failed to refresh.');
      }
    } finally {
      // Ensure loading indicator eventually hides
      await Future.delayed(const Duration(
          milliseconds: 400)); // Give pull-to-refresh animation time
      if (mounted && _isLoading) {
        setStateIfMounted(() => _isLoading = false);
      }
    }
  }

  void setStateIfMounted(VoidCallback f) {
    if (mounted) setState(f);
  }

  // --- Data Loading ---

  // This method seems redundant if _determineUserTypeAndLoadData gets the profile.
  // Kept for potential future use or if called independently.
  Future<void> _loadUserProfile() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    final strings = AppLocalizations.of(context);
    if (strings == null) {
      print(
          "Error: AppLocalizations not found in context during profile load.");
      if (mounted) {
        setState(() => _isLoading = false);
        _showErrorSnackbar('Error: Localization service not available.',
            isCritical: true);
      }
      return;
    }

    try {
      final userData = await _firebaseService.getCurrentUserProfile();
      if (!mounted) return;
      setState(() {
        _currentUser = userData; // Update current user if needed
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading user profile: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        final errorMsg =
            strings.snackErrorLoadingProfile ?? 'Error loading profile:';
        _showErrorSnackbar('$errorMsg $e');
      }
    }
  }

  Future<void> _loadWorkers() async {
    if (!mounted) return;
    print("DEBUG: Loading workers...");
    try {
      final workers = await _firebaseService.getWorkers();
      if (!mounted) return;
      print("DEBUG: Fetched ${workers.length} workers.");

      _dynamicLocations.clear();
      _dynamicLocations.add('All');
      final Set<String> dynamicCategories = {'All', ..._baseCategories};

      for (var worker in workers) {
        if (worker.location.isNotEmpty) {
          _dynamicLocations.add(worker.location);
        }
        // Dynamic Category logic (ensure 'Other' isn't duplicated)
        if (worker.profession.isNotEmpty) {
          final professionLower = worker.profession.toLowerCase();
          final professionTrimmed = worker.profession.trim();
          bool isBase = _baseCategories.any(
              (b) => b != 'All' && professionLower.contains(b.toLowerCase()));
          if (!isBase &&
              !_baseCategories.contains(professionTrimmed) &&
              professionTrimmed.isNotEmpty &&
              professionTrimmed.toLowerCase() != 'other') {
            dynamicCategories.add(professionTrimmed);
          }
        }
      }

      final sortedLocations = _dynamicLocations.toList()..sort();
      final sortedCategories = dynamicCategories.toList()
        ..sort((a, b) => a == 'All' ? -1 : (b == 'All' ? 1 : a.compareTo(b)));

      // Sort by rating for featured list
      List<Worker> sortedByRating = List.from(workers)
        ..sort((a, b) => (b.rating ?? 0.0).compareTo(a.rating ?? 0.0));
      final featured = sortedByRating.take(5).toList(); // Take top 5 rated

      setStateIfMounted(() {
        _workers = workers;
        _featuredWorkers = featured;
        _locations = sortedLocations;
        _availableCategories = sortedCategories;
        _applyWorkerFilters(); // Apply filters after loading
      });
    } catch (e, s) {
      print("DEBUG: Error loading workers: $e\n$s");
      if (mounted) {
        final strings = AppLocalizations.of(context);
        _showErrorSnackbar(
            strings?.snackErrorLoading ?? "Error fetching professionals.",
            isCritical: true);
      }
      // Reset lists on error
      setStateIfMounted(() {
        _workers = [];
        _featuredWorkers = [];
        _filteredWorkers = [];
      });
    }
  }

  Future<void> _loadJobs_loadJobs() async {
    if (!mounted) return;
    print("DEBUG: Loading jobs...");
    try {
      final jobs = await _firebaseService.getJobs();
      if (!mounted) return;
      print("DEBUG: Fetched ${jobs.length} jobs.");

      // Sort by creation date for featured list (newest first)
      List<Job> openJobs = jobs
          .where((j) => j.status.toLowerCase() == 'open')
          .toList()
        ..sort((a, b) =>
            (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
      final featured = openJobs.take(5).toList(); // Take 5 newest open jobs

      setStateIfMounted(() {
        _jobs = jobs;
        _featuredJobs = featured;
        _applyJobFilters(); // Apply filters after loading
      });
    } catch (e, s) {
      print("DEBUG: Error loading jobs: $e\n$s");
      if (mounted) {
        final strings = AppLocalizations.of(context);
        _showErrorSnackbar(strings?.snackErrorLoading ?? "Error fetching jobs.",
            isCritical: true);
      }
      // Reset lists on error
      setStateIfMounted(() {
        _jobs = [];
        _featuredJobs = [];
        _filteredJobs = [];
      });
    }
  }

  void _applyWorkerFilters() {
    if (!mounted) return;
    final query = _searchController.text.toLowerCase().trim();
    final String allKey = 'All'; // Use constant for 'All'

    // Handle empty list case explicitly
    if (_workers.isEmpty && !_isLoading) {
      setStateIfMounted(() => _filteredWorkers = []);
      return;
    }

    final List<Worker> filtered = _workers.where((worker) {
      // Use null-aware operators and provide defaults for safety
      final locationMatch = (_filterSelectedLocation == allKey ||
          (worker.location.toLowerCase() ?? '') ==
              _filterSelectedLocation.toLowerCase());
      final categoryMatch = (_filterSelectedCategory == allKey ||
          (worker.profession.toLowerCase() ?? '')
              .contains(_filterSelectedCategory.toLowerCase()));
      final searchMatch = query.isEmpty
          ? true
          : ((worker.name.toLowerCase() ?? '').contains(query) ||
              (worker.profession.toLowerCase() ?? '').contains(query) ||
              (worker.location.toLowerCase() ?? '').contains(query) ||
              (worker.skills.any((s) => (s.toLowerCase() ?? '')
                  .contains(query))) || // Safe list check
              (worker.about.toLowerCase() ?? '').contains(query));
      return locationMatch && categoryMatch && searchMatch;
    }).toList();

    print(
        "DEBUG: Workers filtered: ${filtered.length} results for query '$query', loc '$_filterSelectedLocation', cat '$_filterSelectedCategory'");
    setStateIfMounted(() {
      _filteredWorkers = filtered;
    });
  }

  void _applyJobFilters() {
    if (!mounted) return;
    final query = _searchController.text.toLowerCase().trim();
    final String allKey = 'All';

    // Handle empty list case explicitly
    if (_jobs.isEmpty && !_isLoading) {
      setStateIfMounted(() => _filteredJobs = []);
      return;
    }

    final List<Job> filtered = _jobs.where((job) {
      // Use null-aware operators and provide defaults for safety
      final statusMatch = (_filterSelectedJobStatus == allKey ||
          (job.status.toLowerCase() ?? '') ==
              _filterSelectedJobStatus.toLowerCase());
      final searchMatch = query.isEmpty
          ? true
          : ((job.title.toLowerCase() ?? '').contains(query) ||
              (job.description.toLowerCase() ?? '').contains(query) ||
              (job.location.toLowerCase() ?? '').contains(query));
      return statusMatch && searchMatch;
    }).toList();

    print(
        "DEBUG: Jobs filtered: ${filtered.length} results for query '$query', status '$_filterSelectedJobStatus'");
    setStateIfMounted(() {
      _filteredJobs = filtered;
    });
  }

  // --- Navigation ---
  void _navigateToCreateJob({String? preselectedWorkerId}) {
    Navigator.push(
            context,
            _createFadeRoute(
                CreateJobScreen(preselectedWorkerId: preselectedWorkerId)))
        .then((jobCreated) {
      // Refresh data if a job was successfully created
      if (jobCreated == true) _refreshData();
    });
  }

  void _navigateToWorkerDetails(Worker worker) {
    Navigator.push(
        context, _createFadeRoute(WorkerDetailScreen(worker: worker)));
  }

  void _navigateToJobDetails(Job job) {
    Navigator.push(context, _createFadeRoute(JobDetailScreen(job: job))).then(
        (_) =>
            _refreshData()); // Refresh data after potentially updating job status
  }

  void _navigateToCreateProfile() {
    Navigator.push(context, _createFadeRoute(const ProfessionalSetupScreen()))
        .then((profileUpdated) {
      // Reload user type and data if profile was potentially updated
      if (profileUpdated == true) _determineUserTypeAndLoadData();
    });
  }

  void _navigateToNotifications() {
    Navigator.push(context, _createFadeRoute(const NotificationsScreen()));
  }

  void _navigateToHistory() {
    Navigator.push(context, _createFadeRoute(const JobHistoryScreen()));
  }

  // Helper for consistent page transitions
  Route _createFadeRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
      transitionDuration:
          const Duration(milliseconds: 300), // Adjust duration as needed
    );
  }

  // --- UI Building Blocks ---

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final isDarkMode = theme.brightness == Brightness.dark;
    // ** Get localized strings safely **
    final appStrings = AppLocalizations.of(context);

    // Ensure background updates if theme changes externally
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateBackgroundAnimationBasedOnTheme();
    });

    // ** Show loading indicator if still loading OR if localization isn't ready **
    if (_isLoading || appStrings == null) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Center(
            child: CircularProgressIndicator(color: colorScheme.primary)),
      );
    }

    // Now we know appStrings is not null
    print(
        "DEBUG: HomeScreen build | userType: $_userType | FW: ${_filteredWorkers.length} | FJ: ${_filteredJobs.length} | isDark: $isDarkMode | Locale: ${appStrings.locale.languageCode}");

    return Scaffold(
      backgroundColor:
          theme.scaffoldBackgroundColor, // Ensure background color is set
      extendBodyBehindAppBar: true, // Allow body content to go behind AppBar
      appBar:
          _buildAppBar(theme, colorScheme, textTheme, isDarkMode, appStrings),
      body: _buildAnimatedBackground(
        theme,
        isDarkMode,
        child: SafeArea(
            top: false, // Let AppBar handle top padding
            bottom: false, // Let content padding handle bottom space if needed
            child: Padding(
              // Adjust top padding to account for AppBar height + status bar
              padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top +
                      (kToolbarHeight + 10)),
              child: _buildBodyContent(
                  theme, colorScheme, textTheme, isDarkMode, appStrings),
            )),
      ),
      floatingActionButton: _buildAnimatedFloatingActionButton(
          theme, colorScheme, textTheme, appStrings),
    );
  }

  Widget _buildAnimatedBackground(ThemeData theme, bool isDarkMode,
      {required Widget child}) {
    // Select the correct gradient list based on the theme
    final gradientList =
        isDarkMode ? _gentleAnimatedBgGradients : _gentleAnimatedBgGradient;
    // Ensure index is within bounds
    final safeIndex = _currentGradientIndex % gradientList.length;

    return AnimatedContainer(
      duration: const Duration(seconds: 5), // Duration for gradient transition
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: gradientList[safeIndex],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        // Use scaffold background color for light mode as a fallback or base
        color: !isDarkMode ? theme.scaffoldBackgroundColor : null,
      ),
      child: child,
    );
  }

  PreferredSizeWidget _buildAppBar(ThemeData theme, ColorScheme colorScheme,
      TextTheme textTheme, bool isDarkMode, AppStrings appStrings) {
    final appBarTheme = theme.appBarTheme;
    final strings =
        AppLocalizations.of(context)!; // Use ! because build checked for null

    // Dynamic background based on scroll and theme
    Color appBarBg = appBarTheme.backgroundColor ??
        (isDarkMode ? colorScheme.surface : colorScheme.primary);
    appBarBg =
        appBarBg.withOpacity(0.6 + (0.25 * _appBarOpacity)); // Blend opacity
    // Determine foreground color based on background brightness or theme defaults
    Color appBarFg = appBarTheme.foregroundColor ??
        (ThemeData.estimateBrightnessForColor(appBarBg) == Brightness.dark
            ? Colors.white
            : Colors.black);
    // Icon color can be themed or default to foreground
    Color iconColor = appBarTheme.iconTheme?.color ?? appBarFg;

    return PreferredSize(
      preferredSize: const Size.fromHeight(
          kToolbarHeight + 10), // Standard AppBar height + extra padding
      child: AnimatedOpacity(
        duration: _animationDuration, // Use defined animation duration
        opacity: _appBarOpacity.clamp(0.4, 1.0), // Clamp opacity for visibility
        child: ClipRect(
          // Clip the blur effect
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(
                sigmaX: 5.0 * (1 - _appBarOpacity),
                sigmaY: 5.0 *
                    (1 - _appBarOpacity)), // Blur intensity based on scroll
            child: AppBar(
              backgroundColor:
                  (appBarTheme.backgroundColor ?? colorScheme.surface)
                      .withOpacity(
                          0.85 * _appBarOpacity), // Semi-transparent background
              elevation: appBarTheme.elevation ?? 0, // Use theme elevation or 0
              scrolledUnderElevation: appBarTheme.scrolledUnderElevation ?? 0,
              titleSpacing: 16.0,
              title: _buildGreeting(textTheme, colorScheme, appStrings),
              actions: _buildAppBarActions(theme, colorScheme, appStrings,
                  isDarkMode, strings, iconColor), // Pass needed params
              iconTheme: appBarTheme.iconTheme?.copyWith(
                  color:
                      iconColor), // Ensure icons respect theme/calculated color
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGreeting(
      TextTheme textTheme, ColorScheme colorScheme, AppStrings appStrings) {
    // Determine title based on user type
    String title = _userType == 'client'
        ? appStrings.findExpertsTitle
        : appStrings.yourJobFeedTitle;
    // Personalize greeting if user data is available
    String? firstName = _currentUser?.name.split(' ').first;
    String welcomeMessage = firstName != null && firstName.isNotEmpty
        ? appStrings.helloUser(firstName) // Use localized greeting
        : title; // Fallback to generic title

    // Style the greeting text
    TextStyle? greetingStyle = textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w600,
        // Add subtle shadow for depth
        shadows: [
          Shadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ]);

    // Animate the greeting text entrance
    return FadeInLeft(
      delay: const Duration(milliseconds: 200),
      duration: _animationDuration,
      child: Text(
        welcomeMessage,
        style: greetingStyle,
        overflow: TextOverflow.ellipsis, // Prevent overflow
      ),
    );
  }

  List<Widget> _buildAppBarActions(
      ThemeData theme,
      ColorScheme colorScheme,
      AppStrings appStrings,
      bool isDarkMode,
      AppStrings strings,
      Color iconColor) {
    int notificationCount = _random.nextInt(5); // Example notification count
    List<Color> notificationGradient = [
      colorScheme.error,
      colorScheme.errorContainer ?? colorScheme.error.withOpacity(0.7)
    ];

    return [
      FadeInRight(
        delay: const Duration(milliseconds: 300),
        duration: _animationDuration,
        child: Row(
          mainAxisSize: MainAxisSize.min, // Keep actions compact
          children: [
            // Notification Icon with Badge
            _buildAppBarAction(
                theme,
                colorScheme,
                notificationGradient,
                Icons.notifications_active_outlined,
                _navigateToNotifications,
                iconColor,
                notificationCount: notificationCount,
                tooltip: appStrings.notificationTitle),
            // History Icon
            _buildAppBarAction(theme, colorScheme, notificationGradient,
                Icons.history_edu_outlined, _navigateToHistory, iconColor,
                tooltip: appStrings.navHistory),
            // Theme Toggle Icon Button
            IconButton(
              icon: Icon(
                  isDarkMode ? Icons.wb_sunny_outlined : Icons.nightlight_round,
                  color: iconColor),
              tooltip: isDarkMode
                  ? strings.themeTooltipLight
                  : strings.themeTooltipDark, // Localized tooltip
              onPressed: () {
                try {
                  // Use Provider to toggle theme
                  Provider.of<ThemeProvider>(context, listen: false)
                      .toggleTheme();
                } catch (e) {
                  print("Error accessing ThemeProvider: $e");
                  _showErrorSnackbar("Could not toggle theme."); // Inform user
                }
              },
            ),
            // Language Toggle Icon Button
            IconButton(
              icon: Icon(Icons.language, color: iconColor),
              tooltip: strings.languageToggleTooltip, // Localized tooltip
              onPressed: () {
                try {
                  final localeProvider =
                      Provider.of<LocaleProvider>(context, listen: false);
                  final currentLocale = localeProvider.locale;
                  // Simple toggle between English and Amharic (example)
                  final nextLocale = currentLocale.languageCode == 'en'
                      ? const Locale('am')
                      : const Locale('en');
                  localeProvider.setLocale(nextLocale);
                  // Reload data after locale change to get localized content/strings
                  // Use addPostFrameCallback to ensure context is valid after build
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      _determineUserTypeAndLoadData(); // Reload all data and reset state based on new locale
                    }
                  });
                } catch (e) {
                  print("Error accessing LocaleProvider: $e");
                  _showErrorSnackbar(
                      "Could not change language."); // Inform user
                }
              },
            ),
            const SizedBox(width: 8), // Padding at the end
          ],
        ),
      )
    ];
  }

  Widget _buildAppBarAction(
      ThemeData theme,
      ColorScheme colorScheme,
      List<Color> notificationGradient,
      IconData icon,
      VoidCallback onPressed,
      Color iconColor,
      {int? notificationCount,
      required String tooltip}) {
    // Determine badge text color based on badge background brightness
    final badgeTextColor =
        ThemeData.estimateBrightnessForColor(colorScheme.error) ==
                Brightness.dark
            ? Colors.white
            : Colors.black;

    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: 4.0), // Spacing between icons
      child: Center(
        // Ensure vertical alignment
        child: IconButton(
          icon: Stack(
            clipBehavior: Clip.none, // Allow badge to overflow
            alignment: Alignment.center,
            children: [
              Icon(icon,
                  size: 26, color: iconColor.withOpacity(0.9)), // Main icon
              // Notification Badge (if count > 0)
              if (notificationCount != null && notificationCount > 0)
                Positioned(
                  top: -4, // Position badge slightly above
                  right: -4, // Position badge slightly to the right
                  child: BounceInDown(
                    // Animated entrance for badge
                    delay: const Duration(milliseconds: 500),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                          gradient: LinearGradient(
                              colors:
                                  notificationGradient), // Use gradient for badge
                          shape: BoxShape.circle,
                          // Add border for contrast against AppBar
                          border: Border.all(
                              color: colorScheme.surface.withOpacity(0.8),
                              width: 1.5)),
                      constraints: const BoxConstraints(
                          minWidth: 20, minHeight: 20), // Ensure minimum size
                      child: Text(
                        '$notificationCount',
                        // Use theme text style with calculated color
                        style: theme.textTheme.labelSmall?.copyWith(
                                color: badgeTextColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 10) ??
                            TextStyle(
                                color: badgeTextColor,
                                fontSize: 10,
                                fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          onPressed: onPressed,
          splashRadius: 24, // Define splash area size
          tooltip: tooltip, // Accessibility feature
          color: iconColor, // Ensure icon color is applied
          splashColor: colorScheme.primary.withOpacity(0.2), // Themed splash
          highlightColor:
              colorScheme.primary.withOpacity(0.1), // Themed highlight
          visualDensity: VisualDensity.compact, // Reduce padding
        ),
      ),
    );
  }

  Widget _buildBodyContent(ThemeData theme, ColorScheme colorScheme,
      TextTheme textTheme, bool isDarkMode, AppStrings appStrings) {
    // Use AnimatedSwitcher for smooth transition between loading and content
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 600), // Animation duration
      switchInCurve: Curves.easeOutQuart, // Animation curves
      switchOutCurve: Curves.easeInQuart,
      transitionBuilder: (child, animation) {
        // Define entrance animation (fade + slide + scale)
        final offsetAnimation = Tween<Offset>(
                begin: const Offset(0.0, 0.2), end: Offset.zero)
            .animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutQuart));
        final scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutQuart));
        return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
                scale: scaleAnimation,
                child:
                    SlideTransition(position: offsetAnimation, child: child)));
      },
      child: _isLoading
          ? _buildShimmerLoading(
              theme, colorScheme, isDarkMode) // Show shimmer if loading
          : _buildMainContent(theme, colorScheme, textTheme, isDarkMode,
              appStrings), // Show main content otherwise
    );
  }

  Widget _buildMainContent(ThemeData theme, ColorScheme colorScheme,
      TextTheme textTheme, bool isDarkMode, AppStrings appStrings) {
    // Determine if the relevant list is empty
    bool isEmpty = (_userType == 'client' && _filteredWorkers.isEmpty) ||
        (_userType == 'worker' && _filteredJobs.isEmpty);

    // Use LiquidPullToRefresh for a nice refresh animation
    return LiquidPullToRefresh(
      key: ValueKey<String>(
          "content_loaded_${_userType}_${theme.brightness}"), // Key to rebuild on theme/type change
      onRefresh: _refreshData, // Refresh function
      color: colorScheme.surfaceContainerHighest, // Color of the liquid blob
      backgroundColor: colorScheme.secondary, // Background color during refresh
      height: 60, // Height of the refresh indicator area
      animSpeedFactor: 1.5, // Speed of the animation
      showChildOpacityTransition: false, // Avoid default opacity transition
      child: CustomScrollView(
        controller:
            _scrollController, // Attach scroll controller for AppBar opacity
        slivers: [
          // Header Section (Search Bar & Filter Button)
          SliverToBoxAdapter(
              key: const ValueKey("search_filter_header"),
              child: FadeInDown(
                  // Animate entrance
                  duration: _animationDuration,
                  child: _buildSearchAndFilterHeader(
                      theme, colorScheme, textTheme, isDarkMode, appStrings))),
          // Featured Section (Carousel)
          SliverToBoxAdapter(
              key: const ValueKey("featured_section"),
              child: _buildFeaturedSection(
                  theme, colorScheme, textTheme, isDarkMode, appStrings)),
          // Content Section (Grid or Empty State)
          isEmpty
              ? SliverFillRemaining(
                  // Use SliverFillRemaining for empty state to fill viewport
                  key: const ValueKey("empty_state_sliver"),
                  hasScrollBody: false, // Important for centering content
                  child: _buildEmptyStateWidget(
                      theme, colorScheme, textTheme, appStrings),
                )
              : _buildContentGridSliver(theme, colorScheme, textTheme,
                  isDarkMode), // Build grid if not empty
        ],
      ),
    );
  }

  Widget _buildSearchAndFilterHeader(ThemeData theme, ColorScheme colorScheme,
      TextTheme textTheme, bool isDarkMode, AppStrings appStrings) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          16.0, 16.0, 16.0, 24.0), // Padding around the header
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center, // Align items vertically
        children: [
          // Search Bar takes most space
          Expanded(
              child:
                  _buildSearchBar(theme, colorScheme, textTheme, appStrings)),
          const SizedBox(width: 12), // Spacing between search and filter
          // Filter Button
          _buildFilterButton(theme, colorScheme, textTheme, isDarkMode),
        ],
      ),
    );
  }

  Widget _buildSearchBar(ThemeData theme, ColorScheme colorScheme,
      TextTheme textTheme, AppStrings appStrings) {
    final inputTheme = theme.inputDecorationTheme;
    final iconColor = theme.iconTheme.color ??
        colorScheme.onSurfaceVariant; // Use themed icon color

    return Container(
      decoration: BoxDecoration(
          // Use themed fill color or a semi-transparent surface color
          color: inputTheme.fillColor ??
              colorScheme.surfaceContainerHighest.withOpacity(0.8),
          borderRadius: BorderRadius.circular(30.0), // Rounded corners
          // Add shadow for depth
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(
                    theme.brightness == Brightness.dark ? 0.5 : 0.1),
                blurRadius: 12,
                spreadRadius: -4,
                offset: const Offset(0, 4))
          ]),
      child: TextField(
        controller: _searchController, // Control text input
        style: textTheme.bodyLarge
            ?.copyWith(fontSize: 15), // Text style inside the bar
        decoration: InputDecoration(
          // Localized hint text based on user type
          hintText: _userType == 'client'
              ? appStrings.searchHintProfessionals
              : appStrings.searchHintJobs,
          // Use themed hint style or a default
          hintStyle: inputTheme.hintStyle ??
              textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant.withOpacity(0.7)),
          // Search icon prefix
          prefixIcon: Padding(
            padding:
                const EdgeInsets.only(left: 18, right: 12), // Adjust padding
            child: Icon(Icons.search_rounded, color: iconColor, size: 22),
          ),
          prefixIconConstraints: const BoxConstraints(
              minWidth: 0, minHeight: 0), // Allow tight icon placement
          // Clear button suffix (only shows when text exists)
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear_rounded, color: iconColor, size: 20),
                  onPressed: () {
                    _searchController.clear(); // Clear text field
                    // Re-apply filters after clearing search
                    if (_userType == 'client') {
                      _applyWorkerFilters();
                    } else {
                      _applyJobFilters();
                    }
                  },
                  splashRadius: 20, // Smaller splash for suffix icon
                )
              : null,
          // Remove default borders
          border: inputTheme.border ?? InputBorder.none,
          enabledBorder:
              inputTheme.enabledBorder ?? inputTheme.border ?? InputBorder.none,
          focusedBorder:
              inputTheme.focusedBorder ?? inputTheme.border ?? InputBorder.none,
          // Adjust content padding
          contentPadding: inputTheme.contentPadding ??
              const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        ),
      ),
    );
  }

  Widget _buildFilterButton(ThemeData theme, ColorScheme colorScheme,
      TextTheme textTheme, bool isDarkMode) {
    // Check if any filters are currently active
    bool filtersActive = (_userType == 'client' &&
            (_filterSelectedLocation != 'All' ||
                _filterSelectedCategory != 'All')) ||
        (_userType == 'worker' && _filterSelectedJobStatus != 'All');

    // Define colors for default and active states
    Color iconSelectedColor = colorScheme
        .onSecondary; // Icon color when active (on secondary background)
    Color iconDefaultColor =
        colorScheme.onSurfaceVariant; // Icon color when inactive
    // Define gradients for default and active states
    List<Color> defaultGradient = isDarkMode
        ? [
            colorScheme.surfaceContainerHighest,
            colorScheme.surface
          ] // Dark mode default gradient
        : [
            theme.cardColor.withOpacity(0.8),
            theme.canvasColor.withOpacity(0.8)
          ]; // Light mode default gradient
    List<Color> activeGradient = [
      colorScheme.secondary,
      colorScheme.secondaryContainer ?? colorScheme.secondary.withOpacity(0.7)
    ]; // Active gradient (using secondary color)

    // Use AnimatedContainer for smooth transition between states
    return AnimatedContainer(
      duration: _animationDuration, // Animation duration
      curve: Curves.easeInOut, // Animation curve
      decoration: BoxDecoration(
          // Apply gradient based on filter state
          gradient: LinearGradient(
            colors: filtersActive ? activeGradient : defaultGradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shape: BoxShape.circle, // Circular shape
          // Adjust shadow based on filter state
          boxShadow: [
            BoxShadow(
                color: filtersActive
                    ? colorScheme.secondary.withOpacity(isDarkMode ? 0.4 : 0.3)
                    : Colors.black.withOpacity(isDarkMode ? 0.5 : 0.1),
                blurRadius: filtersActive ? 10 : 12,
                spreadRadius: filtersActive ? 1 : -4,
                offset: Offset(
                    0,
                    filtersActive
                        ? 3
                        : 4) // Slightly different offset when active
                )
          ]),
      child: Material(
        // Needed for InkWell splash effect
        color: Colors.transparent,
        shape: const CircleBorder(), // Ensure splash conforms to circle
        child: InkWell(
          onTap: () => _showFilterPanel(
              theme, colorScheme, textTheme), // Show filter panel on tap
          borderRadius: BorderRadius.circular(25), // Define splash area shape
          splashColor: colorScheme.primary.withOpacity(0.3), // Themed splash
          highlightColor:
              colorScheme.primary.withOpacity(0.15), // Themed highlight
          child: Padding(
            padding: const EdgeInsets.all(13.0), // Padding inside the button
            child: Icon(
              filtersActive
                  ? Icons.filter_alt_rounded
                  : Icons.filter_list_rounded, // Change icon based on state
              color: filtersActive
                  ? iconSelectedColor
                  : iconDefaultColor, // Change color based on state
              size: 24,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeaturedSection(ThemeData theme, ColorScheme colorScheme,
      TextTheme textTheme, bool isDarkMode, AppStrings appStrings) {
    // Check if there is featured content to display
    bool hasFeatured = (_userType == 'client' && _featuredWorkers.isNotEmpty) ||
        (_userType == 'worker' && _featuredJobs.isNotEmpty);
    if (!hasFeatured) {
      return const SizedBox.shrink(); // Return empty box if no featured content
    }

    // Determine title and item count based on user type
    String title = _userType == 'client'
        ? appStrings.featuredPros
        : appStrings.featuredJobs;
    int itemCount =
        _userType == 'client' ? _featuredWorkers.length : _featuredJobs.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start, // Align title to the left
      children: [
        // Section Title
        Padding(
          padding: const EdgeInsets.fromLTRB(
              16.0, 16.0, 16.0, 12.0), // Padding around title
          child: FadeInLeft(
              // Animate title entrance
              duration: _animationDuration,
              delay: const Duration(milliseconds: 100),
              child: Text(title,
                  style: textTheme.titleMedium?.copyWith(
                      color: colorScheme.onSurface
                          .withOpacity(0.7))) // Style title
              ),
        ),
        // Carousel Slider for Featured Items
        SizedBox(
          height: 180, // Fixed height for the carousel
          child: CarouselSlider.builder(
            carouselController:
                _carouselController, // Controller for programmatic control
            itemCount: itemCount, // Number of items
            itemBuilder: (context, index, realIndex) {
              // Build the appropriate card based on user type
              return Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6.0), // Spacing between cards
                child: _userType == 'client'
                    ? FeaturedWorkerCard(
                        // Use FeaturedWorkerCard for clients
                        worker: _featuredWorkers[index],
                        onTap: () =>
                            _navigateToWorkerDetails(_featuredWorkers[index]),
                      )
                    : NewFeaturedJobCard(
                        // ** Use NewFeaturedJobCard for workers **
                        job: _featuredJobs[index],
                        onTap: () =>
                            _navigateToJobDetails(_featuredJobs[index]),
                      ),
              );
            },
            options: CarouselOptions(
              height: 180, // Height of the carousel viewport
              viewportFraction:
                  0.65, // How much of the next/prev card is visible
              enableInfiniteScroll: itemCount > 2, // Only loop if enough items
              autoPlay: true, // Automatically slide cards
              enlargeCenterPage: true, // Make the center card larger
              enlargeFactor: 0.2, // How much larger the center card becomes
            ),
          ),
        ),
        const SizedBox(height: 24), // Spacing after the carousel
      ],
    );
  }

  Widget _buildContentGridSliver(ThemeData theme, ColorScheme colorScheme,
      TextTheme textTheme, bool isDarkMode) {
    // Determine grid layout based on screen width
    int crossAxisCount = MediaQuery.of(context).size.width > 700
        ? 3
        : 2; // More columns on wider screens
    // Determine item count based on user type
    int itemCount =
        _userType == 'client' ? _filteredWorkers.length : _filteredJobs.length;

    // Use SliverPadding for padding around the grid
    return SliverPadding(
      key: ValueKey(
          'content_grid_data_${_userType}_${itemCount}_${theme.brightness}'), // Key for efficient rebuilds
      padding: const EdgeInsets.only(
          left: 12, right: 12, bottom: 100, top: 4), // Padding (bottom for FAB)
      sliver: AnimationLimiter(
        // Enables staggered animations
        child: SliverMasonryGrid.count(
          // Use MasonryGrid for variable height items
          crossAxisCount: crossAxisCount, // Number of columns
          mainAxisSpacing: 14, // Spacing between items vertically
          crossAxisSpacing: 14, // Spacing between items horizontally
          childCount: itemCount, // Total number of items
          itemBuilder: (context, index) {
            // Calculate animation delay for staggered effect
            int delayMs = ((index ~/ crossAxisCount) * 100 +
                (index % crossAxisCount) * 50);
            // Wrap each item in animation configuration
            return AnimationConfiguration.staggeredGrid(
              position: index,
              duration: const Duration(milliseconds: 500), // Animation duration
              columnCount: crossAxisCount, // Inform animation about grid layout
              child: ScaleAnimation(
                // Scale animation
                delay: Duration(milliseconds: delayMs),
                curve: Curves.easeOutBack, // Animation curve
                child: FadeInAnimation(
                  // Fade-in animation
                  delay: Duration(milliseconds: delayMs),
                  curve: Curves.easeOutCubic,
                  child: _userType == 'client'
                      ? UltimateGridWorkerCard(
                          // Use UltimateGridWorkerCard for clients
                          worker: _filteredWorkers[index],
                          onTap: () =>
                              _navigateToWorkerDetails(_filteredWorkers[index]),
                          onBookNow: () => _navigateToCreateJob(
                              preselectedWorkerId: _filteredWorkers[index].id),
                        )
                      : NewJobGridCard(
                          // ** Use NewJobGridCard for workers **
                          job: _filteredJobs[index],
                          onTap: () =>
                              _navigateToJobDetails(_filteredJobs[index]),
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildShimmerLoading(
      ThemeData theme, ColorScheme colorScheme, bool isDarkMode) {
    int crossAxisCount = MediaQuery.of(context).size.width > 700 ? 3 : 2;
    // Define shimmer colors based on theme
    Color shimmerBase = isDarkMode ? (Colors.grey[850]!) : (Colors.grey[300]!);
    Color shimmerHighlight =
        isDarkMode ? (Colors.grey[700]!) : (Colors.grey[100]!);
    // Provide fallback strings if localization isn't ready yet
    final appStrings =
        AppLocalizations.of(context) ?? AppStringsEn(); // Use English fallback

    // Use CustomScrollView for shimmer layout mirroring the main content
    return CustomScrollView(
        key: ValueKey('shimmer_grid_${theme.brightness}'), // Key for rebuilds
        physics:
            const NeverScrollableScrollPhysics(), // Disable scrolling during shimmer
        slivers: [
          // Shimmer for Header (fades out to reveal actual header)
          SliverToBoxAdapter(
              child: FadeOut(
                  // Fade out animation
                  child: _buildSearchAndFilterHeader(theme, colorScheme,
                      theme.textTheme, isDarkMode, appStrings))),
          // Shimmer for Featured Section
          SliverToBoxAdapter(
              child: _buildFeaturedShimmer(theme, colorScheme, isDarkMode,
                  shimmerBase, shimmerHighlight)),
          // Shimmer for Content Grid
          SliverPadding(
            padding:
                const EdgeInsets.only(left: 12, right: 12, bottom: 100, top: 4),
            sliver: SliverMasonryGrid.count(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              itemBuilder: (context, index) => _buildGridShimmerItem(
                  theme, colorScheme, isDarkMode, shimmerBase, shimmerHighlight,
                  index: index),
              childCount: 6, // Show a fixed number of shimmer items
            ),
          ),
        ]);
  }

  Widget _buildFeaturedShimmer(ThemeData theme, ColorScheme colorScheme,
      bool isDarkMode, Color shimmerBase, Color shimmerHighlight) {
    final textTheme = theme.textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Shimmer for Featured Section Title
          Padding(
              padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 12.0),
              child: Shimmer.fromColors(
                  baseColor: shimmerBase,
                  highlightColor: shimmerHighlight,
                  period: _shimmerDuration,
                  child: Container(
                      width: 150,
                      height: textTheme.titleMedium?.fontSize ?? 16,
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(
                              4)) // Use white as placeholder color inside shimmer
                      ))),
          // Shimmer for Carousel Items
          SizedBox(
            height: 180,
            child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: 3, // Show 3 shimmer placeholders
                padding: const EdgeInsets.only(left: 10),
                itemBuilder: (context, index) {
                  return Shimmer.fromColors(
                    baseColor: shimmerBase,
                    highlightColor: shimmerHighlight,
                    period: _shimmerDuration,
                    child: Container(
                      width: MediaQuery.of(context).size.width *
                          0.65, // Match featured card width
                      height: 170, // Match featured card height (approx)
                      margin: const EdgeInsets.symmetric(horizontal: 6.0),
                      decoration: BoxDecoration(
                        color: theme
                            .cardColor, // Use theme card color as base for shimmer item
                        borderRadius: BorderRadius.circular(
                            16), // Match card border radius
                      ),
                    ),
                  );
                }),
          ),
        ],
      ),
    );
  }

  Widget _buildGridShimmerItem(ThemeData theme, ColorScheme colorScheme,
      bool isDarkMode, Color shimmerBase, Color shimmerHighlight,
      {required int index}) {
    // Add slight height variation for Masonry effect
    double heightVariation = (index % 3 == 0) ? 20 : (index % 3 == 1 ? -15 : 0);
    double baseHeight =
        _userType == 'client' ? 250 : 220; // Base height differs slightly
    double cardHeight =
        (baseHeight + heightVariation).clamp(200, 290); // Clamp height
    // Placeholder color inside shimmer
    final placeholderColor = shimmerBase.withOpacity(0.9);

    return Shimmer.fromColors(
      baseColor: shimmerBase,
      highlightColor: shimmerHighlight,
      period: _shimmerDuration,
      child: Container(
        height: cardHeight,
        decoration: BoxDecoration(
          color: theme.cardColor, // Use theme card color as base
          borderRadius: BorderRadius.circular(24.0), // Match card radius
        ),
        padding: const EdgeInsets.all(16.0), // Match card padding
        child: Column(
          // Mimic card layout
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Shimmer for header (differs for worker vs job)
            if (_userType == 'client')
              Row(children: [
                Container(
                    height: 60,
                    width: 60,
                    decoration: BoxDecoration(
                        color: placeholderColor,
                        borderRadius: BorderRadius.circular(15))),
                const SizedBox(width: 12),
                Expanded(
                    child: Container(
                        height: 16,
                        decoration: BoxDecoration(
                            color: placeholderColor,
                            borderRadius: BorderRadius.circular(4))))
              ])
            else
              Container(
                  height: 18,
                  width: double.infinity,
                  decoration: BoxDecoration(
                      color: placeholderColor,
                      borderRadius: BorderRadius.circular(4))),

            const SizedBox(height: 12),
            // Shimmer for title/name line 1
            Container(
                width: MediaQuery.of(context).size.width * 0.3,
                height: 14,
                decoration: BoxDecoration(
                    color: placeholderColor,
                    borderRadius: BorderRadius.circular(4))),
            const SizedBox(height: 8),
            // Shimmer for subtitle/profession line
            Container(
                width: MediaQuery.of(context).size.width * 0.2,
                height: 12,
                decoration: BoxDecoration(
                    color: placeholderColor,
                    borderRadius: BorderRadius.circular(4))),
            const SizedBox(height: 16),
            // Shimmer for description lines
            Container(
                width: double.infinity,
                height: 12,
                decoration: BoxDecoration(
                    color: placeholderColor,
                    borderRadius: BorderRadius.circular(4))),
            const SizedBox(height: 6),
            Container(
                width: double.infinity,
                height: 12,
                decoration: BoxDecoration(
                    color: placeholderColor,
                    borderRadius: BorderRadius.circular(4))),
            // Extra line for job card description shimmer
            if (_userType != 'client') ...[
              const SizedBox(height: 6),
              Container(
                  width: MediaQuery.of(context).size.width * 0.4,
                  height: 12,
                  decoration: BoxDecoration(
                      color: placeholderColor,
                      borderRadius: BorderRadius.circular(4))),
            ],
            const Spacer(), // Push button to bottom
            // Shimmer for action button
            Align(
                alignment: Alignment.bottomRight,
                child: Container(
                    width: 80,
                    height: 36,
                    decoration: BoxDecoration(
                        color: placeholderColor,
                        borderRadius: BorderRadius.circular(10)))),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyStateWidget(ThemeData theme, ColorScheme colorScheme,
      TextTheme textTheme, AppStrings appStrings) {
    IconData icon = _userType == 'client'
        ? Icons.person_search_outlined
        : Icons.find_in_page_outlined;
    // Use localized strings for message and details
    String message = _userType == 'client'
        ? appStrings.emptyStateProfessionals
        : appStrings.emptyStateJobs;
    String details = appStrings.emptyStateDetails;

    return FadeInUp(
      // Animate entrance
      duration: const Duration(milliseconds: 500),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(40.0), // Padding around content
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center, // Center vertically
            children: [
              Icon(icon,
                  size: 90,
                  color: colorScheme.onSurface
                      .withOpacity(0.4)), // Empty state icon
              const SizedBox(height: 24),
              // Main message
              Text(
                message,
                textAlign: TextAlign.center,
                style: textTheme.titleLarge
                    ?.copyWith(color: colorScheme.onSurface.withOpacity(0.7)),
              ),
              const SizedBox(height: 12),
              // Detail message
              Text(
                details,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium
                    ?.copyWith(color: colorScheme.onSurface.withOpacity(0.6)),
              ),
              const SizedBox(height: 35),
              // Refresh Button
              ElevatedButton.icon(
                icon: const Icon(Icons.refresh_rounded, size: 20),
                label: Text(appStrings.refreshButton), // Use localized label
                onPressed: () =>
                    _refreshData(isInitialLoad: true), // Trigger refresh
                // Style the button
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.secondary
                      .withOpacity(0.2), // Subtle background
                  foregroundColor: colorScheme.secondary, // Text/icon color
                  elevation: 0, // No shadow
                  padding:
                      const EdgeInsets.symmetric(horizontal: 30, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                      side: BorderSide(
                          color: colorScheme.secondary
                              .withOpacity(0.5)) // Subtle border
                      ),
                  textStyle: textTheme.labelLarge
                      ?.copyWith(fontSize: 14, color: colorScheme.secondary),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedFloatingActionButton(ThemeData theme,
      ColorScheme colorScheme, TextTheme textTheme, AppStrings appStrings) {
    bool isClient = _userType == 'client';
    final fabTheme = theme.floatingActionButtonTheme;
    // Use themed FAB colors or fallbacks
    final fabBackgroundColor =
        fabTheme.backgroundColor ?? colorScheme.secondary;
    final fabForegroundColor =
        fabTheme.foregroundColor ?? colorScheme.onSecondary;

    // Animate FAB entrance (scale + fade)
    return ScaleTransition(
      scale: CurvedAnimation(
          parent: _fabAnimationController,
          curve: Curves.elasticOut,
          reverseCurve: Curves.easeOutExpo),
      child: FadeTransition(
        opacity: _fabAnimationController,
        child: FloatingActionButton.extended(
          onPressed: isClient
              ? () => _navigateToCreateJob()
              : _navigateToCreateProfile, // Action based on user type
          backgroundColor: fabBackgroundColor,
          foregroundColor: fabForegroundColor,
          elevation: fabTheme.elevation ?? 6.0,
          highlightElevation: fabTheme.highlightElevation ?? 12.0,
          shape: fabTheme.shape ??
              RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(18)), // Themed shape or default
          icon: Padding(
            padding: const EdgeInsets.only(
                right: 6.0), // Space between icon and label
            child: Icon(
                isClient
                    ? Icons.post_add_rounded
                    : Icons.person_pin_circle_rounded,
                size: 24), // Icon based on user type
          ),
          // Localized label based on user type
          label: Text(
              isClient ? appStrings.fabPostJob : appStrings.fabMyProfile,
              style: textTheme.labelLarge
                  ?.copyWith(fontSize: 16, color: fabForegroundColor)),
          // Localized tooltip based on user type
          tooltip: isClient
              ? appStrings.fabPostJobTooltip
              : appStrings.fabMyProfileTooltip,
        ),
      ),
    );
  }

  void _showFilterPanel(
      ThemeData theme, ColorScheme colorScheme, TextTheme textTheme) {
    // Get localized strings safely
    final appStrings = AppLocalizations.of(context);
    if (appStrings == null) {
      _showErrorSnackbar("Cannot open filters: localization not ready.");
      return;
    }

    // Store current selections temporarily
    if (_userType == 'client') {
      _tempSelectedLocation = _filterSelectedLocation;
      _tempSelectedCategory = _filterSelectedCategory;
    } else {
      _tempSelectedJobStatus = _filterSelectedJobStatus;
    }

    showModalBottomSheet(
        context: context,
        backgroundColor:
            Colors.transparent, // Make sheet background transparent for blur
        isScrollControlled: true, // Allow sheet to take variable height
        elevation: 0, // Remove default shadow
        builder: (modalContext) {
          // Use modal context's theme
          final modalTheme = Theme.of(modalContext);
          final modalColorScheme = modalTheme.colorScheme;
          final modalTextTheme = modalTheme.textTheme;
          // We know appStrings is not null here because of the initial check
          final modalAppStrings = AppLocalizations.of(modalContext)!;

          // Use StatefulBuilder to manage the state *within* the bottom sheet
          return StatefulBuilder(
            builder: (BuildContext context, StateSetter setModalState) {
              // DraggableScrollableSheet allows resizing and scrolling
              return DraggableScrollableSheet(
                initialChildSize: 0.65, // Initial height (65% of screen)
                minChildSize: 0.4, // Minimum height
                maxChildSize: 0.9, // Maximum height
                expand: false, // Don't expand to full screen by default
                builder: (_, controller) {
                  // Controller for scrolling inside the sheet
                  // Clip sheet with rounded corners and apply blur
                  return ClipRRect(
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(28)),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(
                          sigmaX: 8.0, sigmaY: 8.0), // Background blur
                      child: Container(
                        decoration: BoxDecoration(
                          // Semi-transparent background over the blur
                          color: modalColorScheme.surface.withOpacity(0.9),
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(28)),
                        ),
                        child: Column(
                          children: [
                            // Drag Handle
                            Container(
                              width: 45,
                              height: 5,
                              margin: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                  color: modalColorScheme.onSurface
                                      .withOpacity(0.4),
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            // Title
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20.0, vertical: 8),
                              child: Text(modalAppStrings.filterOptionsTitle,
                                  style: modalTextTheme
                                      .titleLarge), // Localized title
                            ),
                            Divider(
                                color: modalTheme.dividerColor,
                                height: 1,
                                thickness: 1),
                            // Filter Options (Scrollable)
                            Expanded(
                              child: ListView(
                                controller:
                                    controller, // Attach scroll controller
                                padding: const EdgeInsets.all(20),
                                // Build options based on user type
                                children: _userType == 'client'
                                    ? _buildClientFilterOptions(
                                        modalTheme,
                                        modalColorScheme,
                                        modalTextTheme,
                                        modalAppStrings,
                                        setModalState)
                                    : _buildWorkerFilterOptions(
                                        modalTheme,
                                        modalColorScheme,
                                        modalTextTheme,
                                        modalAppStrings,
                                        setModalState),
                              ),
                            ),
                            Divider(
                                color: modalTheme.dividerColor,
                                height: 1,
                                thickness: 1),
                            // Action Buttons (Apply/Reset)
                            _buildFilterActionButtons(
                                modalTheme,
                                modalColorScheme,
                                modalTextTheme,
                                modalAppStrings,
                                setModalState),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          );
        });
  }

  List<Widget> _buildClientFilterOptions(
      ThemeData theme,
      ColorScheme colorScheme,
      TextTheme textTheme,
      AppStrings appStrings,
      StateSetter setModalState) {
    return [
      // Category Filter Section
      _buildFilterSectionTitle(
          appStrings.filterCategory, textTheme, colorScheme), // Localized title
      _buildChipGroup(
          theme,
          colorScheme,
          textTheme,
          _availableCategories,
          _tempSelectedCategory,
          (val) => setModalState(() =>
              _tempSelectedCategory = val ?? 'All')), // Update temp selection

      const SizedBox(height: 28), // Spacing

      // Location Filter Section
      _buildFilterSectionTitle(
          appStrings.filterLocation, textTheme, colorScheme), // Localized title
      _buildChipGroup(
          theme,
          colorScheme,
          textTheme,
          _locations,
          _tempSelectedLocation,
          (val) => setModalState(() =>
              _tempSelectedLocation = val ?? 'All')), // Update temp selection

      const SizedBox(height: 10), // Bottom padding
    ];
  }

  List<Widget> _buildWorkerFilterOptions(
      ThemeData theme,
      ColorScheme colorScheme,
      TextTheme textTheme,
      AppStrings appStrings,
      StateSetter setModalState) {
    return [
      // Job Status Filter Section
      _buildFilterSectionTitle(appStrings.filterJobStatus, textTheme,
          colorScheme), // Localized title
      _buildChipGroup(
          theme,
          colorScheme,
          textTheme,
          _jobStatuses,
          _tempSelectedJobStatus,
          (val) => setModalState(() =>
              _tempSelectedJobStatus = val ?? 'All'), // Update temp selection
          localizeKey: _getLocalizedJobStatus // Pass localization function
          ),

      const SizedBox(height: 10), // Bottom padding
    ];
  }

  // Helper to get localized status for display in chips
  String _getLocalizedJobStatus(String statusKey, AppStrings appStrings) {
    switch (statusKey.toLowerCase()) {
      case 'open':
        return appStrings.jobStatusOpen;
      case 'assigned':
        return appStrings.jobStatusAssigned;
      case 'completed':
        return appStrings.jobStatusCompleted;
      case 'all':
        return appStrings.filterAll; // Use localized "All"
      default:
        return statusKey; // Fallback
    }
  }

  Widget _buildFilterSectionTitle(
      String title, TextTheme textTheme, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14.0), // Spacing below title
      child: Text(
        title,
        style: textTheme.titleSmall?.copyWith(
            color: colorScheme.onSurface.withOpacity(0.8),
            fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildChipGroup(
      ThemeData theme,
      ColorScheme colorScheme,
      TextTheme textTheme,
      List<String> items,
      String selectedValue,
      ValueChanged<String?> onSelected,
      {String Function(String, AppStrings)? localizeKey}) {
    // Ensure 'All' is selected if current selection is invalid
    if (!items.contains(selectedValue) && selectedValue != 'All') {
      selectedValue = 'All';
    }
    final chipTheme = theme.chipTheme;
    final appStrings =
        AppLocalizations.of(context)!; // Assume context is available

    return Wrap(
      // Arrange chips in a line, wrapping if necessary
      spacing: 10.0, // Horizontal space between chips
      runSpacing: 10.0, // Vertical space between chip lines
      children: items.map((itemKey) {
        // Iterate through internal item keys
        bool isSelected = selectedValue == itemKey;
        // Determine chip colors based on selection state and theme
        Color bgColor = isSelected
            ? (chipTheme.selectedColor ?? colorScheme.primary)
            : (chipTheme.backgroundColor ??
                colorScheme.surfaceContainerHighest);
        Color labelColor = isSelected
            ? (chipTheme.secondaryLabelStyle?.color ??
                colorScheme.onPrimary) // Color for selected label
            : (chipTheme.labelStyle?.color ??
                colorScheme.onSurfaceVariant); // Color for unselected label
        BorderSide borderSide =
            chipTheme.side ?? BorderSide.none; // Use themed border or none

        // Get display text: Use localization function if provided, otherwise use the key
        String displayItem =
            localizeKey != null ? localizeKey(itemKey, appStrings) : itemKey;

        // Build the ChoiceChip
        return ChoiceChip(
          label: Text(displayItem), // Display localized text
          selected: isSelected, // Selection state
          onSelected: (selected) {
            // Callback when chip is tapped
            if (selected) onSelected(itemKey); // Update selection if selected
          },
          backgroundColor: bgColor, // Apply background color
          selectedColor: chipTheme.selectedColor ??
              colorScheme.primary, // Apply selected background color
          labelStyle: (chipTheme.labelStyle ?? textTheme.labelMedium)
              ?.copyWith(color: labelColor), // Apply label style and color
          labelPadding: chipTheme.padding ??
              const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8), // Apply padding
          // Apply shape and border
          shape: chipTheme.shape ??
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: borderSide,
              ),
          elevation: chipTheme.elevation ??
              (isSelected ? 2 : 0), // Elevation based on selection
          pressElevation:
              chipTheme.pressElevation ?? 4, // Elevation when pressed
        );
      }).toList(),
    );
  }

  Widget _buildFilterActionButtons(ThemeData theme, ColorScheme colorScheme,
      TextTheme textTheme, AppStrings appStrings, StateSetter setModalState) {
    final outlinedButtonStyle = theme.outlinedButtonTheme.style;
    final elevatedButtonStyle = theme.elevatedButtonTheme.style;

    return Container(
      // Padding and decoration for the button row container
      padding: const EdgeInsets.fromLTRB(20, 15, 20, 20),
      decoration: BoxDecoration(
          color: colorScheme.surface
              .withOpacity(0.95), // Slightly opaque background
          // Add shadow to separate from content above
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(
                    theme.brightness == Brightness.dark ? 0.3 : 0.1),
                blurRadius: 8,
                spreadRadius: -4,
                offset: const Offset(0, -4) // Shadow above the container
                )
          ]),
      child: Row(
        children: [
          // Reset Button
          OutlinedButton(
            onPressed: () {
              // Reset temporary selections within the modal sheet state
              setModalState(() {
                if (_userType == 'client') {
                  _tempSelectedLocation = 'All';
                  _tempSelectedCategory = 'All';
                } else {
                  _tempSelectedJobStatus = 'All';
                }
              });
              if (mounted) {
                _showSuccessSnackbar(
                    appStrings.filtersResetSuccess); // Show confirmation
              }
            },
            style: outlinedButtonStyle, // Use themed style
            child: Text(appStrings.filterResetButton), // Localized label
          ),
          const Spacer(), // Pushes Apply button to the right
          // Apply Button
          ElevatedButton.icon(
            icon: const Icon(Icons.check_rounded, size: 18),
            label: Text(appStrings.filterApplyButton), // Localized label
            onPressed: () {
              // Apply temporary selections to the main state
              setState(() {
                if (_userType == 'client') {
                  _filterSelectedLocation = _tempSelectedLocation;
                  _filterSelectedCategory = _tempSelectedCategory;
                  _applyWorkerFilters(); // Apply filters immediately
                } else {
                  _filterSelectedJobStatus = _tempSelectedJobStatus;
                  _applyJobFilters(); // Apply filters immediately
                }
              });
              Navigator.pop(context); // Close the bottom sheet
            },
            style: elevatedButtonStyle, // Use themed style
          ),
        ],
      ),
    );
  }

  // --- Utility Methods ---
  void _showErrorSnackbar(String message, {bool isCritical = false}) {
    if (!mounted) return; // Check if widget is still mounted
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(isCritical ? Icons.error_outline : Icons.warning_amber_rounded,
            color: cs.onError, size: 20), // Icon based on criticality
        const SizedBox(width: 12),
        Expanded(
            child: Text(message,
                style: tt.bodyMedium
                    ?.copyWith(color: cs.onError))) // Error message text
      ]),
      backgroundColor: cs.error, // Use error color from theme
      behavior: SnackBarBehavior.floating, // Floating style
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12)), // Rounded corners
      margin: const EdgeInsets.all(16), // Margin around snackbar
      elevation: 6, // Shadow
      duration: Duration(
          seconds: isCritical ? 6 : 4), // Longer duration for critical errors
    ));
  }

  void _showSuccessSnackbar(String message) {
    if (!mounted) return;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;
    // Define success colors explicitly (can be themed if needed)
    final successColor = theme.brightness == Brightness.dark
        ? Colors.green[400]!
        : Colors.green[700]!;
    final onSuccessColor =
        theme.brightness == Brightness.dark ? Colors.black : Colors.white;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(Icons.check_circle_outline_rounded,
            color: onSuccessColor, size: 20), // Success icon
        const SizedBox(width: 12),
        Expanded(
            child: Text(message,
                style: tt.bodyMedium
                    ?.copyWith(color: onSuccessColor))) // Success message text
      ]),
      backgroundColor: successColor, // Use defined success color
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
      elevation: 6,
      duration:
          const Duration(seconds: 2), // Shorter duration for success messages
    ));
  }
} // End of _HomeScreenState

// ============================================================
//      Refactored Cards (Now using AppLocalizations)
// ============================================================

// --- UltimateGridWorkerCard ---
// (Keep this card as it's used for the client view)
class UltimateGridWorkerCard extends StatelessWidget {
  final Worker worker;
  final VoidCallback onTap;
  final VoidCallback onBookNow;
  const UltimateGridWorkerCard(
      {super.key,
      required this.worker,
      required this.onTap,
      required this.onBookNow});
  IconData _getProfessionIcon(String? p) {
    if (p == null) return Icons.construction_rounded;
    String pl = p.toLowerCase();
    if (pl.contains('plumb')) return Icons.water_drop_outlined;
    if (pl.contains('electric')) return Icons.flash_on_outlined;
    if (pl.contains('carpenter') || pl.contains('wood')) {
      return Icons.workspaces_rounded;
    }
    if (pl.contains('paint')) return Icons.format_paint_outlined;
    if (pl.contains('clean')) return Icons.cleaning_services_outlined;
    if (pl.contains('garden') || pl.contains('landscap')) {
      return Icons.grass_outlined;
    }
    if (pl.contains('handyman') || pl.contains('fix')) {
      return Icons.build_circle_outlined;
    }
    if (pl.contains('tech') || pl.contains('comput')) {
      return Icons.computer_outlined;
    }
    if (pl.contains('tutor') || pl.contains('teach')) {
      return Icons.school_outlined;
    }
    return Icons.engineering_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;
    final isDark = theme.brightness == Brightness.dark;
    double r = worker.rating ?? 0.0;
    Color rC = r >= 3.5 ? cs.secondary : cs.onSurface.withOpacity(0.6);
    Color aC = cs.secondary;
    Color sC = theme.cardColor; // ** USE THEME CARD COLOR **
    final appStrings =
        AppLocalizations.of(context)!; // ** Get localized strings **

    return ClipRRect(
      borderRadius: BorderRadius.circular(24.0),
      child: BackdropFilter(
        // Apply blur effect
        filter: ui.ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
        child: Container(
          decoration: BoxDecoration(
            color: sC.withOpacity(
                0.9), // ** USE THEME CARD COLOR (slightly transparent) **
            borderRadius: BorderRadius.circular(24.0),
            border: Border.all(
              color: cs.outline.withOpacity(0.3), // Use theme outline color
              width: 1.0,
            ),
            boxShadow: [
              // Consistent shadow
              BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.4 : 0.15),
                  blurRadius: 15,
                  spreadRadius: -5,
                  offset: const Offset(0, 6)),
            ],
          ),
          child: Material(
            // For InkWell effect
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(24.0),
              onTap: onTap,
              splashColor: aC.withOpacity(0.2),
              highlightColor: aC.withOpacity(0.1),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Pass appStrings to helper methods
                    _buildProfileHeader(context, theme, cs, tt, aC, appStrings),
                    const SizedBox(height: 8), // Reduced space
                    // Price Range Display
                    _buildPriceRange(
                        theme, cs, tt, appStrings), // New helper for price
                    const SizedBox(height: 8), // Reduced space
                    _buildProfessionAndRating(
                        context, theme, cs, tt, rC, appStrings),
                    const SizedBox(height: 16),
                    _buildStatsWrap(context, theme, cs, tt, aC, appStrings),
                    const SizedBox(height: 16),
                    _buildActionButtons(context, theme, cs, tt, aC, appStrings),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileHeader(BuildContext context, ThemeData t, ColorScheme cs,
      TextTheme tt, Color aC, AppStrings appStrings) {
    final pC = cs.surfaceContainerHighest; // Placeholder background color
    final pIC = cs.onSurfaceVariant.withOpacity(0.5); // Placeholder icon color

    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      // Profile Image with Hero Animation and Border
      Hero(
        tag: 'worker_image_grid_${worker.id}', // Unique tag for Hero
        child: Container(
          padding: const EdgeInsets.all(2.5), // Space for border
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20), // Outer radius
            border: Border.all(color: aC, width: 2.5), // Accent border
            boxShadow: [
              BoxShadow(
                  color: aC.withOpacity(0.3), blurRadius: 8, spreadRadius: 0)
            ], // Subtle shadow
          ),
          child: Container(
            // Inner container for image clipping
            height: 65, width: 65,
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(
                    17.5)), // Inner radius slightly smaller
            child: ClipRRect(
              borderRadius: BorderRadius.circular(17.5),
              child: CachedNetworkImage(
                // Efficiently load and cache network image
                imageUrl: worker.profileImage ??
                    '', // Use profile image URL or empty string
                fit: BoxFit.cover, // Cover the area
                // Placeholder while loading
                placeholder: (c, u) => Container(
                    color: pC,
                    child: Icon(Icons.person_outline_rounded,
                        size: 35, color: pIC)),
                // Error widget if image fails to load
                errorWidget: (c, u, e) => Container(
                    color: pC,
                    child: Icon(Icons.broken_image_outlined,
                        size: 35, color: pIC)),
                fadeInDuration:
                    const Duration(milliseconds: 300), // Fade-in animation
              ),
            ),
          ),
        ),
      ),
      const SizedBox(width: 12), // Spacing between image and text
      // Worker Name
      Expanded(
        child: Text(
          worker.name ??
              appStrings
                  .workerDetailAnonymous, // Use worker name or localized fallback
          style: tt.titleMedium
              ?.copyWith(fontWeight: FontWeight.w600), // Style for name
          maxLines: 2, overflow: TextOverflow.ellipsis, // Prevent overflow
        ),
      ),
    ]);
  }

  Widget _buildPriceRange(
      ThemeData t, ColorScheme cs, TextTheme tt, AppStrings appStrings) {
    // ** Use worker.priceRange and localized fallback **
    String priceText = worker.priceRange != null
        ? appStrings.jobBudgetETB(worker.priceRange.toStringAsFixed(0))
        : appStrings.notSet; // Use specific fallback

    // You might want to add "ETB" or "birr" here if needed, e.g., '$priceText ETB'
    // Ensure workerPriceRange in AppStrings includes the currency if desired, or add it here.
    // Example: String displayPrice = '${worker.priceRange ?? appStrings.workerPriceRangeNotSet} ${appStrings.currencyETB}';
    String displayPrice =
        priceText; // Assuming priceRange includes currency or unit

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color:
            cs.primaryContainer.withOpacity(0.3), // Use a theme color container
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.primary.withOpacity(0.5)), // Subtle border
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min, // Keep row compact
        children: [
          Icon(Icons.attach_money, size: 14, color: cs.primary), // Money icon
          const SizedBox(width: 4),
          Flexible(
            // Allow text to wrap or ellipsis
            child: Text(
              displayPrice,
              style: tt.bodySmall?.copyWith(
                  color: cs.onPrimaryContainer, fontWeight: FontWeight.w500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfessionAndRating(BuildContext context, ThemeData t,
      ColorScheme cs, TextTheme tt, Color rC, AppStrings appStrings) {
    double r = worker.rating ?? 0.0;
    return Row(
        mainAxisAlignment:
            MainAxisAlignment.spaceBetween, // Space out profession and rating
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Profession
          Flexible(
            // Allow profession text to shrink/ellipsis
            child: Row(
              mainAxisSize: MainAxisSize.min, // Keep row compact
              children: [
                Icon(_getProfessionIcon(worker.profession),
                    size: 18,
                    color: cs.onSurface.withOpacity(0.7)), // Profession icon
                const SizedBox(width: 6),
                Flexible(
                  // Allow text to ellipsis
                  child: Text(
                    worker.profession ??
                        appStrings
                            .generalN_A, // Use profession or localized N/A
                    style: tt.bodyMedium
                        ?.copyWith(color: cs.onSurface.withOpacity(0.8)),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10), // Spacing
          // Rating Chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
                color: rC.withOpacity(0.15), // Background based on rating color
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: rC.withOpacity(0.5),
                    width: 1) // Border based on rating color
                ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.star_rounded, color: rC, size: 16), // Star icon
                const SizedBox(width: 4),
                Text(
                  r.toStringAsFixed(1), // Display rating with one decimal place
                  style: tt.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: rC), // Style rating text
                ),
              ],
            ),
          ),
        ]);
  }

  Widget _buildStatsWrap(BuildContext context, ThemeData t, ColorScheme cs,
      TextTheme tt, Color aC, AppStrings appStrings) {
    // Use Wrap for stats items to handle different lengths and screen sizes
    return Wrap(
        spacing: 12.0, // Horizontal space between items
        runSpacing: 8.0, // Vertical space between lines
        children: [
          // Completed Jobs Stat
          _buildStatItem(
              t,
              Icons.check_circle_outline_rounded,
              appStrings.workerCardJobsDone(worker.completedJobs ?? 0),
              aC), // Use localized string with count
          // Experience Stat
          _buildStatItem(
              t,
              Icons.timer_outlined,
              appStrings.workerCardYearsExp(worker.experience ?? 0),
              cs.onSurface.withOpacity(0.7)), // Use localized string with count
          // Location Stat
          _buildStatItem(
              t,
              Icons.location_on_outlined,
              worker.location ?? appStrings.generalN_A,
              cs.onSurface.withOpacity(0.7)), // Use location or localized N/A
        ]);
  }

  Widget _buildStatItem(ThemeData t, IconData i, String txt, Color c) {
    // Helper widget for individual stat items (Icon + Text)
    return Row(
        mainAxisSize: MainAxisSize.min, // Keep row compact
        children: [
          Icon(i, size: 14, color: c.withOpacity(0.9)), // Stat icon
          const SizedBox(width: 5), // Space between icon and text
          Text(
            txt, // The stat text (already localized and formatted)
            style: t.textTheme.bodySmall?.copyWith(
                fontSize: 11.5,
                color: c.withOpacity(0.95),
                fontWeight: FontWeight.w500),
            maxLines: 1, overflow: TextOverflow.ellipsis, // Prevent overflow
          ),
        ]);
  }

  Widget _buildActionButtons(BuildContext context, ThemeData t, ColorScheme cs,
      TextTheme tt, Color aC, AppStrings appStrings) {
    // Determine button text color based on background brightness
    Color onAccentColor =
        aC.computeLuminance() > 0.5 ? Colors.black : Colors.white;

    return Row(
        mainAxisAlignment: MainAxisAlignment.end, // Align button to the right
        children: [
          // Hire/Book Now Button
          ElevatedButton.icon(
            icon: const Icon(Icons.calendar_today_outlined,
                size: 16), // Button icon
            label: Text(appStrings.workerCardHire), // Localized button label
            onPressed: onBookNow, // Action to perform on tap
            // Style the button using theme properties
            style: t.elevatedButtonTheme.style?.copyWith(
              backgroundColor: WidgetStateProperty.all(
                  aC), // Use accent color for background
              foregroundColor: WidgetStateProperty.all(
                  onAccentColor), // Use calculated text color
              textStyle: WidgetStateProperty.all(tt.labelLarge
                  ?.copyWith(fontSize: 13.5, color: onAccentColor)),
              padding: WidgetStateProperty.all(const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 10)), // Button padding
              shape: WidgetStateProperty.all(RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12))), // Button shape
              tapTargetSize: MaterialTapTargetSize
                  .shrinkWrap, // Reduce tap target size slightly
            ),
          ),
        ]);
  }
}

// --- NEW Job Grid Card (Used for Worker View Grid) ---
class NewJobGridCard extends StatelessWidget {
  final Job job;
  final VoidCallback onTap;

  const NewJobGridCard({
    super.key,
    required this.job,
    required this.onTap,
  });

  // Helper to get status color based on theme
  Color _getStatusColor(String? s, ColorScheme cs) {
    switch (s?.toLowerCase()) {
      case 'open':
        return cs.primary; // Use primary for open
      case 'assigned':
        return cs.tertiary; // Use tertiary for assigned
      case 'completed':
        return Colors.green.shade600; // Keep green for completed (universal)
      default:
        return cs.onSurface.withOpacity(0.5); // Default grey
    }
  }

  // Helper to get status icon
  IconData _getStatusIcon(String? s) {
    switch (s?.toLowerCase()) {
      case 'open':
        return Icons.lock_open_rounded;
      case 'assigned':
        return Icons.person_pin_circle_outlined;
      case 'completed':
        return Icons.check_circle_outline_rounded;
      default:
        return Icons.help_outline_rounded;
    }
  }

  // Helper to get localized status text
  String _getStatusText(String? s, AppStrings appStrings) {
    switch (s?.toLowerCase()) {
      case 'open':
        return appStrings.jobStatusOpen;
      case 'assigned':
        return appStrings.jobStatusAssigned;
      case 'completed':
        return appStrings.jobStatusCompleted;
      default:
        return s ?? appStrings.jobStatusUnknown; // Fallback
    }
  }

  // Helper to format time ago using localized strings
  String _getTimeAgo(DateTime? dt, AppStrings appStrings) {
    if (dt == null) return appStrings.jobDateN_A; // N/A if no date
    final Duration diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return appStrings.timeAgoJustNow;
    if (diff.inMinutes < 60) return appStrings.timeAgoMinute(diff.inMinutes);
    if (diff.inHours < 24) return appStrings.timeAgoHour(diff.inHours);
    if (diff.inDays < 7) return appStrings.timeAgoDay(diff.inDays);
    // Calculate weeks
    return appStrings.timeAgoWeek((diff.inDays / 7).floor());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;
    final isDark = theme.brightness == Brightness.dark;
    // ** Get localized strings **
    final appStrings = AppLocalizations.of(context)!;

    // Get status, time, budget using helpers and localization
    Color statusColor = _getStatusColor(job.status, cs);
    IconData statusIcon = _getStatusIcon(job.status);
    String statusText = _getStatusText(job.status, appStrings);
    String timeAgo = _getTimeAgo(job.createdAt, appStrings);
    String budget = job.budget != null
        ? appStrings.jobBudgetETB(
            job.budget.toStringAsFixed(0)) // Format budget with currency
        : appStrings.generalN_A; // N/A if no budget
    // ** USE THEME CARD COLOR **
    Color cardBg = theme.cardColor;

    // Check for a valid image attachment URL
    String? previewImageUrl =
        job.attachments.isNotEmpty ? job.attachments.first : null;
    bool hasImage = previewImageUrl != null &&
        Uri.tryParse(previewImageUrl)?.hasAbsolutePath == true &&
        (previewImageUrl.toLowerCase().endsWith('.jpg') ||
            previewImageUrl.toLowerCase().endsWith('.jpeg') ||
            previewImageUrl.toLowerCase().endsWith('.png') ||
            previewImageUrl.toLowerCase().endsWith('.gif'));

    return Container(
      decoration: BoxDecoration(
        color: cardBg, // ** APPLY THEME CARD COLOR **
        borderRadius: BorderRadius.circular(20.0),
        border: Border.all(
            color: cs.outlineVariant.withOpacity(0.3),
            width: 0.8), // Use theme border
        boxShadow: [
          // Consistent shadow
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.15 : 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        // For InkWell
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20.0),
        child: InkWell(
          borderRadius: BorderRadius.circular(20.0),
          onTap: onTap,
          splashColor:
              statusColor.withOpacity(0.1), // Use status color for splash
          highlightColor: statusColor.withOpacity(0.05),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- Job Title and Status Chip ---
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        job.title ??
                            appStrings.jobUntitled, // Use title or fallback
                        style: tt.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8), // Space before chip
                    // Status Chip
                    Chip(
                      avatar: Icon(statusIcon,
                          size: 14, color: statusColor), // Status icon
                      label: Text(statusText), // Localized status text
                      labelStyle: tt.labelSmall?.copyWith(
                          fontWeight: FontWeight.w600, color: statusColor),
                      backgroundColor:
                          statusColor.withOpacity(0.15), // Light background
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2), // Compact padding
                      visualDensity:
                          VisualDensity.compact, // Reduce chip height
                      side: BorderSide.none, // No border
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // --- Optional Image Preview ---
                if (hasImage)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12.0),
                    child: AspectRatio(
                      aspectRatio: 16 / 9, // Standard image aspect ratio
                      child: CachedNetworkImage(
                        imageUrl: previewImageUrl, // We know it's not null here
                        fit: BoxFit.cover,
                        // Placeholder and error widgets
                        placeholder: (c, u) =>
                            Container(color: cs.surfaceContainer),
                        errorWidget: (c, u, e) => Container(
                            color: cs.surfaceContainer,
                            child: Center(
                                child: Icon(Icons.image_not_supported_outlined,
                                    color:
                                        cs.onSurfaceVariant.withOpacity(0.5)))),
                      ),
                    ),
                  ),
                if (hasImage) const SizedBox(height: 12), // Spacing after image

                // --- Description ---
                Text(
                  job.description ??
                      appStrings
                          .jobNoDescription, // Use description or fallback
                  style: tt.bodyMedium
                      ?.copyWith(color: cs.onSurfaceVariant), // Subdued color
                  maxLines: hasImage ? 2 : 4, // Allow more lines if no image
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),

                // --- Meta Info (Budget, Location, Time) ---
                Row(
                  // Budget and Location row
                  children: [
                    _buildMetaItem(
                        context, Icons.attach_money, budget), // Budget
                    const SizedBox(width: 12),
                    Expanded(
                        child: _buildMetaItem(
                            context,
                            Icons.location_on_outlined,
                            job.location ?? appStrings.generalN_A)), // Location
                  ],
                ),
                const SizedBox(height: 4),
                _buildMetaItem(
                    context, Icons.access_time, timeAgo), // Time posted

                const Spacer(), // Push button to bottom if space allows

                // --- View Details Button ---
                Align(
                  alignment: Alignment.bottomRight,
                  child: TextButton(
                    // Less prominent than the Hire button
                    onPressed: onTap,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: Text(appStrings.jobCardView), // Localized text
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Helper for individual meta items (Icon + Text)
  Widget _buildMetaItem(BuildContext context, IconData icon, String text) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min, // Keep row compact
      children: [
        Icon(icon,
            size: 14,
            color: theme.colorScheme.onSurfaceVariant.withOpacity(0.8)),
        const SizedBox(width: 5), // Space
        Flexible(
          // Allow text to wrap/ellipsis if needed
          child: Text(
            text,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// --- FeaturedWorkerCard (Used for Client View Carousel) ---
// (Keep this card as it's used for the client view)
class FeaturedWorkerCard extends StatelessWidget {
  final Worker worker;
  final VoidCallback onTap;
  const FeaturedWorkerCard(
      {super.key, required this.worker, required this.onTap});

  // Icon helper remains the same
  IconData _getProfessionIcon(String? p) {
    if (p == null) return Icons.construction_rounded;
    String pl = p.toLowerCase();
    if (pl.contains('plumb')) return Icons.water_drop_outlined;
    if (pl.contains('electric')) return Icons.flash_on_outlined;
    if (pl.contains('carpenter') || pl.contains('wood')) {
      return Icons.workspaces_rounded;
    }
    if (pl.contains('paint')) return Icons.format_paint_outlined;
    if (pl.contains('clean')) return Icons.cleaning_services_outlined;
    if (pl.contains('garden') || pl.contains('landscap')) {
      return Icons.grass_outlined;
    }
    if (pl.contains('handyman') || pl.contains('fix')) {
      return Icons.build_circle_outlined;
    }
    if (pl.contains('tech') || pl.contains('comput')) {
      return Icons.computer_outlined;
    }
    if (pl.contains('tutor') || pl.contains('teach')) {
      return Icons.school_outlined;
    }
    return Icons.engineering_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;
    final isDark = theme.brightness == Brightness.dark;
    double r = worker.rating ?? 0.0;
    // Determine rating chip colors based on theme and rating value
    Color ratingColor = r >= 4.0
        ? cs.secondary
        : (r >= 3.0
            ? (cs.tertiaryContainer ?? cs.primaryContainer)
            : cs.errorContainer ?? cs.error);
    Color onRatingColor = r >= 4.0
        ? cs.onSecondary
        : (r >= 3.0
            ? (cs.onTertiaryContainer ?? cs.onPrimaryContainer)
            : cs.onErrorContainer ?? cs.onError);
    // ** Get localized strings **
    final appStrings = AppLocalizations.of(context)!;
    // ** USE THEME CARD COLOR **
    Color cardBg = theme.cardColor;

    return Container(
      width: MediaQuery.of(context).size.width * 0.6, // Card width
      decoration: BoxDecoration(
        // Use gradient based on theme card color
        gradient: LinearGradient(
            colors: [
              cardBg,
              cardBg.withOpacity(isDark ? 0.85 : 0.95)
            ], // Subtle gradient
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(
            color: cs.outline.withOpacity(0.2), width: 0.8), // Theme border
        boxShadow: [
          // Subtle shadow
          BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
              blurRadius: 10,
              spreadRadius: -4,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Material(
        // For InkWell
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16.0),
          onTap: onTap,
          splashColor: cs.primary.withOpacity(0.15), // Theme splash
          highlightColor: cs.primary.withOpacity(0.08), // Theme highlight
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment
                  .spaceBetween, // Space out elements vertically
              children: [
                // --- Top Section: Image, Name, Rating ---
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Profile Image with Hero Animation
                  Hero(
                    tag: 'worker_image_featured_${worker.id}', // Unique tag
                    child: Container(
                      height: 50,
                      width: 50,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: cs.secondary.withOpacity(0.5),
                            width: 1.5), // Secondary color border
                        boxShadow: [
                          BoxShadow(
                              color: cs.secondary.withOpacity(0.2),
                              blurRadius: 6)
                        ], // Shadow
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                            11), // Inner radius for clipping
                        child: CachedNetworkImage(
                          imageUrl: worker.profileImage ?? '',
                          fit: BoxFit.cover,
                          // Placeholder and error widgets
                          placeholder: (c, u) => Container(
                              color: cs.surfaceContainerHighest,
                              child: Icon(Icons.person_outline_rounded,
                                  size: 25,
                                  color: cs.onSurfaceVariant.withOpacity(0.5))),
                          errorWidget: (c, u, e) => Container(
                              color: cs.surfaceContainerHighest,
                              child: Icon(Icons.broken_image_outlined,
                                  size: 25,
                                  color: cs.onSurfaceVariant.withOpacity(0.5))),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10), // Spacing
                  // Name and Rating Column
                  Expanded(
                      child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        worker.name ??
                            appStrings
                                .workerDetailAnonymous, // Name or fallback
                        style: tt.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      // Price Range (using helper from grid card)
                      _buildFeaturedPriceRange(theme, cs, tt, appStrings,
                          worker), // Pass worker here
                      const SizedBox(height: 4),
                      // Rating Chip
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: ratingColor
                              .withOpacity(0.8), // Use calculated rating color
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.star_rate_rounded,
                                color: onRatingColor, size: 13), // Star icon
                            const SizedBox(width: 3),
                            Text(r.toStringAsFixed(1), // Rating value
                                style: tt.labelSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color:
                                        onRatingColor)), // Style with calculated color
                          ],
                        ),
                      ),
                    ],
                  )),
                ]),
                // --- Bottom Section: Profession ---
                Row(
                  // Profession row
                  children: [
                    Icon(_getProfessionIcon(worker.profession),
                        size: 15, color: cs.secondary), // Profession icon
                    const SizedBox(width: 5), // Space
                    Expanded(
                      // Allow text to ellipsis
                      child: Text(
                        worker.profession ??
                            appStrings.generalN_A, // Profession or N/A
                        style: tt.bodySmall
                            ?.copyWith(color: cs.onSurface.withOpacity(0.7)),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Helper specifically for featured card price range (might have slightly different styling if needed)
  Widget _buildFeaturedPriceRange(ThemeData t, ColorScheme cs, TextTheme tt,
      AppStrings appStrings, Worker worker) {
    String priceText = worker.priceRange != null
        ? appStrings.jobBudgetETB(worker.priceRange.toStringAsFixed(0))
        : appStrings.notSet;
    String displayPrice =
        priceText; // Assuming priceRange includes currency or unit

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 6, vertical: 3), // Slightly different padding maybe
      decoration: BoxDecoration(
        color: cs.primaryContainer.withOpacity(0.2), // Consistent background
        borderRadius: BorderRadius.circular(6),
        // border: Border.all(color: cs.primary.withOpacity(0.4)), // Optional border
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.attach_money, size: 13, color: cs.primary),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              displayPrice,
              style: tt.labelSmall?.copyWith(
                  color: cs.onPrimaryContainer,
                  fontWeight: FontWeight.w500), // Use labelSmall
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// --- NEW Featured Job Card (Used for Worker View Carousel) ---
class NewFeaturedJobCard extends StatelessWidget {
  final Job job;
  final VoidCallback onTap;

  const NewFeaturedJobCard({super.key, required this.job, required this.onTap});

  // Reusing helpers from Job Grid Card
  Color _getStatusColor(String? s, ColorScheme cs) {
    switch (s?.toLowerCase()) {
      case 'open':
        return cs.primary;
      case 'assigned':
        return cs.tertiary;
      case 'completed':
        return Colors.green.shade600;
      default:
        return cs.onSurface.withOpacity(0.5);
    }
  }

  String _getTimeAgo(DateTime? dt, AppStrings appStrings) {
    if (dt == null) return appStrings.jobDateN_A;
    final Duration diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return appStrings.timeAgoJustNow;
    if (diff.inMinutes < 60) return appStrings.timeAgoMinute(diff.inMinutes);
    if (diff.inHours < 24) return appStrings.timeAgoHour(diff.inHours);
    if (diff.inDays < 7) return appStrings.timeAgoDay(diff.inDays);
    return appStrings.timeAgoWeek((diff.inDays / 7).floor());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;
    final isDark = theme.brightness == Brightness.dark;
    // ** Get localized strings **
    final appStrings = AppLocalizations.of(context)!;

    // Get status, time, budget using helpers and localization
    Color statusColor = _getStatusColor(job.status, cs);
    String timeAgo = _getTimeAgo(job.createdAt, appStrings);
    String budget = job.budget != null
        ? appStrings.jobBudgetETB(job.budget.toStringAsFixed(0))
        : appStrings.generalN_A;
    // ** USE THEME CARD COLOR **
    Color cardBg = theme.cardColor;

    // Check for a valid image attachment URL
    String? previewImageUrl =
        job.attachments.isNotEmpty ? job.attachments.first : null;
    bool hasImage = previewImageUrl != null &&
        Uri.tryParse(previewImageUrl)?.hasAbsolutePath == true &&
        (previewImageUrl.toLowerCase().endsWith('.jpg') ||
            previewImageUrl.toLowerCase().endsWith('.jpeg') ||
            previewImageUrl.toLowerCase().endsWith('.png') ||
            previewImageUrl.toLowerCase().endsWith('.gif'));

    return Container(
      width: MediaQuery.of(context).size.width * 0.65, // Card width
      decoration: BoxDecoration(
        color: cardBg, // ** APPLY THEME CARD COLOR **
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(
            color: cs.outlineVariant.withOpacity(0.3),
            width: 0.8), // Theme border
        boxShadow: [
          // Subtle shadow
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        // For InkWell
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16.0),
        child: InkWell(
          borderRadius: BorderRadius.circular(16.0),
          onTap: onTap,
          splashColor:
              statusColor.withOpacity(0.1), // Use status color for splash
          highlightColor: statusColor.withOpacity(0.05),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              // Arrange content vertically
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- Top Section: Title and Optional Image ---
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      // Title takes available space
                      child: Text(
                        job.title ??
                            appStrings.jobUntitled, // Title or fallback
                        style: tt.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Small Image Preview if available
                    if (hasImage) ...[
                      const SizedBox(width: 10), // Space before image
                      ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CachedNetworkImage(
                            imageUrl: previewImageUrl,
                            height: 40, width: 40,
                            fit: BoxFit.cover, // Small preview size
                            placeholder: (c, u) => Container(
                                height: 40,
                                width: 40,
                                color: cs.surfaceContainerHigh), // Placeholder
                            errorWidget: (c, u, e) => Container(
                                height: 40,
                                width: 40,
                                color: cs.surfaceContainerHigh,
                                child: Icon(Icons.image_not_supported_outlined,
                                    size: 18,
                                    color: cs.onSurfaceVariant
                                        .withOpacity(0.5))), // Error icon
                          ))
                    ]
                  ],
                ),
                const SizedBox(height: 6),
                // --- Description ---
                Text(
                  job.description ??
                      appStrings.jobNoDescription, // Description or fallback
                  style: tt.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant
                          .withOpacity(0.9)), // Slightly darker description
                  maxLines: 2, overflow: TextOverflow.ellipsis, // Limit lines
                ),
                const Spacer(), // Push meta info to bottom

                // --- Meta Info (Bottom) ---
                Row(
                  // Budget and Location row
                  mainAxisAlignment:
                      MainAxisAlignment.spaceBetween, // Space out items
                  children: [
                    // Use flexible meta item helper
                    _buildMetaItemFeatured(
                        context, Icons.attach_money, budget), // Budget
                    Flexible(
                        child: _buildMetaItemFeatured(
                            context,
                            Icons.location_on_outlined,
                            job.location ?? appStrings.generalN_A)), // Location
                  ],
                ),
                const SizedBox(height: 4),
                _buildMetaItemFeatured(
                    context, Icons.access_time, timeAgo), // Time Ago
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Helper specific to featured card meta items (Icon + Text)
  Widget _buildMetaItemFeatured(
      BuildContext context, IconData icon, String text) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min, // Keep row compact
      children: [
        Icon(icon,
            size: 13,
            color: theme.colorScheme.onSurfaceVariant.withOpacity(0.8)), // Icon
        const SizedBox(width: 4), // Space
        Flexible(
          // Allow text to wrap/ellipsis
          child: Text(
            text,
            style: theme.textTheme.labelSmall?.copyWith(
                color:
                    theme.colorScheme.onSurfaceVariant), // Use labelSmall style
            maxLines: 1, overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
