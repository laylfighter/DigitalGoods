// lib/screens/user_screens.dart
import 'dart:async';
// import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'shared_screens.dart';
import 'chat_list_screen.dart';
import 'wallet_screen.dart';
import 'qr_scanner_enhanced.dart';
import '../blockchain/blockchain_service.dart';
import '../services/resale_service.dart';
import '../services/push_notification_service.dart';
import 'resale_listing_sheet.dart';
import 'asset_detail_screen.dart';
import 'profile_screen.dart';
import '../theme.dart';

final db = FirebaseFirestore.instance;


// USER HOME SCREEN


class UserHomeScreen extends StatefulWidget {
  const UserHomeScreen({super.key});

  @override
  State<UserHomeScreen> createState() => _UserHomeScreenState();
}

class _UserHomeScreenState extends State<UserHomeScreen> {
  int _index = 0;
  String _category = "land";
  String _landMode = "sale"; // 'sale' or 'rent'
  String _search = "";
  Map<String, dynamic> _filters = {};
  final Set<int> _loadedTabs = {0};

  final GlobalKey _chatKey = GlobalKey();
  final GlobalKey _searchKey = GlobalKey();
  final GlobalKey _scanKey = GlobalKey();
  bool _showHandHelp = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkFirstLaunch();
    });
  }

  Future<void> _checkFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_home_completed', true);
  }

  void _openFilters() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        maxChildSize: 0.95,
        initialChildSize: 0.75,
        builder: (_, controller) => FilterSheet(
          category: _category,
          controller: controller,
          existing: _filters,
        ),
      ),
    );
    if (result != null) setState(() => _filters = result);
  }

  void _nav(int i) {
    if (i == 1) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const QRScannerEnhanced()),
      );
      return;
    }
    setState(() {
      _loadedTabs.add(i);
      _index = i;
    });
  }

  @override
  Widget build(BuildContext context) {
    final surfaceColor = context.appSurface;
    final textPrimary = context.appTextPrimary;
    final textSecondary = context.appTextSecondary;

    return Scaffold(
      appBar: _index == 3
          ? null
          : _index == 2
          ? AppBar(
              backgroundColor: context.appSurface,
              leading: IconButton(
                icon: const Icon(Icons.chevron_left, color: Colors.black),
                onPressed: () => setState(() => _index = 0),
              ),
              title: Text(
                "My Assets",
                style: TextStyle(color: context.appTextPrimary),
              ),
            )
          : AppBar(
              backgroundColor: surfaceColor,
              elevation: 0,
              leading: Padding(
                padding: const EdgeInsets.all(8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset('assets/logos.png', fit: BoxFit.cover),
                ),
              ),
              actions: [
                IconButton(
                  icon: Icon(
                    Icons.account_balance_wallet_outlined,
                    color: textPrimary,
                  ),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const WalletScreen()),
                  ),
                ),
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('notifications')
                      .where(
                        'receiverId',
                        isEqualTo: FirebaseAuth.instance.currentUser?.uid,
                      )
                      .where('isRead', isEqualTo: false)
                      .snapshots(),
                  builder: (context, snapshot) {
                    final unreadCount = snapshot.data?.docs.length ?? 0;
                    return Badge(
                      label: Text(unreadCount.toString()),
                      isLabelVisible: unreadCount > 0,
                      offset: const Offset(-4, 4),
                      child: IconButton(
                        icon: Icon(
                          Icons.notifications_none_rounded,
                          color: textPrimary,
                        ),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const NotificationsScreen(),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
      floatingActionButton: _index == 0
          ? FloatingActionButton(
              heroTag: 'chat_fab',
              child: const Icon(Icons.chat),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ChatListScreen()),
              ),
            )
          : null,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: _nav,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppTheme.primaryStart,
        unselectedItemColor: textSecondary,
        selectedLabelStyle: AppTheme.body(12, weight: FontWeight.w700),
        unselectedLabelStyle: AppTheme.body(12),
        items: [
          const BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
          const BottomNavigationBarItem(
            icon: Icon(Icons.qr_code_scanner),
            label: "Scan",
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.inventory),
            label: "My Assets",
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: "Profile",
          ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: [
          _mainMarketplaceBody(),
          const SizedBox(), // Placeholder for Scan (handled by nav)
          _loadedTabs.contains(2)
              ? const MyAssetsScreen()
              : const SizedBox.shrink(),
          _loadedTabs.contains(3)
              ? const ProfileScreen()
              : const SizedBox.shrink(),
        ],
      ),
    );
  }

  Widget _mainMarketplaceBody() {
    final isLand = _category == 'land';
    final headline = isLand
        ? 'Find Your\nBest Property '
        : 'Find Your\nBest Device ';
    final latestLabel = isLand ? 'Latest Property' : 'Latest Device';

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          // ── Headline ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
            child: Text(
              headline,
              style: AppTheme.heading(
                28,
                color: context.appTextPrimary,
              ).copyWith(height: 1.25),
            ),
          ),

          // ── Search bar ───────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 50,
                    decoration: BoxDecoration(
                      color: context.appSurface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: context.appBorder),
                    ),
                    child: TextField(
                      onChanged: (v) =>
                          setState(() => _search = v.trim().toLowerCase()),
                      decoration: InputDecoration(
                        hintText: 'Search your home...',
                        hintStyle: AppTheme.body(
                          14,
                          color: context.appTextMuted,
                        ),
                        prefixIcon: Icon(
                          Icons.search,
                          color: context.appTextMuted,
                          size: 20,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 15,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: _openFilters,
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryStart,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.tune_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Category toggle ──────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                _categoryChip('land', 'Property', Icons.home_work_rounded),
                const SizedBox(width: 10),
                _categoryChip(
                  'electronics',
                  'Electronics',
                  Icons.devices_rounded,
                ),
              ],
            ),
          ),

          // ── Land Mode Toggle (Sale/Rent) ──────────────────────────
          if (isLand) ...[
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _landModeToggle(),
            ),
          ],
          const SizedBox(height: 26),

          // ── Latest 5 — horizontal scroll ─────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  latestLabel,
                  style: AppTheme.heading(18, color: context.appTextPrimary),
                ),
                TextButton(
                  onPressed: () {},
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.accent,
                    padding: EdgeInsets.zero,
                  ),
                  child: Text(
                    'View All',
                    style: AppTheme.heading(13, color: AppTheme.accent),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 250,
            child: _LatestAssetsRow(
              category: _category,
              mode: isLand ? _landMode : null,
              currentUserId: FirebaseAuth.instance.currentUser?.uid ?? '',
            ),
          ),
          const SizedBox(height: 28),

          // ── Listing — full grid ──────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Icon(
                  Icons.list_alt_rounded,
                  size: 20,
                  color: Color(0xFF1A4F5C),
                ),
                const SizedBox(width: 8),
                Text(
                  'Listing',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: context.appTextPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AssetListView(
            category: _category,
            mode: isLand ? _landMode : null,
            search: _search,
            filters: _filters,
            shrinkWrap: true,
          ),
        ],
      ),
    );
  }

  Widget _landModeToggle() {
    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.appBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: _landModeBtn('sale', 'For Sale', Icons.sell_outlined),
          ),
          Expanded(child: _landModeBtn('rent', 'For Rent', Icons.key_outlined)),
        ],
      ),
    );
  }

  Widget _landModeBtn(String value, String label, IconData icon) {
    final selected = _landMode == value;
    final selectedColor = context.isDarkMode
        ? Colors.white
        : AppTheme.primaryStart;
    return GestureDetector(
      onTap: () => setState(() => _landMode = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: selected ? context.appSurfaceAlt : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: context.appShadow,
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? selectedColor : context.appTextSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: AppTheme.heading(
                  14,
                  color: selected ? selectedColor : context.appTextSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _categoryChip(String value, String label, IconData icon) {
    final selected = _category == value;
    return GestureDetector(
      onTap: () => setState(() {
        _category = value;
        _filters = {};
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primaryStart : context.appSurfaceMuted,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppTheme.primaryStart : context.appBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: selected ? Colors.white : context.appTextSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTheme.heading(
                13,
                color: selected ? Colors.white : context.appTextPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


// MY ASSETS SCREEN (Integrated)


class MyAssetsScreen extends StatefulWidget {
  const MyAssetsScreen({super.key});

  @override
  State<MyAssetsScreen> createState() => _MyAssetsScreenState();
}

class _MyAssetsScreenState extends State<MyAssetsScreen> {
  final BlockchainServiceEnhanced _blockchain = BlockchainServiceEnhanced();
  final ResaleService _resaleSvc = ResaleService();

  bool _loading = false;
  // FIX #3 — guard against double-tap opening two sheets simultaneously
  bool _listingInProgress = false;

  // ── Owned-asset state ────────────────────────────────────────
  List<QueryDocumentSnapshot> _ownedAssets = [];
  bool _assetsLoading = true;
  String? _assetsError;

  QuerySnapshot? _snap1;
  QuerySnapshot? _snap2;
  QuerySnapshot? _snap3;
  StreamSubscription? _sub1;
  StreamSubscription? _sub2;
  StreamSubscription? _sub3;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) _subscribeToAssets(uid);
  }

  void _subscribeToAssets(String uid) {
    // Query 1 — ownerId  (written by _finalizeOwnership on every transfer)
    _sub1 = db
        .collection('assets')
        .where('ownerId', isEqualTo: uid)
        .snapshots()
        .listen(
          (snap) {
            _snap1 = snap;
            _mergeAndSetState();
          },
          onError: (e) {
            if (mounted) {
              setState(() {
                _assetsError = e.toString();
                _assetsLoading = false;
              });
            }
          },
        );

    // Query 3 — fractional holdings (for bought land)
    _sub3 = db
        .collection('fractional_holdings')
        .where('userId', isEqualTo: uid)
        .where('fractionsOwned', isGreaterThan: 0)
        .snapshots()
        .listen((snap) async {
          _snap3 = snap;
          _mergeAndSetState();
        });
  }

  void _mergeAndSetState() async {
    final seen = <String>{};
    final merged = <QueryDocumentSnapshot>[];

    // Add primary owned assets
    for (final snap in [_snap1, _snap2]) {
      if (snap == null) continue;
      for (final doc in snap.docs) {
        if (seen.add(doc.id)) merged.add(doc);
      }
    }

    // Add fractional holdings
    if (_snap3 != null) {
      for (final holdingDoc in _snap3!.docs) {
        final h = holdingDoc.data() as Map<String, dynamic>;
        final assetId = h['assetId'] as String?;
        if (assetId != null && seen.add(assetId)) {
          // Fetch the master asset doc if we don't have it yet
          final assetDoc = await db.collection('assets').doc(assetId).get();
          if (assetDoc.exists) {
            merged.add(assetDoc as QueryDocumentSnapshot);
          }
        }
      }
    }

    if (mounted) {
      setState(() {
        _ownedAssets = merged;
        _assetsLoading = false;
        _assetsError = null;
      });
    }
  }

  @override
  void dispose() {
    _sub1?.cancel();
    _sub2?.cancel();
    _sub3?.cancel();
    super.dispose();
  }

  Future<void> _restoreAssets() async {
    setState(() => _loading = true);
    try {
      await _ensureWalletConnected();
      final addr = _blockchain.connectedAddress!;

      // Show scanning dialog
      _showScanningDialog();

      // In a real app, you'd scan events.
      // For this prototype, we'll ask the user to input a Token ID if they know it,
      // or we scan a range if possible.
      // But based on Problem 7, we'll just implement a manual "Restore by ID" for now.
      _showRestoreDialog();
    } catch (e) {
      _showSnack('Sync error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  void _showScanningDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Syncing with Blockchain'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Scanning for your digital goods…'),
          ],
        ),
      ),
    );
    Future.delayed(const Duration(seconds: 2), () => Navigator.pop(context));
  }

  void _showRestoreDialog() {
    final idCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore Asset'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter the Blockchain Token ID or Property ID to restore from chain.',
            ),
            TextField(
              controller: idCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Token/Property ID'),
            ),
            const SizedBox(height: 10),
            const Text(
              'Note: This will recreate the record if you deleted it from the app.',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final id = int.tryParse(idCtrl.text);
              if (id == null) return;
              Navigator.pop(ctx);

              setState(() => _loading = true);
              // Try restoring as electronics first, then land
              await _blockchain.restoreAssetFromBlockchain(
                type: 'electronics',
                tokenId: id,
                firestore: db,
              );
              await _blockchain.restoreAssetFromBlockchain(
                type: 'land',
                tokenId: id,
                firestore: db,
              );
              setState(() => _loading = false);

              _showSnack('Restoration process complete. Check your list.');
            },
            child: const Text('Restore'),
          ),
        ],
      ),
    );
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  Future<void> _ensureWalletConnected() async {
    if (!_blockchain.isConnected) await _blockchain.connectWallet(context);
  }

  Future<void> _claimRent(int propertyId) async {
    setState(() => _loading = true);
    try {
      await _ensureWalletConnected();
      final tx = await _blockchain.claimLandRent(propertyId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Transaction Sent! Waiting for confirmation...'),
          ),
        );
      }
      if (tx != null) {
        await _blockchain.waitForConfirmation(tx);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Rent Claimed Successfully!'),
              backgroundColor: Color(0xFF2A7F8F),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Resale helpers ────────────────────────────────────────────────────────

  // FIX #3 — double-tap guard + FIX #4 — removed redundant inner const Color
  Future<void> _listForResale(
    String assetId,
    Map<String, dynamic> asset,
  ) async {
    if (_listingInProgress) return;
    if (mounted) setState(() => _listingInProgress = true);
    try {
      final listed = await ResaleListingSheet.show(
        context,
        assetId: assetId,
        assetData: asset,
      );
      if (listed && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Asset listed for resale on marketplace!'),
            backgroundColor: AppTheme.primaryStart,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _listingInProgress = false);
    }
  }

  Future<void> _removeListing(String assetId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Listing'),
        content: const Text(
          'This will hide the asset from the marketplace. You can re-list it at any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Remove',
              style: AppTheme.button(14, color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _resaleSvc.removeListing(assetId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Listing removed. Asset hidden from marketplace.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _submitReview(int tokenId) async {
    final txtCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Submit Blockchain Review"),
        content: TextField(
          controller: txtCtrl,
          decoration: const InputDecoration(hintText: "Enter your review..."),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              if (txtCtrl.text.isEmpty) return;
              Navigator.pop(ctx);
              try {
                await _ensureWalletConnected();
                await _blockchain.submitElectronicsReview(
                  tokenId: tokenId,
                  reviewText: txtCtrl.text,
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Review Transaction Sent!"),
                      backgroundColor: AppTheme.primaryStart,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text("Error: $e")));
                }
              }
            },
            child: const Text("Submit"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Center(child: Text("Login required"));

    if (_assetsLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryStart),
      );
    }

    if (_assetsError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text(
                'Could not load assets:\n$_assetsError',
                textAlign: TextAlign.center,
                style: AppTheme.body(13, color: AppTheme.error),
              ),
            ],
          ),
        ),
      );
    }

    if (_ownedAssets.isEmpty) {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: context.appSurface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: context.appBorder),
            boxShadow: [
              BoxShadow(
                color: context.appShadow,
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: context.appSurfaceMuted,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.inventory_2_outlined,
                  size: 34,
                  color: AppTheme.primaryStart,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                "No assets owned yet",
                style: AppTheme.heading(16, color: context.appTextPrimary),
              ),
              const SizedBox(height: 6),
              Text(
                "Assets you buy or receive will appear here.",
                textAlign: TextAlign.center,
                style: AppTheme.body(13, color: context.appTextSecondary),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Go to Home tab to buy assets")),
                ),
                child: const Text("Browse Marketplace"),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: context.appScaffold,
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        itemCount: _ownedAssets.length,
        itemBuilder: (context, index) {
          final assetDoc = _ownedAssets[index];
          final asset = assetDoc.data() as Map<String, dynamic>;
          final assetId = assetDoc.id;

          final tokenId = asset['blockchainTokenId'] as int?;
          final title = (asset['title'] as String?) ?? 'Unknown Asset';
          final imgList = asset['images'] as List?;

          String? firstImg;
          if (imgList != null && imgList.isNotEmpty) {
            final raw = imgList.first;
            if (raw is String) firstImg = raw;
          }

          final resolvedCategory = (asset['category'] as String?) ?? 'land';
          final transferredAt = asset['transferredAt'] as Timestamp?;
          final warrantyActivatedAt = resolvedCategory == 'electronics'
              ? transferredAt
              : null;
          final fractionAmount = asset['fractionAmount'] as int?;
          final isSyncing = asset['isSyncingWithBlockchain'] == true;

          return _SafeCard(
            key: ValueKey(assetId),
            child: Container(
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: context.appSurface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: context.appBorder),
                boxShadow: [
                  BoxShadow(
                    color: context.appShadow,
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(24),
                  // FIX #2 — navigate to detail; resale is also accessible
                  // from _buildResaleRow below so the card tap stays as detail view
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AssetDetailScreen(assetId: assetId),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Header ───────────────────────────────────────
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: buildAssetImage(
                                firstImg,
                                width: 78,
                                height: 78,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: context.appTextPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    resolvedCategory == 'land'
                                        ? 'Fractional Land Ownership'
                                        : 'Electronic Device',
                                    style: TextStyle(
                                      color: context.appTextMuted,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: isSyncing
                                    ? Colors.orange.shade600
                                    : (asset['verified'] == true)
                                    ? Colors.green.shade600
                                    : tokenId != null
                                    ? AppTheme.primaryStart
                                    : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(18),
                                boxShadow: isSyncing || tokenId != null
                                    ? [
                                        BoxShadow(
                                          color:
                                              (isSyncing
                                                      ? Colors.orange.shade600
                                                      : AppTheme.primaryStart)
                                                  .withOpacity(0.18),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isSyncing)
                                    const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  else
                                    Icon(
                                      tokenId != null
                                          ? Icons.verified
                                          : Icons.schedule_rounded,
                                      size: 14,
                                      color: tokenId != null
                                          ? Colors.white
                                          : Colors.grey.shade700,
                                    ),
                                  const SizedBox(width: 6),
                                  Text(
                                    isSyncing
                                        ? 'Syncing...'
                                        : (asset['verified'] == true)
                                        ? 'Verified'
                                        : (tokenId != null
                                              ? 'Minted'
                                              : 'Pending'),
                                    style: TextStyle(
                                      color:
                                          (isSyncing ||
                                              tokenId != null ||
                                              asset['verified'] == true)
                                          ? Colors.white
                                          : Colors.grey.shade700,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // ── Category panel ────────────────────────────────
                      if (resolvedCategory == 'land') ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFFB0D8DE),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.pie_chart,
                                  size: 16,
                                  color: Color(0xFF1A4F5C),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  fractionAmount != null
                                      ? 'Fractions Owned: $fractionAmount'
                                      : 'Fractional Owner',
                                  style: const TextStyle(
                                    color: Color(0xFF1A4F5C),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (tokenId != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Flexible(
                                  child: FutureBuilder<BigInt>(
                                    future: _blockchain.getUnclaimedRent(
                                      user.uid,
                                      tokenId,
                                    ),
                                    builder: (c, s) {
                                      if (s.hasError) {
                                        return const Text(
                                          'Rent: —',
                                          style: TextStyle(fontSize: 12),
                                        );
                                      }
                                      final rent = s.data ?? BigInt.zero;
                                      return Text(
                                        'Unclaimed: ${_blockchain.weiToEther(rent)} MATIC',
                                        style: const TextStyle(
                                          color: Color(0xFF1A4F5C),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton.icon(
                                  icon: _loading
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.monetization_on,
                                          size: 15,
                                        ),
                                  label: const Text(
                                    'Claim Rent',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.accent,
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    minimumSize: const Size(0, 38),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  onPressed: _loading
                                      ? null
                                      : () => _claimRent(tokenId),
                                ),
                              ],
                            ),
                          ),
                      ] else ...[
                        if (warrantyActivatedAt != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.surface,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color(0xFFB0D8DE),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.verified_user,
                                    size: 16,
                                    color: Color(0xFF2A7F8F),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Warranty Activated',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF1A4F5C),
                                            fontSize: 12,
                                          ),
                                        ),
                                        Text(
                                          _formatDate(
                                            warrantyActivatedAt.toDate(),
                                          ),
                                          style: const TextStyle(
                                            color: Color(0xFF2A7F8F),
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],

                      // ── Resale status + actions ───────────────────────
                      // FIX #1 — pass tokenId so the row can apply the NFT guard
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 2, 4, 10),
                        child: _buildResaleRow(assetId, asset, tokenId),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Resale action row ─────────────────────────────────────────────────────
  // FIX #1 — added tokenId parameter; shows "Pending NFT" when not minted
  Widget _buildResaleRow(
    String assetId,
    Map<String, dynamic> asset,
    int? tokenId, // ← NEW parameter
  ) {
    final isListed = asset['isListedForResale'] == true;
    final resalePrice = asset['resalePrice'];
    // NFT must be minted before the asset can be listed for resale
    final canList = tokenId != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          // Status chip — only shown when actively listed
          if (isListed)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.orange[300]!),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.storefront, size: 13, color: Colors.orange[700]),
                  const SizedBox(width: 4),
                  Text(
                    resalePrice != null
                        ? 'Listed · PKR $resalePrice'
                        : 'Listed for Resale',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.orange[700],
                    ),
                  ),
                ],
              ),
            ),

          const Spacer(),

          // FIX #1 — three-branch decision tree
          if (!canList)
            // NFT not yet minted — disable resale quietly
            Tooltip(
              message: 'NFT must be minted before listing',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.hourglass_top_rounded,
                    size: 13,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Pending NFT',
                    style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                  ),
                ],
              ),
            )
          else if (isListed)
            TextButton.icon(
              onPressed: () => _removeListing(assetId),
              icon: const Icon(Icons.remove_circle_outline, size: 15),
              label: const Text(
                'Remove Listing',
                style: TextStyle(fontSize: 12),
              ),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red[700],
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
            )
          else
            TextButton.icon(
              // FIX #3 — disabled while another sheet is opening
              onPressed: _listingInProgress
                  ? null
                  : () => _listForResale(assetId, asset),
              icon: const Icon(Icons.sell_outlined, size: 15),
              label: const Text(
                'List for Resale',
                style: TextStyle(fontSize: 12),
              ),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.accent,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Error-boundary wrapper ─────────────────────────────────────────────────
class _SafeCard extends StatelessWidget {
  final Widget child;
  const _SafeCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    try {
      return child;
    } catch (e) {
      return Card(
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.broken_image, color: Colors.grey),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Could not display asset',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }
}


// LATEST ASSETS — horizontal scroll, last 5


class _LatestAssetsRow extends StatelessWidget {
  final String category;
  final String? mode;
  final String currentUserId;

  const _LatestAssetsRow({
    required this.category,
    this.mode,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context) {
    final query = db
        .collection('assets')
        .where('category', isEqualTo: category)
        .where('isMinted', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .limit(10);

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snap.data!.docs.where((doc) {
          final d = doc.data() as Map<String, dynamic>;
          final owner = (d['ownerId'] ?? d['ownerUid']) as String?;
          if (currentUserId.isNotEmpty && owner == currentUserId) return false;
          if (d['isStolenReported'] == true) return false;

          if (category == 'land' && mode != null) {
            if (mode == 'sale') return d['isListedForResale'] == true;
            if (mode == 'rent') return d['isForRent'] == true;
          }

          final wasPurchased = d['previousOwnerId'] != null;
          return wasPurchased
              ? d['isListedForResale'] == true
              : d['isListedForResale'] != false;
        }).toList();

        if (docs.isEmpty) {
          return Center(
            child: Text(
              'No ${category == 'land' ? 'properties' : 'devices'} yet',
              style: const TextStyle(color: Colors.grey),
            ),
          );
        }

        return ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final doc = docs[i];
            final data = doc.data() as Map<String, dynamic>;
            final imgList = data['images'] as List?;
            String? firstImg;
            if (imgList != null && imgList.isNotEmpty && imgList[0] is String) {
              firstImg = imgList[0] as String;
            }
            final city = (data['city'] ?? data['location'] ?? '').toString();
            final price = data['price'] ?? 0;
            final isResale =
                data['isListedForResale'] == true &&
                data['previousOwnerId'] != null;

            return GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AssetDetailScreen(assetId: doc.id),
                ),
              ),
              child: Container(
                width: 160,
                margin: const EdgeInsets.only(right: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.07),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Image
                    Expanded(
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(16),
                            ),
                            child: buildAssetImage(
                              firstImg,
                              width: double.infinity,
                              height: double.infinity,
                            ),
                          ),

                          Positioned(
                            top: 8,
                            right: 8,
                            child: FavoriteButton(assetId: doc.id, size: 14),
                          ),
                        ],
                      ),
                    ),
                    // Info
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            data['title'] ?? 'Asset',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          if (city.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                const Icon(
                                  Icons.location_on_outlined,
                                  size: 11,
                                  color: Colors.grey,
                                ),
                                const SizedBox(width: 2),
                                Expanded(
                                  child: Text(
                                    city,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 6),
                          Text(
                            'PKR $price',
                            style: const TextStyle(
                              color: Color(0xFF2A7F8F),
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ],
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
  }
}


// ASSET LIST VIEW (Search / Filter Logic)


class AssetListView extends StatelessWidget {
  final String category;
  final String? mode;
  final String search;
  final Map<String, dynamic> filters;
  final bool shrinkWrap;

  const AssetListView({
    super.key,
    required this.category,
    this.mode,
    required this.search,
    required this.filters,
    this.shrinkWrap = false,
  });

  Query _buildQuery() {
    Query q = db
        .collection("assets")
        .where("category", isEqualTo: category)
        .where("isMinted", isEqualTo: true);

    if (filters["minPrice"] != null) {
      q = q.where(
        "price",
        isGreaterThanOrEqualTo: (filters["minPrice"] as num).toInt(),
      );
    }
    if (filters["maxPrice"] != null) {
      q = q.where(
        "price",
        isLessThanOrEqualTo: (filters["maxPrice"] as num).toInt(),
      );
    }

    if (mode == 'rent') {
      return q.orderBy("createdAt", descending: true);
    }
    return q.orderBy("price").orderBy("createdAt", descending: true);
  }

  bool _matchesSearch(Map<String, dynamic> d) {
    if (search.isEmpty) return true;
    final title = (d["title"] ?? "").toString().toLowerCase();
    final brand = (d["brand"] ?? "").toString().toLowerCase();
    return title.contains(search) || brand.contains(search);
  }

  bool _matchesFilters(Map<String, dynamic> d) {
    if (filters["brand"] != null && filters["brand"].toString().isNotEmpty) {
      if ((d["brand"] ?? "").toString().toLowerCase() !=
          filters["brand"].toString().toLowerCase()) {
        return false;
      }
    }
    if (filters["city"] != null && filters["city"].toString().isNotEmpty) {
      if ((d["city"] ?? "").toString().toLowerCase() !=
          filters["city"].toString().toLowerCase()) {
        return false;
      }
    }
    if (category == "electronics") {
      if (filters["ram"] != null && filters["ram"].toString().isNotEmpty) {
        if ((d["ram"] ?? "").toString() != filters["ram"].toString()) {
          return false;
        }
      }
      if (filters["storage"] != null &&
          filters["storage"].toString().isNotEmpty) {
        if ((d["storage"] ?? "").toString() != filters["storage"].toString()) {
          return false;
        }
      }
      if (filters["condition"] != null &&
          filters["condition"].toString().isNotEmpty) {
        if ((d["condition"] ?? "").toString().toLowerCase() !=
            filters["condition"].toString().toLowerCase()) {
          return false;
        }
      }
    }
    if (category == "land") {
      if (filters["area"] != null && filters["area"].toString().isNotEmpty) {
        if ((d["area"] ?? "").toString() != filters["area"].toString()) {
          return false;
        }
      }
      if (filters["landType"] != null &&
          filters["landType"].toString().isNotEmpty) {
        if ((d["landType"] ?? "").toString().toLowerCase() !=
            filters["landType"].toString().toLowerCase()) {
          return false;
        }
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _buildQuery().snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text("Error: ${snap.error}"));
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snap.data!.docs;
        final filtered = docs
            .where(
              (e) =>
                  _matchesFilters(e.data() as Map<String, dynamic>) &&
                  _matchesSearch(e.data() as Map<String, dynamic>),
            )
            .toList();

        final currentUid = FirebaseAuth.instance.currentUser?.uid;
        final visible = filtered.where((doc) {
          final d = doc.data() as Map<String, dynamic>;
          final owner = (d['ownerId'] ?? d['ownerUid']) as String?;
          if (currentUid != null && owner == currentUid) return false;
          if (d['isStolenReported'] == true) return false;

          if (category == 'land' && mode != null) {
            if (mode == 'sale') return d['isListedForResale'] == true;
            if (mode == 'rent') return d['isForRent'] == true;
          }

          final isListedForResale = d['isListedForResale'];
          final wasPurchased = d['previousOwnerId'] != null;
          return wasPurchased
              ? isListedForResale == true
              : isListedForResale != false;
        }).toList();

        if (visible.isEmpty) {
          return const Center(child: Text("No assets found matching criteria"));
        }

        return GridView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shrinkWrap: shrinkWrap,
          physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
          itemCount: visible.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.72,
          ),
          itemBuilder: (_, i) {
            final doc = visible[i];
            return AssetGridCard(
              id: doc.id,
              data: doc.data() as Map<String, dynamic>,
              currentUserId: FirebaseAuth.instance.currentUser!.uid,
            );
          },
        );
      },
    );
  }
}


// FAVOURITE BUTTON


class FavoriteButton extends StatefulWidget {
  final String assetId;
  final double size;

  const FavoriteButton({super.key, required this.assetId, this.size = 16});

  @override
  State<FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends State<FavoriteButton> {
  bool _isFav = false;
  bool _loading = false;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';
  String get _docId => '${_uid}_${widget.assetId}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_uid.isEmpty) return;
    final doc = await db.collection('favorites').doc(_docId).get();
    if (mounted) setState(() => _isFav = doc.exists);
  }

  Future<void> _toggle() async {
    if (_uid.isEmpty || _loading) return;
    setState(() => _loading = true);
    try {
      final ref = db.collection('favorites').doc(_docId);
      if (_isFav) {
        await ref.delete();
      } else {
        await ref.set({
          'userId': _uid,
          'assetId': widget.assetId,
          'savedAt': FieldValue.serverTimestamp(),
        });
      }
      if (mounted) setState(() => _isFav = !_isFav);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final containerSize = widget.size + 12;
    return GestureDetector(
      onTap: _toggle,
      child: Container(
        width: containerSize,
        height: containerSize,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.85),
          shape: BoxShape.circle,
        ),
        child: _loading
            ? Padding(
                padding: const EdgeInsets.all(4),
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: Color(0xFF1A4F5C),
                ),
              )
            : Icon(
                _isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                size: widget.size,
                color: _isFav ? Colors.red : const Color(0xFF1A4F5C),
              ),
      ),
    );
  }
}


// ASSET GRID CARD


class AssetGridCard extends StatelessWidget {
  final String id;
  final Map<String, dynamic> data;
  final String currentUserId;

  const AssetGridCard({
    super.key,
    required this.id,
    required this.data,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context) {
    final imgList = data["images"] as List?;
    String? firstImg;
    if (imgList != null && imgList.isNotEmpty && imgList[0] is String) {
      firstImg = imgList[0] as String;
    }

    final city = (data['city'] ?? data['location'] ?? '').toString();
    final price = data['price'] ?? 0;
    final isResale = data['isListedForResale'] == true;
    final isStolen = data['isStolenReported'] == true;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => AssetDetailScreen(assetId: id)),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.07),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Image ────────────────────────────────────────────
            Expanded(
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                    child: buildAssetImage(
                      firstImg,
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  ),

                  if (isStolen)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.red[700]!.withOpacity(0.92),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(16),
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.report_problem_rounded,
                              color: Colors.white,
                              size: 11,
                            ),
                            SizedBox(width: 4),
                            Text(
                              '🚨 STOLEN — REPORTED',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: FavoriteButton(assetId: id, size: 16),
                  ),
                ],
              ),
            ),

            // ── Info ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    data['title'] ?? 'Asset',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  if (city.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 11,
                          color: Colors.grey,
                        ),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(
                            city,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          data['isForRent'] == true
                              ? "PKR ${(data['monthlyRent'] ?? 0).toStringAsFixed(0)} / mo"
                              : "PKR ${(data['price'] ?? 0).toStringAsFixed(0)}",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF2A7F8F),
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AssetDetailScreen(assetId: id),
                          ),
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryStart,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'View',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
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


// FILTER SHEET


class FilterSheet extends StatefulWidget {
  final String category;
  final ScrollController controller;
  final Map<String, dynamic> existing;

  const FilterSheet({
    super.key,
    required this.category,
    required this.controller,
    required this.existing,
  });

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  String _priceSort = 'low';
  String? _selectedCity;
  String? _selectedArea;

  static const _cities = ['Lahore', 'Karachi', 'Islamabad', 'Rawalpindi'];
  static const _areas = ['5 Marla', '10 Marla', '1 Kanal'];

  final _minCtrl = TextEditingController();
  final _maxCtrl = TextEditingController();

  static const _teal = Color(0xFF1A4F5C);
  static const _chipBg = Color(0xFFF5F7F8);
  static const _labelClr = AppTheme.textPrimary;

  @override
  void initState() {
    super.initState();
    _selectedCity = widget.existing['city'] as String?;
    _selectedArea = widget.existing['area'] as String?;
    _priceSort = (widget.existing['priceSort'] as String?) ?? 'low';
    _minCtrl.text = widget.existing['minPrice']?.toString() ?? '';
    _maxCtrl.text = widget.existing['maxPrice']?.toString() ?? '';
  }

  @override
  void dispose() {
    _minCtrl.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  void _apply() {
    Navigator.pop(context, {
      'priceSort': _priceSort,
      if (_selectedCity != null) 'city': _selectedCity,
      if (_selectedArea != null && widget.category == 'land')
        'area': _selectedArea,
      if (double.tryParse(_minCtrl.text) != null)
        'minPrice': double.parse(_minCtrl.text),
      if (double.tryParse(_maxCtrl.text) != null)
        'maxPrice': double.parse(_maxCtrl.text),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 6),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 12, 0),
            child: Row(
              children: [
                const Text(
                  'Filter',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: _labelClr,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          Expanded(
            child: ListView(
              controller: widget.controller,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              children: [
                _sectionLabel('Price'),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _toggleBtn('Low to high', 'low', flex: 1),
                    const SizedBox(width: 10),
                    _toggleBtn('High to low', 'high', flex: 1),
                  ],
                ),
                const SizedBox(height: 20),

                _sectionLabel('Price Range'),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _priceField(_minCtrl, 'Min (Rs)')),
                    const SizedBox(width: 12),
                    Expanded(child: _priceField(_maxCtrl, 'Max (Rs)')),
                  ],
                ),
                const SizedBox(height: 20),

                _sectionLabel('City'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _cities
                      .map(
                        (c) => _selectChip(
                          label: c,
                          selected: _selectedCity == c,
                          onTap: () => setState(
                            () => _selectedCity = _selectedCity == c ? null : c,
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 20),

                if (widget.category == 'land') ...[
                  _sectionLabel('Plot Area'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _areas
                        .map(
                          (a) => _selectChip(
                            label: a,
                            selected: _selectedArea == a,
                            onTap: () => setState(
                              () =>
                                  _selectedArea = _selectedArea == a ? null : a,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 20),
                ],

                const SizedBox(height: 12),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _apply,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _teal,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Apply Now',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w700,
      color: _labelClr,
    ),
  );

  Widget _toggleBtn(String label, String value, {int flex = 1}) {
    final sel = _priceSort == value;
    return Expanded(
      flex: flex,
      child: GestureDetector(
        onTap: () => setState(() => _priceSort = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: sel ? _teal : _chipBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: sel ? Colors.white : Colors.grey[600],
            ),
          ),
        ),
      ),
    );
  }

  Widget _selectChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? _teal : _chipBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? _teal : Colors.grey.shade200),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? Colors.white : Colors.grey[700],
          ),
        ),
      ),
    );
  }

  Widget _priceField(TextEditingController ctrl, String hint) {
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
        filled: true,
        fillColor: _chipBg,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _teal, width: 1.5),
        ),
      ),
    );
  }
}
