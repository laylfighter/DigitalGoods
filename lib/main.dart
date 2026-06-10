// lib/main.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_fonts/google_fonts.dart';
import 'screens/auth_screens.dart';
import 'screens/user_screens.dart';
import 'screens/supplier_screens.dart';
import 'screens/admin_screen.dart';
import 'screens/transfer_screen.dart';
import 'services/push_notification_service.dart';
import 'blockchain/wallet_service.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'theme.dart';

const _gradientTop = Color(0xFF0D7A7A); // ← LOGO SHADE  (tell your designer)
const _gradientMid = Color(0xFF0B5E6B);
const _gradientBottom = Color(0xFF0A4A57);

const kSplashGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [_gradientTop, _gradientMid, _gradientBottom],
  stops: [0.0, 0.55, 1.0],
);

// ─────────────────────────────────────────────────────────────────────────────
// DESIGN 2 — TEAL PALETTE (single source of truth for the whole app)
// ─────────────────────────────────────────────────────────────────────────────
class AppColors {
  static const primary = AppTheme.primaryStart; // Primary Teal
  static const primaryDark =
      AppTheme.primaryStartDark; // Dark Teal  (AppBar, headers)
  static const primaryLight = AppTheme.primaryLight; // Teal Light (backgrounds)
  static const background = AppTheme.background; // App scaffold BG
  static const surface = Colors.white; // Card / sheet BG
  static const textPrimary = AppTheme.textPrimary; // Dark navy text
  static const textSecondary = AppTheme.textSecondary; // Muted grey text
  static const border = AppTheme.primaryStart; // Subtle border
  static const error = AppTheme.error; // Red
}

// ─────────────────────────────────────────────────────────────────────────────
// CUSTOM PAGE-TRANSITION BUILDER
// ─────────────────────────────────────────────────────────────────────────────
class _AppPageTransition extends PageTransitionsBuilder {
  const _AppPageTransition();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // Outgoing screen slides left a little and fades slightly
    final slideOut =
        Tween<Offset>(begin: Offset.zero, end: const Offset(-0.15, 0)).animate(
          CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeInOut),
        );

    // Incoming screen slides from the right
    final slideIn = Tween<Offset>(
      begin: const Offset(1.0, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));

    // Incoming screen fades in during the first 65% of the animation
    final fadeIn = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: animation,
        curve: const Interval(0.0, 0.65, curve: Curves.easeOut),
      ),
    );

    return SlideTransition(
      position: slideOut,
      child: FadeTransition(
        opacity: fadeIn,
        child: SlideTransition(position: slideIn, child: child),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// REUSABLE ROUTE HELPERS  (use these instead of MaterialPageRoute everywhere)
// ─────────────────────────────────────────────────────────────────────────────

/// Standard forward navigation — slide + fade
class SlidePageRoute<T> extends PageRouteBuilder<T> {
  SlidePageRoute({required Widget page})
    : super(
        pageBuilder: (_, __, ___) => page,
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 260),
        transitionsBuilder: (_, anim, secAnim, child) {
          final out = Tween<Offset>(
            begin: Offset.zero,
            end: const Offset(-0.15, 0),
          ).animate(CurvedAnimation(parent: secAnim, curve: Curves.easeInOut));
          final inSlide = Tween<Offset>(
            begin: const Offset(1.0, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic));
          final fade = Tween<double>(begin: 0.0, end: 1.0).animate(
            CurvedAnimation(
              parent: anim,
              curve: const Interval(0.0, 0.65, curve: Curves.easeOut),
            ),
          );
          return SlideTransition(
            position: out,
            child: FadeTransition(
              opacity: fade,
              child: SlideTransition(position: inSlide, child: child),
            ),
          );
        },
      );
}

/// Modal feel — fade + scale up from 95%
class FadeScalePageRoute<T> extends PageRouteBuilder<T> {
  FadeScalePageRoute({required Widget page})
    : super(
        pageBuilder: (_, __, ___) => page,
        transitionDuration: const Duration(milliseconds: 280),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        transitionsBuilder: (_, anim, __, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.95, end: 1.0).animate(
                CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
              ),
              child: child,
            ),
          );
        },
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// GLOBAL NAVIGATOR KEY
// ─────────────────────────────────────────────────────────────────────────────
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// ─────────────────────────────────────────────────────────────────────────────
// BACKGROUND MESSAGE HANDLER
// ─────────────────────────────────────────────────────────────────────────────
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('Background message: ${message.messageId}');
}

// ─────────────────────────────────────────────────────────────────────────────
// ENTRY POINT
// ─────────────────────────────────────────────────────────────────────────────
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseAnalytics.instance;
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  await PushNotificationService().initialize();

  // Status bar: transparent — icons dark to match light transparent AppBar
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: AppColors.surface,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(const DigitalGoodsApp());
}

// ─────────────────────────────────────────────────────────────────────────────
// ROOT APP WIDGET
// ─────────────────────────────────────────────────────────────────────────────
class DigitalGoodsApp extends StatefulWidget {
  const DigitalGoodsApp({super.key});

  @override
  State<DigitalGoodsApp> createState() => _DigitalGoodsAppState();
}

class _DigitalGoodsAppState extends State<DigitalGoodsApp> {
  bool _darkMode = false;
  bool _loading = true;
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _themeSubscription;
  bool _notificationHandlersReady = false;
  String? _activeAuthUid;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    _activeAuthUid = currentUser?.uid;
    await _syncThemeForUser(currentUser);
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      final nextUid = user?.uid;
      final uidChanged = nextUid != _activeAuthUid;
      if (uidChanged) {
        _activeAuthUid = nextUid;
        unawaited(SimpleWalletService().resetSession());
      }
      if (!uidChanged &&
          user?.uid == FirebaseAuth.instance.currentUser?.uid &&
          _themeSubscription != null) {
        return;
      }
      unawaited(_syncThemeForUser(user));
    });
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _syncThemeForUser(User? user) async {
    await _themeSubscription?.cancel();
    _themeSubscription = null;

    if (user == null) {
      if (mounted && _darkMode) {
        setState(() => _darkMode = false);
      }
      _applySystemUi(false);
      return;
    }

    if (!_notificationHandlersReady) {
      _setupNotificationHandlers();
      _notificationHandlersReady = true;
    }

    final userRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid);
    try {
      final doc = await userRef.get();
      final nextDarkMode = doc.data()?['darkMode'] == true;
      if (mounted && _darkMode != nextDarkMode) {
        setState(() => _darkMode = nextDarkMode);
      }
      _applySystemUi(nextDarkMode);
      _themeSubscription = userRef.snapshots().listen((snapshot) {
        final liveDarkMode = snapshot.data()?['darkMode'] == true;
        if (!mounted) return;
        if (_darkMode != liveDarkMode) {
          setState(() => _darkMode = liveDarkMode);
        }
        _applySystemUi(liveDarkMode);
      });
    } catch (e) {
      debugPrint('Error loading theme: $e');
      _applySystemUi(_darkMode);
    }
  }

  void _applySystemUi(bool isDark) {
    final navColor = isDark ? AppTheme.darkSurface : AppColors.surface;
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: navColor,
        systemNavigationBarDividerColor: navColor,
        systemNavigationBarIconBrightness: isDark
            ? Brightness.light
            : Brightness.dark,
      ),
    );
  }

  // ── Notification wiring ────────────────────────────────────────────────────
  void _setupNotificationHandlers() {
    // Foreground notifications are shown as local notifications by PushNotificationService.
    // Here we only handle navigation when user taps a notification.
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationNavigation);
    FirebaseMessaging.instance.getInitialMessage().then((m) {
      if (m != null) {
        Future.delayed(
          const Duration(seconds: 2),
          () => _handleNotificationNavigation(m),
        );
      }
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _themeSubscription?.cancel();
    super.dispose();
  }

  void _handleNotificationNavigation(RemoteMessage message) {
    final data = message.data;
    if (data.isEmpty) return;
    final type = data['type'];
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;

    switch (type) {
      case 'checkout_request':
        final txId = data['transactionId'];
        if (txId != null) _navigateToTransferScreen(ctx, txId);
        break;
      case 'checkout_accepted':
      case 'checkout_rejected':
        showDialog(
          context: ctx,
          builder: (_) => AlertDialog(
            title: Text(
              type == 'checkout_accepted'
                  ? 'Checkout Accepted'
                  : 'Checkout Rejected',
            ),
            content: Text(message.notification?.body ?? ''),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        break;
      case 'transfer_complete':
      case 'product_sold':
        showDialog(
          context: ctx,
          builder: (_) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: AppColors.primary),
                SizedBox(width: 8),
                Text('Success'),
              ],
            ),
            content: Text(message.notification?.body ?? ''),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        break;
    }
  }

  Future<void> _navigateToTransferScreen(
    BuildContext context,
    String transactionId,
  ) async {
    try {
      final txDoc = await FirebaseFirestore.instance
          .collection('transactions')
          .doc(transactionId)
          .get();
      if (!txDoc.exists) throw Exception('Transaction not found');
      final txData = txDoc.data()!;
      final assetType = txData['assetType'] == 'electronics'
          ? AssetType.electronics
          : AssetType.land;

      final assetDoc = await FirebaseFirestore.instance
          .collection('assets')
          .doc(txData['assetId'])
          .get();
      final assetPrice = assetDoc.data()?['price']?.toString() ?? '0';

      final buyerDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(txData['buyerUid'])
          .get();
      final buyerName = buyerDoc.data()?['name'] ?? 'Buyer';

      if (context.mounted) {
        Navigator.push(
          context,
          SlidePageRoute(
            page: TransferScreen(
              assetType: assetType,
              assetId: txData['assetId'],
              transactionId: transactionId,
              buyerUid: txData['buyerUid'],
              sellerUid: txData['sellerUid'],
              tokenId: txData['blockchainTokenId'],
              propertyId: txData['blockchainTokenId'],
              fractionAmount: txData['fractionAmount'],
              assetPrice: assetPrice,
              buyerName: buyerName,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error navigating to transfer screen: $e');
    }
  }

  // ── Theme builder ──────────────────────────────────────────────────────────
  ThemeData _buildTheme(bool isDark) {
    final base = isDark ? ThemeData.dark() : ThemeData.light();

    // Poppins — clean, geometric, professional sans-serif
    final textTheme = GoogleFonts.poppinsTextTheme(base.textTheme).copyWith(
      displayLarge: GoogleFonts.poppins(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      displayMedium: GoogleFonts.poppins(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      displaySmall: GoogleFonts.poppins(
        fontSize: 24,
        fontWeight: FontWeight.w600,
      ),
      headlineLarge: GoogleFonts.poppins(
        fontSize: 22,
        fontWeight: FontWeight.w600,
      ),
      headlineMedium: GoogleFonts.poppins(
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      headlineSmall: GoogleFonts.poppins(
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: GoogleFonts.poppins(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      ),
      titleMedium: GoogleFonts.poppins(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.1,
      ),
      titleSmall: GoogleFonts.poppins(
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      bodyLarge: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w400),
      bodyMedium: GoogleFonts.poppins(
        fontSize: 14,
        fontWeight: FontWeight.w400,
      ),
      bodySmall: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w400),
      labelLarge: GoogleFonts.poppins(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
      ),
      labelMedium: GoogleFonts.poppins(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.3,
      ),
      labelSmall: GoogleFonts.poppins(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.4,
      ),
    );

    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: isDark ? Brightness.dark : Brightness.light,
      primary: AppColors.primary,
      onPrimary: Colors.white,
      primaryContainer: AppColors.primaryLight,
      secondary: AppColors.primaryDark,
      onSecondary: Colors.white,
      surface: isDark ? AppTheme.darkSurfaceAlt : AppColors.surface,
      onSurface: isDark ? AppTheme.darkTextPrimary : AppColors.textPrimary,
      error: AppColors.error,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      colorScheme: colorScheme,
      textTheme: textTheme,
      fontFamily: GoogleFonts.poppins().fontFamily,
      scaffoldBackgroundColor: isDark
          ? AppTheme.darkBackground
          : AppColors.background,

      // ── AppBar ──────────────────────────────────────────────────────────
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        shadowColor: Colors.transparent,
        titleTextStyle: GoogleFonts.poppins(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: isDark ? AppTheme.darkTextPrimary : Colors.black87,
          letterSpacing: 0.2,
        ),
        iconTheme: IconThemeData(
          color: isDark ? AppTheme.darkTextPrimary : Colors.black87,
          size: 24,
        ),
        actionsIconTheme: IconThemeData(
          color: isDark ? AppTheme.darkTextSecondary : Colors.black54,
          size: 22,
        ),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        ),
      ),

      // ── Elevated Button ────────────────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.primary.withOpacity(0.4),
          disabledForegroundColor: Colors.white54,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          minimumSize: const Size(double.infinity, 50),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
          animationDuration: const Duration(milliseconds: 200),
        ),
      ),

      // ── Outlined Button ────────────────────────────────────────────────
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
          animationDuration: const Duration(milliseconds: 200),
        ),
      ),

      // ── Text Button ────────────────────────────────────────────────────
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          textStyle: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          animationDuration: const Duration(milliseconds: 200),
        ),
      ),

      // ── FAB ────────────────────────────────────────────────────────────
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),

      // ── Card ───────────────────────────────────────────────────────────
      cardTheme: CardThemeData(
        color: isDark ? AppTheme.darkSurfaceAlt : AppColors.surface,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: isDark ? AppTheme.darkBorder : AppColors.border,
          ),
        ),
        margin: const EdgeInsets.symmetric(vertical: 4),
        clipBehavior: Clip.antiAlias,
      ),

      // ── Input Decoration ───────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? AppTheme.darkSurfaceSoft : AppColors.background,
        hintStyle: GoogleFonts.poppins(
          fontSize: 14,
          color: isDark ? AppTheme.darkTextSecondary : AppColors.textSecondary,
        ),
        labelStyle: GoogleFonts.poppins(
          fontSize: 14,
          color: isDark ? AppTheme.darkTextSecondary : AppColors.textSecondary,
        ),
        floatingLabelStyle: GoogleFonts.poppins(
          fontSize: 13,
          color: AppColors.primary,
          fontWeight: FontWeight.w500,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? AppTheme.darkBorder : AppColors.border,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error, width: 2),
        ),
        prefixIconColor: isDark
            ? AppTheme.darkTextSecondary
            : AppColors.textSecondary,
        suffixIconColor: isDark
            ? AppTheme.darkTextSecondary
            : AppColors.textSecondary,
      ),

      // ── Bottom Navigation Bar ──────────────────────────────────────────
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: isDark ? AppTheme.darkSurfaceAlt : AppColors.surface,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: isDark
            ? AppTheme.darkTextSecondary
            : AppColors.textSecondary,
        selectedLabelStyle: GoogleFonts.poppins(
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: GoogleFonts.poppins(
          fontSize: 11,
          fontWeight: FontWeight.w400,
        ),
        elevation: 8,
        type: BottomNavigationBarType.fixed,
        showSelectedLabels: true,
        showUnselectedLabels: true,
      ),

      // ── Tab Bar ────────────────────────────────────────────────────────
      tabBarTheme: TabBarThemeData(
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white60,
        indicatorColor: Colors.white,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelStyle: GoogleFonts.poppins(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: GoogleFonts.poppins(
          fontSize: 13,
          fontWeight: FontWeight.w400,
        ),
      ),

      // ── Chip ───────────────────────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor: isDark
            ? AppColors.primary.withOpacity(0.16)
            : AppColors.primaryLight,
        selectedColor: AppColors.primary,
        labelStyle: GoogleFonts.poppins(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: isDark ? AppTheme.darkTextPrimary : AppColors.primaryDark,
        ),
        secondaryLabelStyle: GoogleFonts.poppins(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: Colors.white,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide.none,
        ),
        elevation: 0,
        pressElevation: 0,
      ),

      // ── Dialog ─────────────────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? AppTheme.darkSurfaceAlt : AppColors.surface,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: GoogleFonts.poppins(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: isDark ? AppTheme.darkTextPrimary : AppColors.textPrimary,
        ),
        contentTextStyle: GoogleFonts.poppins(
          fontSize: 14,
          color: isDark ? AppTheme.darkTextSecondary : AppColors.textSecondary,
        ),
      ),

      // ── Snack Bar ──────────────────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppTheme.primaryStartDark,
        contentTextStyle: GoogleFonts.poppins(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: Colors.white,
        ),
        actionTextColor: AppColors.primaryLight,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 4,
      ),

      // ── List Tile ──────────────────────────────────────────────────────
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        titleTextStyle: GoogleFonts.poppins(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: isDark ? AppTheme.darkTextPrimary : AppColors.textPrimary,
        ),
        subtitleTextStyle: GoogleFonts.poppins(
          fontSize: 12,
          color: isDark ? AppTheme.darkTextSecondary : AppColors.textSecondary,
        ),
        iconColor: AppColors.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),

      // ── Divider ────────────────────────────────────────────────────────
      dividerTheme: DividerThemeData(
        color: isDark ? AppTheme.darkBorder : AppColors.border,
        thickness: 1,
        space: 1,
      ),

      // ── Switch ─────────────────────────────────────────────────────────
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.primary
              : Colors.grey[400],
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.primaryLight
              : (isDark ? Colors.white24 : Colors.grey[300]),
        ),
      ),

      // ── Checkbox ───────────────────────────────────────────────────────
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.primary
              : Colors.transparent,
        ),
        checkColor: WidgetStateProperty.all(Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        side: const BorderSide(color: AppColors.primary, width: 1.5),
      ),

      // ── Radio ──────────────────────────────────────────────────────────
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.textSecondary,
        ),
      ),

      // ── Progress Indicator ─────────────────────────────────────────────
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppTheme.primaryStart,
        linearTrackColor: AppColors.primaryLight,
        circularTrackColor: AppColors.primaryLight,
      ),

      // ── Bottom Sheet ───────────────────────────────────────────────────
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? AppTheme.darkSurfaceAlt : AppColors.surface,
        modalBackgroundColor: isDark
            ? AppTheme.darkSurfaceAlt
            : AppColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        showDragHandle: true,
        dragHandleColor: isDark ? AppTheme.darkBorder : AppColors.border,
        elevation: 8,
      ),

      // ── Popup Menu ─────────────────────────────────────────────────────
      popupMenuTheme: PopupMenuThemeData(
        color: isDark ? AppTheme.darkSurfaceAlt : AppColors.surface,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: GoogleFonts.poppins(
          fontSize: 13,
          color: isDark ? AppTheme.darkTextPrimary : AppColors.textPrimary,
        ),
      ),

      // ── Badge ──────────────────────────────────────────────────────────
      badgeTheme: const BadgeThemeData(
        backgroundColor: AppTheme.primaryStart,
        textColor: Colors.white,
        textStyle: TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
      ),

      // ── Page Transitions — applies to ALL Navigator.push calls ─────────
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _AppPageTransition(),
          TargetPlatform.iOS: _AppPageTransition(),
          TargetPlatform.fuchsia: _AppPageTransition(),
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: _darkMode
              ? AppTheme.darkBackground
              : AppColors.background,
          body: const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
        ),
      );
    }

    return MaterialApp(
      title: 'Digital Goods',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(false),
      darkTheme: _buildTheme(true),
      themeMode: _darkMode ? ThemeMode.dark : ThemeMode.light,
      navigatorKey: navigatorKey,
      home: const AppEntry(),
      // ── Global back-button override ──────────────────────────────────────
      // Flutter's default back button uses arrow_back on Android. By setting
      // platform to iOS the framework automatically uses arrow_back_ios
      // (a chevron-style icon) for all AppBar back buttons app-wide — without
      // changing any other platform behaviour because we override it only here.
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(platform: TargetPlatform.iOS),
          child: child!,
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// APP ENTRY — checks onboarding flag
// ─────────────────────────────────────────────────────────────────────────────
class AppEntry extends StatefulWidget {
  const AppEntry({super.key});

  @override
  State<AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends State<AppEntry> {
  bool _loading = true;
  bool _seenOnboarding = false;

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
  }

  Future<void> _checkOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    _seenOnboarding = prefs.getBool('onboarding') ?? false;
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }
    return _seenOnboarding ? const SplashScreen() : const OnboardingScreen();
  }
}

// NOTE: OnboardingScreen and SplashScreen are defined in auth_screens.dart.
// They were removed from here to avoid shadowing the imported versions.

// ─────────────────────────────────────────────────────────────────────────────
// ROLE-BASED ROUTER
// ─────────────────────────────────────────────────────────────────────────────
class RoleBasedRouter extends StatelessWidget {
  const RoleBasedRouter({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const LoginScreen();

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          );
        }
        if (!snapshot.hasData || !snapshot.data!.exists)
          return const LoginScreen();

        final userData = snapshot.data!.data() as Map<String, dynamic>;
        final role = userData['role'] as String? ?? 'user';

        if (role == 'admin') {
          return const AdminHomeScreen();
        } else if (role.contains('supplier')) {
          final type = role.contains('land') ? 'land' : 'electronics';
          return SupplierHomeScreen(type: type);
        } else {
          return const UserHomeScreen();
        }
      },
    );
  }
}
