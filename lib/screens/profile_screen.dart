// lib/screens/profile_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../blockchain/ipfs_service.dart'; // ← your existing service
import '../blockchain/blockchain_service.dart';
import 'shared_screens.dart';
import 'asset_screen.dart';
import 'asset_detail_screen.dart';
import 'stolen_report_screen.dart';
import 'auth_screens.dart';
import '../theme.dart';
import 'EmailSupportScreen.dart';
import 'terms_screen.dart';

final FirebaseAuth _auth = FirebaseAuth.instance;
final FirebaseFirestore _db = FirebaseFirestore.instance;
final IPFSService _ipfs = IPFSService();

Future<List<DocumentSnapshot<Map<String, dynamic>>>> _loadFavoriteAssets(
    List<String> assetIds,
    ) async {
  if (assetIds.isEmpty) return const [];

  final chunks = <List<String>>[];
  for (int i = 0; i < assetIds.length; i += 10) {
    final end = (i + 10 < assetIds.length) ? i + 10 : assetIds.length;
    chunks.add(assetIds.sublist(i, end));
  }

  final snapshots = await Future.wait(
    chunks.map(
          (chunk) => FirebaseFirestore.instance
          .collection('assets')
          .where(FieldPath.documentId, whereIn: chunk)
          .get(),
    ),
  );

  final byId = <String, DocumentSnapshot<Map<String, dynamic>>>{};
  for (final snap in snapshots) {
    for (final doc in snap.docs) {
      byId[doc.id] = doc;
    }
  }

  return [
    for (final id in assetIds)
      if (byId.containsKey(id)) byId[id]!,
  ];
}

// ─────────────────────────────────────────────────────────────────────────────
// PROFILE SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class ProfileScreen extends StatefulWidget {
  final VoidCallback? onBack;
  final bool showFavorites;
  const ProfileScreen({super.key, this.onBack, this.showFavorites = true});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _userDocStream;
  bool _uploadingPhoto = false;
  int _index = 0;

  static const Color _teal = Color(0xFF2D8C8C);

  @override
  void initState() {
    super.initState();
    final user = _auth.currentUser;
    if (user != null) {
      _userDocStream = _db.collection('users').doc(user.uid).snapshots();
    }
  }

  // ── Photo bottom sheet ────────────────────────────────────────────────────
  void _showPhotoOptions({
    required String currentPhotoUrl,
    required String currentCid,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.appSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // handle bar
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: context.appBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              'Profile Photo',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: context.appTextPrimary,
              ),
            ),
            const SizedBox(height: 8),
            _sheetTile(
              icon: Icons.photo_camera_rounded,
              label: 'Take a photo',
              onTap: () {
                Navigator.pop(context);
                _pickAndUpload(ImageSource.camera);
              },
            ),
            _sheetTile(
              icon: Icons.photo_library_rounded,
              label: 'Choose from gallery',
              onTap: () {
                Navigator.pop(context);
                _pickAndUpload(ImageSource.gallery);
              },
            ),
            if (currentPhotoUrl.isNotEmpty)
              _sheetTile(
                icon: Icons.delete_outline_rounded,
                label: 'Remove photo',
                color: Colors.red.shade400,
                onTap: () {
                  Navigator.pop(context);
                  _removePhoto(cid: currentCid);
                },
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _sheetTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color color = _teal,
  }) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(
        label,
        style: TextStyle(
          color: color == _teal ? context.appTextPrimary : color,
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: onTap,
    );
  }

  // ── Pick image → upload to IPFS via IPFSService ───────────────────────────
  Future<void> _pickAndUpload(ImageSource source) async {
    final user = _auth.currentUser;
    if (user == null) return;

    // 1. Pick image
    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 512,
    );
    if (picked == null) return;

    setState(() => _uploadingPhoto = true);
    try {
      // 2. Read bytes (IPFSService needs Uint8List)
      final bytes = await picked.readAsBytes();
      final fileName = 'profile_${user.uid}.jpg';

      // 3. Upload via your IPFSService
      final result = await _ipfs.uploadFile(
        fileBytes: bytes,
        fileName: fileName,
        metadata: {'uid': user.uid, 'type': 'profile_photo'},
      );

      if (!result.success) {
        throw Exception(result.error ?? 'IPFS upload failed');
      }

      final photoUrl = result.ipfsUrl!;
      final photoCid = result.ipfsHash!;

      // 4. Persist to Firestore + Firebase Auth profile
      await _db.collection('users').doc(user.uid).update({
        'photoUrl': photoUrl,
        'photoCid': photoCid,
      });
      await user.updatePhotoURL(photoUrl);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile photo updated ✅')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _removePhoto({required String cid}) async {
    final user = _auth.currentUser;
    if (user == null) return;

    setState(() => _uploadingPhoto = true);
    try {
      await _db.collection('users').doc(user.uid).update({
        'photoUrl': '',
        'photoCid': '',
      });
      await user.updatePhotoURL(null);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Profile photo removed')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  // ── Reset password ────────────────────────────────────────────────────────
  Future<void> _sendResetPasswordEmail() async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      await _auth.sendPasswordResetEmail(email: user.email ?? '');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reset password email sent')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  // ── Logout ────────────────────────────────────────────────────────────────
  Future<void> _logout() async {
    clearRoleCache(); // 🚀 Clear cache
    await _auth.signOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
          (_) => false,
    );
  }

  // ── UI helpers ────────────────────────────────────────────────────────────
  Widget _menuTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color iconColor = _teal,
    bool showDivider = true,
  }) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: context.appTextPrimary,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: context.appTextSecondary,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
        if (showDivider)
          Divider(height: 1, thickness: 1, color: context.appBorder),
      ],
    );
  }

  Widget _card({required List<Widget> children}) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      color: context.appSurface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: context.appBorder),
      boxShadow: [
        BoxShadow(
          color: context.appShadow,
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Column(children: children),
  );

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    if (user == null) {
      return Scaffold(
        backgroundColor: context.appScaffold,
        body: Center(
          child: Text(
            'Not logged in',
            style: TextStyle(color: context.appTextPrimary),
          ),
        ),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _userDocStream,
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.data() == null) {
          return Scaffold(
            backgroundColor: context.appScaffold,

            appBar: _index == 4
                ? null
                : _index == 3
                ? AppBar(
              backgroundColor: context.appSurface,
              title: Text(
                'Profile',
                style: TextStyle(color: context.appTextPrimary),
              ),
            )
                : null,

            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.account_circle_outlined,
                    size: 64,
                    color: AppTheme.primaryStart,
                  ),

                  const SizedBox(height: 16),

                  Text(
                    'No profile found. Please register.',
                    style: TextStyle(
                      fontSize: 16,
                      color: context.appTextSecondary,
                    ),
                  ),

                  const SizedBox(height: 24),

                  ElevatedButton(
                    onPressed: () => Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const LoginScreen(),
                      ),
                    ),
                    child: const Text('Go to Registration'),
                  ),
                ],
              ),
            ),
          );
        }

        final data = snap.data!.data()!;
        final displayEmail = user.email ?? '';
        final name = data['name'] ?? user.displayName ?? '';
        final role = data['role'] ?? 'user';
        final photoUrl = (data['photoUrl'] as String?) ?? user.photoURL ?? '';
        final photoCid = (data['photoCid'] as String?) ?? '';
        final displayName = name.isNotEmpty ? name : displayEmail;

        return Scaffold(
          backgroundColor: context.appScaffold,

          // ── AppBar ───────────────────────────────────────────────────────
          appBar: AppBar(
            backgroundColor: context.appSurface,
            elevation: 0,
            centerTitle: true,
            automaticallyImplyLeading: false,
            title: Text(
              'Profile',
              style: TextStyle(
                color: context.appTextPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            leading: IconButton(
              icon: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: context.appSurfaceMuted,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.chevron_left_rounded,
                  color: context.appTextPrimary,
                  size: 24,
                ),
              ),
              onPressed: () {
                if (widget.onBack != null) {
                  widget.onBack!();
                } else if (Navigator.canPop(context)) {
                  Navigator.pop(context);
                }
              },
            ),
          ),

          body: Column(
            children: [
              // ── Profile header ───────────────────────────────────────────
              Container(
                color: context.appSurface,
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
                child: Row(
                  children: [
                    // Tappable avatar
                    GestureDetector(
                      onTap: () => _showPhotoOptions(
                        currentPhotoUrl: photoUrl,
                        currentCid: photoCid,
                      ),
                      child: Stack(
                        children: [
                          Container(
                            width: 74,
                            height: 74,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _teal.withOpacity(0.12),
                              border: Border.all(
                                color: _teal.withOpacity(0.3),
                                width: 2.5,
                              ),
                            ),
                            child: ClipOval(
                              child: _uploadingPhoto
                                  ? const Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: _teal,
                                ),
                              )
                                  : photoUrl.isNotEmpty
                                  ? Image.network(
                                photoUrl,
                                fit: BoxFit.cover,
                                cacheWidth: 256,
                                filterQuality: FilterQuality.low,
                                gaplessPlayback: true,
                                // Show spinner while loading
                                loadingBuilder: (_, child, progress) =>
                                progress == null
                                    ? child
                                    : const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: _teal,
                                  ),
                                ),
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.person_rounded,
                                  size: 38,
                                  color: _teal,
                                ),
                              )
                                  : const Icon(
                                Icons.person_rounded,
                                size: 38,
                                color: _teal,
                              ),
                            ),
                          ),
                          // Edit badge
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: _teal,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: context.appSurface,
                                  width: 2,
                                ),
                              ),
                              child: const Icon(
                                Icons.edit_rounded,
                                size: 12,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 18),

                    // Name / email / role
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: context.appTextPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            displayEmail,
                            style: TextStyle(
                              fontSize: 13,
                              color: context.appTextSecondary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _teal.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              role.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: _teal,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // ── Menu sections ────────────────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      // Section 1 — main features
                      _card(
                        children: [
                          if (widget.showFavorites)
                            _menuTile(
                              icon: Icons.favorite_rounded,
                              label: 'Favorites',
                              iconColor: const Color(0xFFE57373),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const FavoritesScreen(),
                                ),
                              ),
                            ),
                          _menuTile(
                            icon: Icons.report_problem_rounded,
                            label: 'Stolen Reports',
                            iconColor: const Color(0xFFFF8A65),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const StolenReportScreen(),
                              ),
                            ),
                          ),
                          _menuTile(
                            icon: Icons.swap_horiz_rounded,
                            label: 'Transactions',
                            showDivider: false,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const TransactionsScreen(),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // Section 2 — account
                      _card(
                        children: [
                          _menuTile(
                            icon: Icons.lock_reset_rounded,
                            label: 'Reset Password',
                            iconColor: const Color(0xFF7986CB),
                            onTap: _sendResetPasswordEmail,
                          ),
                          _menuTile(
                            icon: Icons.settings_rounded,
                            label: 'Settings',
                            showDivider: false,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const SettingsScreen(),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // Section 3 — support
                      _card(
                        children: [
                          _menuTile(
                            icon: Icons.help_outline_rounded,
                            label: 'Help & Support',
                            iconColor: const Color(0xFF4DB6AC),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const HelpScreen(),                          
                              ),                             
                            ),
                            
                          ),
                         _menuTile(
  icon: Icons.email_outlined,
  label: 'Email Support',
  iconColor: const Color(0xFF4DB6AC),
  onTap: () => Navigator.push(context,
    MaterialPageRoute(builder: (_) => const EmailSupportScreen())),
),
                          _menuTile(
                            icon: Icons.privacy_tip_outlined,
                            label: 'Terms & Privacy',
                            iconColor: const Color(0xFF78909C),
                            showDivider: false,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const TermsScreen(),
                              ),
                            ),
                          ),
                        ],
                      ),

                      if (role == 'admin') ...[
                        const SizedBox(height: 12),
                        _card(
                          children: [
                            _menuTile(
                              icon: Icons.admin_panel_settings_rounded,
                              label: 'Admin Tools',
                              iconColor: const Color(0xFF673AB7),
                              showDivider: false,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const AdminPanelScreen(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],

                      const SizedBox(height: 24),

                      // Logout
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _teal,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: _logout,
                            icon: const Icon(Icons.logout_rounded, size: 20),
                            label: const Text(
                              'Logout',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FAVORITES SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  static const Color _teal = Color(0xFF2D8C8C);

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return Scaffold(
        backgroundColor: context.appScaffold,
        body: Center(
          child: Text(
            'Not logged in',
            style: TextStyle(color: context.appTextPrimary),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: context.appScaffold,
      appBar: AppBar(
        backgroundColor: context.appSurface,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'Favorites',
          style: TextStyle(
            color: context.appTextPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          icon: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: context.appSurfaceMuted,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.chevron_left_rounded,
              color: context.appTextPrimary,
              size: 24,
            ),
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('favorites')
            .where('userId', isEqualTo: uid)
            .snapshots(),
        builder: (context, favSnap) {
          if (favSnap.hasError) {
            return Center(
              child: Text(
                'Error: ${favSnap.error}',
                style: TextStyle(color: context.appTextPrimary),
              ),
            );
          }
          if (!favSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final favDocs = favSnap.data!.docs;
          // Sort newest-first client-side (avoids composite index requirement)
          favDocs.sort((a, b) {
            final aTs = (a.data() as Map)['savedAt'];
            final bTs = (b.data() as Map)['savedAt'];
            if (aTs == null || bTs == null) return 0;
            return (bTs as Timestamp).compareTo(aTs as Timestamp);
          });

          if (favDocs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.favorite_border_rounded,
                    size: 72,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No favorites yet',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: context.appTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap ♡ on any listing to save it here',
                    style: TextStyle(
                      fontSize: 13,
                      color: context.appTextSecondary,
                    ),
                  ),
                ],
              ),
            );
          }

          final assetIds = favDocs
              .map(
                (d) => (d.data() as Map<String, dynamic>)['assetId'] as String,
          )
              .toList();

          return FutureBuilder<List<DocumentSnapshot<Map<String, dynamic>>>>(
            future: _loadFavoriteAssets(assetIds),
            builder: (context, assetSnap) {
              if (!assetSnap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final assets = assetSnap.data!.where((d) => d.exists).toList();

              if (assets.isEmpty) {
                return Center(
                  child: Text(
                    'Saved assets no longer available',
                    style: TextStyle(color: context.appTextSecondary),
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: assets.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, i) {
                  final doc = assets[i];
                  final data = doc.data() as Map<String, dynamic>;
                  final imgList = data['images'] as List?;
                  String? firstImg;
                  if (imgList != null &&
                      imgList.isNotEmpty &&
                      imgList[0] is String) {
                    firstImg = imgList[0] as String;
                  }
                  final city = (data['city'] ?? data['location'] ?? '')
                      .toString();
                  final price = data['price'] ?? 0;
                  final title = (data['title'] ?? 'Asset').toString();

                  return GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AssetDetailScreen(assetId: doc.id),
                      ),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        color: context.appSurface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: context.appBorder),
                        boxShadow: [
                          BoxShadow(
                            color: context.appShadow,
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          // ── Image ──────────────────────────────
                          Stack(
                            children: [
                              ClipRRect(
                                borderRadius: const BorderRadius.horizontal(
                                  left: Radius.circular(16),
                                ),
                                child: buildAssetImage(
                                  firstImg,
                                  width: 120,
                                  height: 110,
                                ),
                              ),
                              Positioned(
                                top: 8,
                                left: 8,
                                child: _UnfavouriteButton(
                                  assetId: doc.id,
                                  userId: uid,
                                ),
                              ),
                            ],
                          ),

                          // ── Info ───────────────────────────────
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 14,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: context.appTextPrimary,
                                    ),
                                  ),
                                  if (city.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.location_on_outlined,
                                          size: 13,
                                          color: context.appTextSecondary,
                                        ),
                                        const SizedBox(width: 3),
                                        Expanded(
                                          child: Text(
                                            city,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: context.appTextSecondary,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  Text(
                                    'PKR $price',
                                    style: const TextStyle(
                                      color: Color(0xFF2A7F8F),
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // ── Arrow ──────────────────────────────
                          Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: Icon(
                              Icons.chevron_right_rounded,
                              color: context.appTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

// Small stateful widget so the heart button gives instant visual feedback
// before Firestore confirms the delete.
class _UnfavouriteButton extends StatefulWidget {
  final String assetId;
  final String userId;
  const _UnfavouriteButton({required this.assetId, required this.userId});

  @override
  State<_UnfavouriteButton> createState() => _UnfavouriteButtonState();
}

class _UnfavouriteButtonState extends State<_UnfavouriteButton> {
  bool _removing = false;

  Future<void> _remove() async {
    setState(() => _removing = true);
    await FirebaseFirestore.instance
        .collection('favorites')
        .doc('${widget.userId}_${widget.assetId}')
        .delete();
    // No need to reset _removing — StreamBuilder removes the card automatically.
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _removing ? null : _remove,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: context.appSurface.withOpacity(0.92),
          shape: BoxShape.circle,
        ),
        child: _removing
            ? const Padding(
          padding: EdgeInsets.all(5),
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: Colors.red,
          ),
        )
            : const Icon(Icons.favorite_rounded, size: 16, color: Colors.red),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SETTINGS SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _loading = false;
  bool _darkMode = false;
  bool _lastSeenEnabled = true;

  static const Color _teal = Color(0xFF2D8C8C);

  @override
  void initState() {
    super.initState();
    _loadUserSettings();
  }

  Future<void> _loadUserSettings() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    setState(() {
      _darkMode = doc.data()?['darkMode'] ?? false;
      _lastSeenEnabled = doc.data()?['lastSeenEnabled'] ?? true;
    });
  }

  Future<void> _setLastSeen(bool val) async {
    setState(() => _lastSeenEnabled = val);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'lastSeenEnabled': val,
    });
  }

  Future<void> _setDarkMode(bool v) async {
    final user = _auth.currentUser;
    if (user == null) return;
    await _db.collection('users').doc(user.uid).update({'darkMode': v});
    setState(() => _darkMode = v);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Preference saved')));
    }
  }

  Future<void> _deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete account'),
        content: const Text(
          'This will delete your Firebase account and user document. '
              'This requires recent login. Are you sure?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _loading = true);
    try {
      clearRoleCache(); // 🚀 Clear cache
      await _db.collection('users').doc(user.uid).delete().catchError((_) {});
      await user.delete();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
            (_) => false,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appScaffold,
      appBar: AppBar(
        backgroundColor: context.appSurface,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'Settings',
          style: TextStyle(
            color: context.appTextPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          icon: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: context.appSurfaceMuted,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.chevron_left_rounded,
              color: context.appTextPrimary,
              size: 24,
            ),
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                color: context.appSurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.appBorder),
                boxShadow: [
                  BoxShadow(
                    color: context.appShadow,
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  SwitchListTile(
                    title: Text(
                      'Dark Mode',
                      style: TextStyle(
                        color: context.appTextPrimary,
                        fontWeight: FontWeight.w500,
                        fontSize: 15,
                      ),
                    ),
                    subtitle: Text(
                      'Save preference to your account',
                      style: TextStyle(color: context.appTextSecondary),
                    ),
                    value: _darkMode,
                    activeColor: _teal,
                    onChanged: _setDarkMode,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                    ),
                  ),
                  Divider(height: 1, thickness: 1, color: context.appBorder),
                  SwitchListTile(
                    title: Text(
                      'Last Seen',
                      style: TextStyle(
                        color: context.appTextPrimary,
                        fontWeight: FontWeight.w500,
                        fontSize: 15,
                      ),
                    ),
                    subtitle: Text(
                      'Show others when you were last active',
                      style: TextStyle(color: context.appTextSecondary),
                    ),
                    value: _lastSeenEnabled,
                    activeColor: _teal,
                    onChanged: _setLastSeen,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(
                        bottom: Radius.circular(16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _loading
                ? const Center(child: CircularProgressIndicator())
                : SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.isDarkMode
                      ? Colors.red.shade900.withOpacity(0.22)
                      : Colors.red.shade50,
                  foregroundColor: Colors.red,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _deleteAccount,
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
                label: const Text(
                  'Delete Account',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HELP SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appScaffold,
      appBar: AppBar(
        backgroundColor: context.appSurface,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'Help & Support',
          style: TextStyle(
            color: context.appTextPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          icon: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: context.appSurfaceMuted,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.chevron_left_rounded,
              color: context.appTextPrimary,
              size: 24,
            ),
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Contact',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: context.appTextPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'For support, contact: digitalgoods.support@gmail.com',
              style: TextStyle(color: context.appTextSecondary),
            ),
            const SizedBox(height: 16),
            Text(
              'FAQ',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: context.appTextPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '• How to buy?\nBrowse the marketplace, select an asset, complete the payment, and receive ownership through NFT transfer.\n• How to sell?\n List your verified asset on the marketplace, set the price, and transfer ownership to the buyer after purchase.\n• How to verify assets?\nScan the assets QR code or check its NFT record to verify ownership, authenticity, and transaction history.',
              style: TextStyle(color: context.appTextSecondary),
            ),
          ],
        ),
      ),
    );
  }
}



// ─────────────────────────────────────────────────────────────────────────────
// ADMIN PANEL SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  final _addressCtrl = TextEditingController();
  final _bs = BlockchainServiceEnhanced();
  bool _loading = false;
  String _roleType = 'VENDOR_ROLE';

  Future<void> _grantRole() async {
    final addr = _addressCtrl.text.trim();
    if (addr.isEmpty || !addr.startsWith('0x')) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invalid Wallet Address')));
      return;
    }

    setState(() => _loading = true);
    try {
      if (_roleType == 'VENDOR_ROLE') {
        await _bs.grantVendorRole(addr);
      } else {
        await _bs.grantRetailerRole(addr);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$_roleType granted successfully to $addr')),
        );
        _addressCtrl.clear();
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: context.appSurface,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'Admin Tools',
          style: TextStyle(
            color: context.appTextPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          icon: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: context.appSurfaceMuted,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.chevron_left_rounded,
              color: context.appTextPrimary,
              size: 24,
            ),
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      backgroundColor: context.appScaffold,
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: context.appSurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.appBorder),
                boxShadow: [
                  BoxShadow(
                    color: context.appShadow,
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Grant Roles',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: context.appTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Assign VENDOR or RETAILER roles to specific wallet addresses to authorize them to receive products.',
                    style: TextStyle(
                      fontSize: 13,
                      color: context.appTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _addressCtrl,
                    decoration: InputDecoration(
                      labelText: 'Wallet Address (0x...)',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _roleType,
                    items: const [
                      DropdownMenuItem(
                        value: 'VENDOR_ROLE',
                        child: Text('VENDOR_ROLE'),
                      ),
                      DropdownMenuItem(
                        value: 'RETAILER_ROLE',
                        child: Text('RETAILER_ROLE'),
                      ),
                    ],
                    onChanged: (v) => setState(() => _roleType = v!),
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _grantRole,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2D8C8C),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _loading
                          ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                          : const Text(
                        'Grant Role',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
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