// lib/screens/auth_screens.dart
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:introduction_screen/introduction_screen.dart';
import 'package:image/image.dart' as img;

import 'user_screens.dart';
import 'supplier_screens.dart';
import 'admin_screen.dart';
import 'terms_screen.dart';
import '../theme.dart';

// ─── Brand Colors ─────────────────────────────────────────────────────────────
// Migration to AppTheme: The constants below are now derived from AppTheme
const kTeal = AppTheme.primaryStart;
const kTealDark = AppTheme.primaryStartDark;
const kTealLight = Color(0xFFE8F4F4); // Kept for light background variations
const kTealAccent = AppTheme.accent;
const kScaffoldBg = AppTheme.background;
const kTextPrimary = AppTheme.textPrimary;
const kTextSecondary = AppTheme.textSecondary;

final FirebaseAuth auth = FirebaseAuth.instance;
final FirebaseFirestore db = FirebaseFirestore.instance;

// ─── Shared Input Decoration ──────────────────────────────────────────────────
InputDecoration _inputDecoration(
  BuildContext context,
  String label, {
  Widget? prefix,
  Widget? suffix,
}) {
  return InputDecoration(
    labelText: label,
    labelStyle: AppTheme.body(14, color: context.appTextSecondary),
    prefixIcon: prefix,
    suffixIcon: suffix,
    filled: true,
    fillColor: context.appInputFill,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: context.appBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: kTeal, width: 2),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
  );
}

// ─── Image Compression ───────────────────────────────────────────────────────
Future<String> compressImageToBase64(
  Uint8List bytes, {
  int quality = 70,
}) async {
  final image = img.decodeImage(bytes);
  if (image == null) return base64Encode(bytes);
  img.Image resized = image;
  if (image.width > 800) resized = img.copyResize(image, width: 800);
  final compressed = img.encodeJpg(resized, quality: quality);
  final base64Str = base64Encode(compressed);
  if (base64Str.length > 900000) {
    return compressImageToBase64(bytes, quality: quality - 10);
  }
  return base64Str;
}

// ─── Onboarding Screen ────────────────────────────────────────────────────────
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  Future<void> _complete(BuildContext ctx) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding', true);
    if (!ctx.mounted) return;
    Navigator.pushReplacement(
      ctx,
      MaterialPageRoute(builder: (_) => const SplashScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _buildPage(
        context: context,
        icon: Icons.security_rounded,
        title: 'Secure Ownership',
        body: 'Digital verification for land & electronic assets.',
      ),
      _buildPage(
        context: context,
        icon: Icons.qr_code_scanner_rounded,
        title: 'QR Verification',
        body: 'Instant verification using QR codes.',
      ),
      _buildPage(
        context: context,
        icon: Icons.token_rounded,
        title: 'Future Tokenization',
        body: 'Invest in tokenized assets in Phase 2.',
      ),
    ];

    return IntroductionScreen(
      globalBackgroundColor: context.appScaffold,
      pages: pages,
      done: Text(
        'Get Started',
        style: AppTheme.heading(14, color: AppTheme.primaryStart),
      ),
      onDone: () => _complete(context),
      next: const Icon(Icons.arrow_forward_ios_rounded, color: kTeal, size: 18),
      showSkipButton: true,
      skip: Text(
        'Skip',
        style: AppTheme.body(14, color: AppTheme.textSecondary),
      ),
      dotsDecorator: const DotsDecorator(
        activeColor: AppTheme.primaryStart,
        color: Color(0xFFB2CFCF),
        size: Size(8, 8),
        activeSize: Size(20, 8),
        activeShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(4)),
        ),
      ),
    );
  }

  PageViewModel _buildPage({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String body,
  }) {
    return PageViewModel(
      titleWidget: Text(
        title,
        style: AppTheme.heading(24, color: context.appTextPrimary),
      ),
      bodyWidget: Text(
        body,
        textAlign: TextAlign.center,
        style: AppTheme.body(15, color: context.appTextSecondary),
      ),
      image: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          gradient: AppTheme.primaryGradient,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: kTeal.withOpacity(0.3),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Icon(icon, size: 80, color: Colors.white),
      ),
    );
  }
}

// ─── Splash Screen ────────────────────────────────────────────────────────────
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;
  late Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..forward();

    _scaleAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.5, curve: Curves.elasticOut),
      ),
    );
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.4, 0.8, curve: Curves.easeIn),
      ),
    );
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _ctrl,
            curve: const Interval(0.4, 0.8, curve: Curves.easeOut),
          ),
        );
    _glowAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.3, 0.7, curve: Curves.easeOut),
      ),
    );

    _ctrl.addStatusListener((s) {
      if (s == AnimationStatus.completed) _goNext();
    });
  }

  Future<void> _goNext() async {
    await Future.delayed(const Duration(milliseconds: 500));
    final user = auth.currentUser;
    if (!mounted) return;
    if (user == null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      return;
    }
    try {
      final snap = await db.collection('users').doc(user.uid).get();
      if (!snap.exists) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
        return;
      }
      final role = ((snap.data()?['role'] as String?) ?? 'user')
          .toLowerCase()
          .trim();
      if (!mounted) return;
      _navigateByRole(role);
    } catch (_) {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    }
  }

  void _navigateByRole(String role) {
    if (role.contains('admin')) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AdminHomeScreen()),
      );
    } else if (role.contains('supplier')) {
      final type = role.contains('land') ? 'land' : 'electronics';
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => SupplierHomeScreen(type: type)),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const UserHomeScreen()),
      );
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      body: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => Stack(
          children: [
            // Background gradient
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF003D38),
                    Color(0xFF00695C),
                    Color(0xFF009688),
                    Color(0xFF26A69A),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),

            // Decorative orb top-right
            Positioned(
              top: -size.width * 0.25,
              right: -size.width * 0.20,
              child: Container(
                width: size.width * 0.7,
                height: size.width * 0.7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.06),
                ),
              ),
            ),

            // Decorative orb bottom-left
            Positioned(
              bottom: -size.width * 0.30,
              left: -size.width * 0.20,
              child: Container(
                width: size.width * 0.8,
                height: size.width * 0.8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.05),
                ),
              ),
            ),

            // Main content
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Glassmorphism rounded-square logo card
                  Transform.scale(
                    scale: _scaleAnim.value,
                    child: Container(
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(32),
                        color: Colors.white.withOpacity(0.12),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.28),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF003D38).withOpacity(0.50),
                            blurRadius: 40,
                            offset: const Offset(0, 18),
                          ),
                          BoxShadow(
                            color: Colors.white.withOpacity(0.07),
                            blurRadius: 20,
                            offset: const Offset(0, -6),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(32),
                        child: Padding(
                          padding: const EdgeInsets.all(22),
                          child: Image.asset(
                            'assets/logoss.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 44),

                  // Text + loader
                  FadeTransition(
                    opacity: _fadeAnim,
                    child: SlideTransition(
                      position: _slideAnim,
                      child: Column(
                        children: [
                          Text(
                            'Digital Goods',
                            style: AppTheme.heading(34, color: Colors.white)
                                .copyWith(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 22,
                                height: 1,
                                color: Colors.white.withOpacity(0.4),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                child: Text(
                                  'Verify. Secure. Own.',
                                  style: AppTheme.body(
                                    13,
                                    color: Colors.white.withOpacity(0.76),
                                  ).copyWith(letterSpacing: 2.2),
                                ),
                              ),
                              Container(
                                width: 22,
                                height: 1,
                                color: Colors.white.withOpacity(0.4),
                              ),
                            ],
                          ),
                          const SizedBox(height: 60),
                          // Animated bouncing dot loader
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(3, (i) {
                              final delay = i / 3.0;
                              final t = ((_glowAnim.value - delay) % 1.0).clamp(
                                0.0,
                                1.0,
                              );
                              final bounce = (t < 0.5 ? t : 1.0 - t) * 2.0;
                              return Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                ),
                                width: 7,
                                height: 7 + bounce * 6,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(
                                    0.45 + bounce * 0.55,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              );
                            }),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── User doc helper ──────────────────────────────────────────────────────────
Future<void> createUserDocIfNotExists(
  User user, {
  String role = 'user',
  String? photoBase64,
}) async {
  final docRef = db.collection('users').doc(user.uid);
  final snap = await docRef.get();
  if (!snap.exists) {
    await docRef.set({
      'uid': user.uid,
      'name': user.displayName ?? '',
      'email': user.email ?? '',
      'phone': user.phoneNumber ?? '',
      'photoBase64': photoBase64 ?? '',
      'role': role,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}

// ─── Google Sign-In ───────────────────────────────────────────────────────────
Future<User?> signInWithGoogle(BuildContext ctx) async {
  try {
    final gUser = await GoogleSignIn().signIn();
    if (gUser == null) return null;
    final gAuth = await gUser.authentication;
    final cred = GoogleAuthProvider.credential(
      accessToken: gAuth.accessToken,
      idToken: gAuth.idToken,
    );
    final userCred = await auth.signInWithCredential(cred);
    return userCred.user;
  } catch (e) {
    if (ctx.mounted) {
      _showSnack(ctx, 'Google sign-in failed: $e', color: Colors.red);
    }
    return null;
  }
}

void _showSnack(BuildContext ctx, String msg, {Color? color}) {
  ScaffoldMessenger.of(ctx).showSnackBar(
    SnackBar(
      content: Text(msg),
      backgroundColor: color ?? AppTheme.primaryStart,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );
}

// ─── Login Screen ─────────────────────────────────────────────────────────────
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;

  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_emailCtrl.text.trim().isEmpty || _passCtrl.text.trim().isEmpty) {
      _showSnack(context, 'Please enter email & password');
      return;
    }
    setState(() => _loading = true);
    try {
      final cred = await auth.signInWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text.trim(),
      );
      final snap = await db.collection('users').doc(cred.user!.uid).get();
      if (!snap.exists) {
        if (mounted) {
          _showSnack(
            context,
            'Account record missing. Please register your role.',
            color: Colors.orange,
          );
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const RegisterScreen()),
          );
        }
        return;
      }
      final role = (snap.data()?['role'] as String? ?? 'user')
          .toLowerCase()
          .trim();
      if (!mounted) return;
      _navigateByRole(role);
    } catch (e) {
      if (mounted) _showSnack(context, 'Login failed: $e', color: Colors.red);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _googleLogin() async {
    final user = await signInWithGoogle(context);
    if (user != null) {
      final snap = await db.collection('users').doc(user.uid).get();
      if (!snap.exists) {
        // 🛑 IMPORTANT: If doc is missing, don't auto-create as 'user'.
        // Redirect to Register so they can choose 'Supplier' if they want.
        if (mounted) {
          _showSnack(
            context,
            'Account record missing. Please register your role.',
            color: Colors.orange,
          );
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const RegisterScreen()),
          );
        }
        if (mounted) setState(() => _loading = false);
        return;
      }
      final role = ((snap.data()?['role'] as String?) ?? 'user')
          .toLowerCase()
          .trim();
      if (mounted) _navigateByRole(role);
    }
    if (mounted) setState(() => _loading = false);
  }

  void _navigateByRole(String role) {
    if (role.contains('admin')) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AdminHomeScreen()),
      );
    } else if (role.contains('supplier')) {
      final type = role.contains('land') ? 'land' : 'electronics';
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => SupplierHomeScreen(type: type)),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const UserHomeScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appScaffold,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [kTealDark, kTeal],
            begin: Alignment.topLeft,
            end: Alignment(0.4, 0.5),
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ── Top hero area ─────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Image.asset('assets/logoss.png', height: 28),
                        //   child: const Icon(Icons.apartment_rounded,
                        //     color: Colors.white, size: 28),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Welcome Back!',
                        style: AppTheme.heading(28, color: Colors.white),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Sign in to continue',
                        style: AppTheme.body(
                          14,
                          color: Colors.white.withOpacity(0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── White bottom card ─────────────────────────────────
              Expanded(
                child: SlideTransition(
                  position: _slideAnim,
                  child: FadeTransition(
                    opacity: _fadeAnim,
                    child: Container(
                      decoration: BoxDecoration(
                        color: context.appSurface,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(32),
                          topRight: Radius.circular(32),
                        ),
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 30, 24, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Email
                            TextField(
                              controller: _emailCtrl,
                              keyboardType: TextInputType.emailAddress,
                              style: AppTheme.body(
                                14,
                                color: context.appTextPrimary,
                              ),
                              decoration: _inputDecoration(
                                context,
                                'Email Address',
                                prefix: const Icon(
                                  Icons.email_outlined,
                                  color: AppTheme.primaryStart,
                                  size: 20,
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Password
                            TextField(
                              controller: _passCtrl,
                              obscureText: _obscure,
                              style: AppTheme.body(
                                14,
                                color: context.appTextPrimary,
                              ),
                              decoration: _inputDecoration(
                                context,
                                'Password',
                                prefix: const Icon(
                                  Icons.lock_outline_rounded,
                                  color: AppTheme.primaryStart,
                                  size: 20,
                                ),
                                suffix: IconButton(
                                  icon: Icon(
                                    _obscure
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                    color: context.appTextSecondary,
                                    size: 20,
                                  ),
                                  onPressed: () =>
                                      setState(() => _obscure = !_obscure),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),

                            // Forgot password
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const ForgotPasswordScreen(),
                                  ),
                                ),
                                child: Text(
                                  'Forgot Password?',
                                  style: AppTheme.heading(
                                    13,
                                    color: AppTheme.primaryStart,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),

                            // Login button
                            _GradientButton(
                              label: 'Sign In',
                              loading: _loading,
                              onPressed: _login,
                            ),
                            const SizedBox(height: 20),

                            // Divider
                            Row(
                              children: [
                                Expanded(
                                  child: Divider(color: kTeal.withOpacity(0.2)),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  child: Text(
                                    'or',
                                    style: AppTheme.body(
                                      13,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Divider(color: kTeal.withOpacity(0.2)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // Google button
                            _GoogleButton(
                              onPressed: _loading ? null : _googleLogin,
                            ),
                            const SizedBox(height: 24),

                            // Register link
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  "Don't have an account? ",
                                  style: AppTheme.body(
                                    13,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const RegisterScreen(),
                                    ),
                                  ),
                                  child: Text(
                                    'Register',
                                    style: AppTheme.heading(
                                      13,
                                      color: AppTheme.primaryStart,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Register Screen ──────────────────────────────────────────────────────────
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with SingleTickerProviderStateMixin {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _companyCtrl = TextEditingController();
  final _cnicCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();

  String _role = 'user';
  String _supplierType = 'land';
  Uint8List? _photo;
  bool _loading = false;
  bool _obscure = true;
  bool _agreeToTerms = false;
  final _picker = ImagePicker();

  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    for (final c in [
      _nameCtrl,
      _emailCtrl,
      _phoneCtrl,
      _passCtrl,
      _confirmCtrl,
      _companyCtrl,
      _cnicCtrl,
      _cityCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final status = await Permission.photos.request();
    if (!status.isGranted) return;
    final XFile? file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );
    if (file != null) {
      _photo = await file.readAsBytes();
      setState(() {});
    }
  }

  Future<void> _register() async {
    if (_passCtrl.text != _confirmCtrl.text) {
      _showSnack(context, 'Passwords do not match', color: Colors.red);
      return;
    }
    if (_emailCtrl.text.isEmpty || _passCtrl.text.isEmpty) {
      _showSnack(context, 'Email and password required');
      return;
    }
    if (!_agreeToTerms) {
      _showSnack(context, 'You must agree to the Terms & Privacy Policy to register', color: Colors.red);
      return;
    }
    setState(() => _loading = true);
    try {
      final userCred = await auth.createUserWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text.trim(),
      );
      final uid = userCred.user!.uid;
      final roleString = _role == 'user' ? 'user' : 'supplier_$_supplierType';
      final Map<String, dynamic> data = {
        'uid': uid,
        'name': _nameCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'role': roleString,
        'createdAt': FieldValue.serverTimestamp(),
      };
      if (_role == 'supplier') {
        data.addAll({
          'company': _companyCtrl.text.trim(),
          'cnic': _cnicCtrl.text.trim(),
          'city': _cityCtrl.text.trim(),
        });
      }
      if (_photo != null) {
        data['photoBase64'] = await compressImageToBase64(_photo!);
      }
      await db.collection('users').doc(uid).set(data);
      await userCred.user!.updateDisplayName(roleString);
      if (!mounted) return;
      _showSnack(
        context,
        '✅ Account created! Please login.',
        color: Colors.green,
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted) _showSnack(context, 'Error: $e', color: Colors.red);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _googleRegister() async {
    setState(() => _loading = true);
    final user = await signInWithGoogle(context);
    if (user != null) {
      final docRef = db.collection('users').doc(user.uid);
      final snap = await docRef.get();
      if (!snap.exists) {
        await docRef.set({
          'uid': user.uid,
          'name': user.displayName ?? '',
          'email': user.email ?? '',
          'phone': user.phoneNumber ?? '',
          'photoBase64': '',
          'role': 'user',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      final role = ((await docRef.get()).data()?['role'] as String? ?? 'user')
          .toLowerCase()
          .trim();
      if (!mounted) return;
      _navigateByRole(role);
    }
    if (mounted) setState(() => _loading = false);
  }

  void _navigateByRole(String role) {
    if (role.contains('admin')) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AdminHomeScreen()),
      );
    } else if (role.contains('supplier')) {
      final type = role.contains('land') ? 'land' : 'electronics';
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => SupplierHomeScreen(type: type)),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const UserHomeScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appScaffold,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [kTealDark, kTeal],
            begin: Alignment.topLeft,
            end: Alignment(0.4, 0.4),
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Top bar
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Create Account',
                            style: AppTheme.heading(20, color: Colors.white),
                          ),
                          Text(
                            'Join Digital Goods today',
                            style: AppTheme.body(
                              12,
                              color: Colors.white.withOpacity(0.8),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Form card
              Expanded(
                child: SlideTransition(
                  position: _slideAnim,
                  child: FadeTransition(
                    opacity: _fadeAnim,
                    child: Container(
                      decoration: BoxDecoration(
                        color: context.appSurface,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(32),
                          topRight: Radius.circular(32),
                        ),
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Avatar picker
                            Center(
                              child: GestureDetector(
                                onTap: _pickPhoto,
                                child: Stack(
                                  children: [
                                    CircleAvatar(
                                      radius: 50,
                                      backgroundColor: AppTheme.primaryStart
                                          .withOpacity(0.12),
                                      backgroundImage: _photo != null
                                          ? MemoryImage(_photo!)
                                          : null,
                                      child: _photo == null
                                          ? const Icon(
                                              Icons.person_rounded,
                                              size: 44,
                                              color: AppTheme.primaryStart,
                                            )
                                          : null,
                                    ),
                                    Positioned(
                                      bottom: 0,
                                      right: 0,
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: const BoxDecoration(
                                          color: kTeal,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.camera_alt_rounded,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Role chips
                            _SectionLabel('Account Type'),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                _RoleChip(
                                  label: 'User',
                                  icon: Icons.person_rounded,
                                  selected: _role == 'user',
                                  onTap: () => setState(() => _role = 'user'),
                                ),
                                const SizedBox(width: 10),
                                _RoleChip(
                                  label: 'Supplier',
                                  icon: Icons.business_rounded,
                                  selected: _role == 'supplier',
                                  onTap: () =>
                                      setState(() => _role = 'supplier'),
                                ),
                              ],
                            ),

                            if (_role == 'supplier') ...[
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  _RoleChip(
                                    label: 'Land',
                                    icon: Icons.landscape_rounded,
                                    selected: _supplierType == 'land',
                                    onTap: () =>
                                        setState(() => _supplierType = 'land'),
                                  ),
                                  const SizedBox(width: 10),
                                  _RoleChip(
                                    label: 'Electronics',
                                    icon: Icons.devices_rounded,
                                    selected: _supplierType == 'electronics',
                                    onTap: () => setState(
                                      () => _supplierType = 'electronics',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 22),

                            // Fields
                            _SectionLabel('Personal Info'),
                            const SizedBox(height: 10),
                            _Field(
                              ctrl: _nameCtrl,
                              label: 'Full Name',
                              icon: Icons.person_outline_rounded,
                            ),
                            const SizedBox(height: 12),
                            _Field(
                              ctrl: _emailCtrl,
                              label: 'Email',
                              icon: Icons.email_outlined,
                              type: TextInputType.emailAddress,
                            ),
                            const SizedBox(height: 12),
                            _Field(
                              ctrl: _phoneCtrl,
                              label: 'Phone',
                              icon: Icons.phone_outlined,
                              type: TextInputType.phone,
                            ),
                            const SizedBox(height: 12),
                            _PasswordField(
                              ctrl: _passCtrl,
                              label: 'Password',
                              obscure: _obscure,
                              onToggle: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                            const SizedBox(height: 12),
                            _PasswordField(
                              ctrl: _confirmCtrl,
                              label: 'Confirm Password',
                              obscure: _obscure,
                              onToggle: () =>
                                  setState(() => _obscure = !_obscure),
                            ),

                            if (_role == 'supplier') ...[
                              const SizedBox(height: 22),
                              _SectionLabel('Business Info'),
                              const SizedBox(height: 10),
                              _Field(
                                ctrl: _companyCtrl,
                                label: 'Company / Brand',
                                icon: Icons.business_outlined,
                              ),
                              const SizedBox(height: 12),
                              _Field(
                                ctrl: _cnicCtrl,
                                label: 'CNIC / NTN',
                                icon: Icons.badge_outlined,
                              ),
                              const SizedBox(height: 12),
                              _Field(
                                ctrl: _cityCtrl,
                                label: 'City',
                                icon: Icons.location_on_outlined,
                              ),
                            ],

                            const SizedBox(height: 16),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: Checkbox(
                                    value: _agreeToTerms,
                                    activeColor: kTeal,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    onChanged: (val) {
                                      setState(() {
                                        _agreeToTerms = val ?? false;
                                      });
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: RichText(
                                    text: TextSpan(
                                      style: AppTheme.body(
                                        12,
                                        color: context.appTextSecondary,
                                      ),
                                      children: [
                                        const TextSpan(text: 'I agree to the '),
                                        WidgetSpan(
                                          alignment: PlaceholderAlignment.middle,
                                          child: GestureDetector(
                                            onTap: () => Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => const TermsScreen(initialTabIndex: 0),
                                              ),
                                            ),
                                            child: Text(
                                              'Terms of Service',
                                              style: AppTheme.heading(
                                                12,
                                                color: kTeal,
                                                weight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const TextSpan(text: ' & '),
                                        WidgetSpan(
                                          alignment: PlaceholderAlignment.middle,
                                          child: GestureDetector(
                                            onTap: () => Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => const TermsScreen(initialTabIndex: 1),
                                              ),
                                            ),
                                            child: Text(
                                              'Privacy Policy',
                                              style: AppTheme.heading(
                                                12,
                                                color: kTeal,
                                                weight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),

                            _GradientButton(
                              label: 'Create Account',
                              loading: _loading,
                              onPressed: _register,
                            ),

                            if (_role == 'user') ...[
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: Divider(
                                      color: kTeal.withOpacity(0.2),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    child: Text(
                                      'or',
                                      style: AppTheme.body(
                                        13,
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Divider(
                                      color: kTeal.withOpacity(0.2),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              _GoogleButton(
                                label: 'Register with Google',
                                onPressed: _loading ? null : _googleRegister,
                              ),
                            ],

                            const SizedBox(height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Already have an account? ',
                                  style: AppTheme.body(
                                    13,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => Navigator.pop(context),
                                  child: Text(
                                    'Login',
                                    style: AppTheme.heading(
                                      13,
                                      color: AppTheme.primaryStart,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Forgot Password Screen ───────────────────────────────────────────────────
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen>
    with SingleTickerProviderStateMixin {
  final _emailCtrl = TextEditingController();
  bool _loading = false;
  bool _sent = false;

  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _reset() async {
    if (_emailCtrl.text.trim().isEmpty) {
      _showSnack(context, 'Please enter your email');
      return;
    }
    setState(() => _loading = true);
    try {
      await auth.sendPasswordResetEmail(email: _emailCtrl.text.trim());
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted) _showSnack(context, 'Error: $e', color: Colors.red);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appScaffold,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [kTealDark, kTeal],
            begin: Alignment.topLeft,
            end: Alignment(0.4, 0.5),
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Top bar
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        'Forgot Password',
                        style: AppTheme.heading(20, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),

              // Card
              Expanded(
                child: SlideTransition(
                  position: _slideAnim,
                  child: FadeTransition(
                    opacity: _fadeAnim,
                    child: Container(
                      decoration: BoxDecoration(
                        color: context.appSurface,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(32),
                          topRight: Radius.circular(32),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: _sent ? _buildSuccessState() : _buildFormState(),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFormState() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: context.appSurfaceMuted,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              const Icon(Icons.lock_reset_rounded, size: 48, color: kTeal),
              const SizedBox(height: 12),
              Text(
                'Reset your password',
                style: AppTheme.heading(17, color: context.appTextPrimary),
              ),
              const SizedBox(height: 6),
              Text(
                'Enter your email and we will send a reset link.',
                textAlign: TextAlign.center,
                style: AppTheme.body(13, color: context.appTextSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          style: AppTheme.body(14, color: context.appTextPrimary),
          decoration: _inputDecoration(
            context,
            'Email Address',
            prefix: const Icon(Icons.email_outlined, color: kTeal, size: 20),
          ),
        ),
        const SizedBox(height: 24),
        _GradientButton(
          label: 'Send Reset Link',
          loading: _loading,
          onPressed: _reset,
          icon: Icons.send_rounded,
        ),
      ],
    );
  }

  Widget _buildSuccessState() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 500),
      builder: (_, v, __) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, 20 * (1 - v)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.mark_email_read_rounded,
                  size: 56,
                  color: Colors.green,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Email Sent!',
                style: AppTheme.heading(22, color: context.appTextPrimary),
              ),
              const SizedBox(height: 10),
              Text(
                'Check your inbox for the password reset link.',
                textAlign: TextAlign.center,
                style: AppTheme.body(
                  14,
                  color: context.appTextSecondary,
                ).copyWith(height: 1.5),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kTeal,
                    side: const BorderSide(color: kTeal),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                    'Back to Login',
                    style: AppTheme.heading(14, color: AppTheme.primaryStart),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Reusable small widgets ───────────────────────────────────────────────────
class _GradientButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback onPressed;
  final IconData? icon;

  const _GradientButton({
    required this.label,
    required this.loading,
    required this.onPressed,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 52,
      decoration: BoxDecoration(
        gradient: loading ? null : AppTheme.primaryGradient,
        color: loading ? Colors.grey.shade300 : null,
        borderRadius: BorderRadius.circular(14),
        boxShadow: loading
            ? []
            : [
                BoxShadow(
                  color: kTeal.withOpacity(0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: loading ? null : onPressed,
          child: Center(
            child: loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, color: Colors.white, size: 18),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        label,
                        style: AppTheme.body(
                          15,
                          weight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _GoogleButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String label;

  const _GoogleButton({this.onPressed, this.label = 'Continue with Google'});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: context.appSurface,
          side: BorderSide(color: context.appBorder),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.network(
              'https://developers.google.com/identity/images/g-logo.png',
              height: 20,
              width: 20,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.g_mobiledata, color: Colors.red),
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: AppTheme.heading(14, color: context.appTextPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _RoleChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? kTeal : context.appSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? kTeal : context.appBorder),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: kTeal.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [],
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? Colors.white : context.appTextSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTheme.heading(
                13,
                color: selected ? Colors.white : context.appTextSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) =>
      Text(text, style: AppTheme.heading(13, color: context.appTextPrimary));
}

class _Field extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final IconData icon;
  final TextInputType? type;

  const _Field({
    required this.ctrl,
    required this.label,
    required this.icon,
    this.type,
  });

  @override
  Widget build(BuildContext context) => TextField(
    controller: ctrl,
    keyboardType: type,
    style: GoogleFonts.poppins(fontSize: 14, color: context.appTextPrimary),
    decoration: _inputDecoration(
      context,
      label,
      prefix: Icon(icon, color: kTeal, size: 20),
    ),
  );
}

class _PasswordField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final bool obscure;
  final VoidCallback onToggle;

  const _PasswordField({
    required this.ctrl,
    required this.label,
    required this.obscure,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) => TextField(
    controller: ctrl,
    obscureText: obscure,
    style: AppTheme.body(14, color: context.appTextPrimary),
    decoration: _inputDecoration(
      context,
      label,
      prefix: const Icon(Icons.lock_outline_rounded, color: kTeal, size: 20),
      suffix: IconButton(
        icon: Icon(
          obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          color: context.appTextSecondary,
          size: 20,
        ),
        onPressed: onToggle,
      ),
    ),
  );
}
