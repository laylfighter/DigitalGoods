import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:web3dart/web3dart.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:reown_appkit/reown_appkit.dart';
import 'package:url_launcher/url_launcher.dart';

import '../blockchain/wallet_service.dart';
import '../blockchain/contract_config.dart';
import '../blockchain/explorer_service.dart';
import '../screens/transaction_model.dart';
import '../services/push_notification_service.dart';
import '../theme.dart';
import 'package:cached_network_image/cached_network_image.dart';

// ─── Design Tokens ──────────────────────────────────────────
const kTeal = Color(0xFF2D7D7D);
const kTealDark = Color(0xFF1F5C5C);
const kTealLight = Color(0xFFE8F4F4);
const kTealAccent = Color(0xFF3AAFA9);

// ─── Card decoration helper ─────────────────────────────────
BoxDecoration _card(
  BuildContext context, {
  double radius = 20,
  Color? border,
}) => BoxDecoration(
  color: context.appSurface,
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(color: border ?? context.appBorder, width: 1),
  boxShadow: [
    BoxShadow(
      color: kTeal.withOpacity(0.06),
      blurRadius: 20,
      offset: const Offset(0, 4),
    ),
    BoxShadow(
      color: context.appShadow,
      blurRadius: 4,
      offset: const Offset(0, 1),
    ),
  ],
);

// ─── Polygon / POL asset icon widget ────────────────────────
class _PolygonIcon extends StatelessWidget {
  final double size;
  const _PolygonIcon({this.size = 36});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [kTealAccent, kTealDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(
          "⬡",
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.5,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// WIDGET
// ════════════════════════════════════════════════════════════
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen>
    with SingleTickerProviderStateMixin {
  // ─── Services ───────────────────────────────────────────
  final SimpleWalletService _walletService = SimpleWalletService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ExplorerService _explorer = ExplorerService();
  late Web3Client _client;

  // ─── State ──────────────────────────────────────────────
  String? _address;
  String? _userName;
  double _balance = 0.0;
  bool _connecting = false;
  bool _loading = false;
  bool _hideBalance = false;

  // Tracks hashes already notified so we don't re-fire on every refresh
  final Set<String> _seenTxHashes = {};
  final _notif = PushNotificationService();

  // All deduplicated transactions shown in Recent Activity
  List<TransactionModel> _transactions = [];

  // Owned assets from Firestore — source of truth for NFT count
  List<Map<String, dynamic>> _assets = [];

  // Asset lookup populated by _loadAllData — used in transaction tile builder
  Map<String, Map<String, dynamic>> _assetByName = {};

  // Secondary lookup by Firestore doc ID / assetId field
  // Allows resolving a raw ID in tx.title to the asset's display name
  Map<String, Map<String, dynamic>> _assetById = {};

  // Counts shown in the stats cards
  int _txCount = 0; // send/receive transactions
  int _nftCount = 0; // currently owned NFTs (from assets collection)

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  // ─── Polygon Amoy network ────────────────────────────────
  static final _amoyNetwork = ReownAppKitModalNetworkInfo(
    name: 'Polygon Amoy',
    chainId: '80002',
    currency: 'POL',
    rpcUrl: ContractConfig.rpcUrl,
    explorerUrl: 'https://amoy.polygonscan.com',
    isTestNetwork: true,
  );

  // ════════════════════════════════════════════════════════
  // LIFECYCLE
  // ════════════════════════════════════════════════════════
  @override
  void initState() {
    super.initState();
    _client = Web3Client(ContractConfig.rpcUrl, http.Client());
    _checkExistingConnection();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(
      begin: 0.7,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!_walletService.isInitialized) await _walletService.init(context);
      _walletService.appKitModal.addListener(_onWalletNotify);
      if (_walletService.appKitModal.isConnected &&
          _walletService.isConnected &&
          _walletService.address != null) {
        if (mounted) {
          setState(() => _address = _walletService.address);
          await _loadAllData();
        }
      }
    });
  }

  @override
  void dispose() {
    _walletService.appKitModal.removeListener(_onWalletNotify);
    _pulseCtrl.dispose();
    _client.dispose();
    super.dispose();
  }

  void _onWalletNotify() {
    if (!mounted) return;
    setState(() {
      if (!_walletService.appKitModal.isConnected ||
          !_walletService.isConnected) {
        _address = null;
        _balance = 0.0;
      } else {
        _address = _walletService.address;
      }
    });
  }

  // ════════════════════════════════════════════════════════
  // NETWORK
  // ════════════════════════════════════════════════════════
  Future<void> _enforceAmoyNetwork() async {
    try {
      await _walletService.appKitModal.selectChain(
        _amoyNetwork,
        switchChain: true,
      );
    } catch (e) {
      debugPrint("⚠️ Could not switch to Amoy: $e");
    }
  }

  // ════════════════════════════════════════════════════════
  // WALLET OPERATIONS
  // ════════════════════════════════════════════════════════
  Future<void> _checkExistingConnection() async {
    final user = _auth.currentUser;
    if (user == null) return;
    final doc = await _firestore.collection("users").doc(user.uid).get();
    if (!mounted) return;
    if (!doc.exists) return;
    final data = doc.data();
    _address = data?["walletAddress"];
    _userName = data?["name"];
    if (_address != null) await _loadAllData();
    if (mounted) setState(() {});
  }

  Future<void> _connect() async {
    if (_connecting) return;
    setState(() => _connecting = true);
    try {
      if (!_walletService.isInitialized) await _walletService.init(context);
      final address = await _walletService
          .connect(context)
          .timeout(const Duration(seconds: 25), onTimeout: () => null);
      await Future.delayed(const Duration(milliseconds: 500));
      if (!_walletService.appKitModal.isConnected ||
          !_walletService.isConnected ||
          address == null) {
        throw Exception("Wallet connection failed or cancelled");
      }
      await _enforceAmoyNetwork();
      final user = _auth.currentUser;
      if (user != null) {
        await _saveWalletToFirestore(user.uid, address);
        await _notif.notify(
          receiverUid: user.uid,
          title: '🔗 Wallet Connected',
          body:
              'Your wallet ${_shorten(address)} is now linked to your account.',
          type: NotificationType.general,
        );
      }
      if (!mounted) return;
      setState(() => _address = address);
      await _loadAllData();
    } catch (e) {
      debugPrint("Connect error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Wallet connection failed or timed out"),
            backgroundColor: kTealDark,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _disconnect() async {
    if (_loading || _connecting) return;
    setState(() => _loading = true);
    try {
      if (_walletService.isConnected) await _walletService.disconnect();
      setState(() {
        _address = null;
        _balance = 0.0;
        _transactions.clear();
        _assets.clear();
        _txCount = 0;
        _nftCount = 0;
        _seenTxHashes.clear();
      });
    } catch (e) {
      debugPrint("Disconnect error: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _switchAccount() async {
    if (_loading || _connecting) return;
    setState(() => _connecting = true);
    try {
      try {
        await _walletService.disconnect();
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      final newAddress = await _walletService.connect(context);
      if (newAddress == null) return;
      await _enforceAmoyNetwork();
      final user = _auth.currentUser;
      if (user != null) await _saveWalletToFirestore(user.uid, newAddress);
      if (!mounted) return;
      setState(() {
        _address = newAddress;
        _loading = true;
      });
      await _loadAllData();
    } catch (e) {
      debugPrint("Switch error: $e");
    } finally {
      if (mounted)
        setState(() {
          _connecting = false;
          _loading = false;
        });
    }
  }

  Future<void> _removeWallet() async {
    if (_loading || _connecting) return;
    setState(() => _loading = true);
    try {
      final user = _auth.currentUser;
      if (user == null) return;
      await _walletService.disconnect();
      await _firestore.collection("users").doc(user.uid).update({
        "walletAddress": FieldValue.delete(),
        "walletAddressLower": FieldValue.delete(),
      });

      await _notif.notify(
        receiverUid: user.uid,
        title: '🔓 Wallet Removed',
        body:
            'Your wallet has been unlinked from your account. You can reconnect anytime.',
        type: NotificationType.general,
      );

      setState(() {
        _address = null;
        _balance = 0.0;
        _transactions.clear();
        _assets.clear();
        _txCount = 0;
        _nftCount = 0;
        _seenTxHashes.clear();
      });
    } catch (e) {
      debugPrint("Remove error: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ════════════════════════════════════════════════════════
  // DATA LOADING
  // ════════════════════════════════════════════════════════
  bool get _isWalletReady =>
      _walletService.isConnected &&
      _walletService.appKitModal.isConnected &&
      _address != null;

  Future<void> _loadAllData() async {
    if (_address == null) return;
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      await _loadBalance();

      final results = await Future.wait([
        _explorer.getTransactions(_address!),
        _explorer.getNFTTransactions(_address!),
      ]);
      final normalTxs = results[0];
      final nftTxs = results[1];

      List<TransactionModel> firestoreTxs = [];
      List<Map<String, dynamic>> fetchedAssets = [];

      final user = _auth.currentUser;
      if (user != null) {
        // ── Firestore transactions ──────────────────────────
        final txSnap = await _firestore
            .collection("users")
            .doc(user.uid)
            .collection("transactions")
            .orderBy("time", descending: true)
            .limit(10)
            .get();
        firestoreTxs = txSnap.docs.map((doc) {
          final d = doc.data();
          // Normalise type: treat "purchase", "buy", "mint" as "nft"
          String txType = (d["type"] ?? "sent").toString().toLowerCase();
          if (txType == "purchase" || txType == "buy" || txType == "mint") {
            txType = "nft";
          }
          // Use assetName / assetTitle fields if present, falling back to title
          final title =
              (d["assetName"] ?? d["assetTitle"] ?? d["title"] ?? "Transaction")
                  .toString();
          return TransactionModel(
            type: txType,
            title: title,
            to: d["to"] ?? "",
            value: d["value"]?.toString() ?? "0",
            gas: d["gas"]?.toString() ?? "0",
            time: d["time"]?.toString() ?? "0",
            success: true,
            hash: d["hash"] ?? "",
          );
        }).toList();

        // ── Assets collection — source of truth for NFT ownership ──
        final assetSnap = await _firestore
            .collection("assets")
            .where("ownerId", isEqualTo: user.uid)
            .get();
        fetchedAssets = assetSnap.docs.map((d) {
          final data = d.data();
          data['_docId'] = d.id;
          return data;
        }).toList();
      }

      // ── Build asset lookups ────────────────────────────────
      final assetByName = <String, Map<String, dynamic>>{
        for (final a in fetchedAssets)
          if (a["name"] != null) (a["name"] as String).trim().toLowerCase(): a,
        // also index by "title" field if present (some docs use "title" not "name")
        for (final a in fetchedAssets)
          if (a["title"] != null)
            (a["title"] as String).trim().toLowerCase(): a,
      };

      final assetById = <String, Map<String, dynamic>>{
        for (final a in fetchedAssets) ...{
          if (a["assetId"] != null) (a["assetId"] as String).trim(): a,
          if (a["_docId"] != null) (a["_docId"] as String).trim(): a,
          if (a["blockchainTokenId"] != null)
            a["blockchainTokenId"].toString().trim(): a,
        },
      };

      // ── Build hash → asset map so NFT purchases on-chain get correct labels ──
      // Assets store their mint/purchase tx in "blockchainTx" field.
      final assetByTxHash = <String, Map<String, dynamic>>{
        for (final a in fetchedAssets)
          if (a["blockchainTx"] != null &&
              (a["blockchainTx"] as String).trim().isNotEmpty)
            (a["blockchainTx"] as String).trim().toLowerCase(): a,
      };

      // ── Merge + re-classify transactions ──────────────────
      // Combine all sources, then for any "sent" tx whose hash matches an asset
      // purchase, upgrade it to type="nft" with the correct asset name.
      final List<TransactionModel> mergedRaw = [
        ...normalTxs,
        ...nftTxs,
        ...firestoreTxs,
      ];

      final List<TransactionModel> reclassified = mergedRaw.map((tx) {
        if (tx.type == "sent" || tx.type == "contract") {
          final asset = assetByTxHash[tx.hash.trim().toLowerCase()];
          if (asset != null) {
            final assetName = (asset["name"] ?? asset["title"] ?? "")
                .toString()
                .trim();
            return TransactionModel(
              type: "nft",
              title: assetName.isNotEmpty ? assetName : tx.title,
              to: tx.to,
              value: tx.value,
              gas: tx.gas,
              time: tx.time,
              success: tx.success,
              hash: tx.hash,
            );
          }
        }
        return tx;
      }).toList();

      // ── Deduplicate by hash, newest first ──────────────────
      final seen = <String>{};
      final allTxs =
          reclassified
              .where((tx) => tx.hash.isNotEmpty && seen.add(tx.hash))
              .toList()
            ..sort((a, b) => int.parse(b.time).compareTo(int.parse(a.time)));

      final txCount = allTxs.length;

      _assetByName = assetByName;
      _assetById = assetById;

      if (!mounted) return;
      setState(() {
        _transactions = allTxs.take(15).toList();
        _assets = fetchedAssets;
        _txCount = txCount;
        _nftCount = fetchedAssets.isNotEmpty
            ? fetchedAssets.length
            : allTxs.where((tx) => tx.type == "nft").length;
      });
    } catch (e) {
      debugPrint("Load data error: $e");
      if (mounted)
        setState(() {
          _transactions = [];
          _assets = [];
          _txCount = 0;
          _nftCount = 0;
        });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadBalance() async {
    if (_address == null) return;
    try {
      final ethAddress = EthereumAddress.fromHex(_address!);
      final balanceWei = await _client.getBalance(ethAddress);
      if (!mounted) return;
      _balance = balanceWei.getValueInUnit(EtherUnit.ether);

      final user = _auth.currentUser;
      if (user != null && _balance < 0.05 && _balance >= 0) {
        final balKey = 'low_balance_alerted';
        if (!_seenTxHashes.contains(balKey)) {
          _seenTxHashes.add(balKey);
          await _notif.notifyLowBalance(
            userUid: user.uid,
            currentBalance: _balance.toStringAsFixed(4),
            currency: 'POL',
          );
        }
      }
    } catch (e) {
      debugPrint("Balance error: $e");
    }
  }

  // ════════════════════════════════════════════════════════
  // FIRESTORE HELPERS
  // ════════════════════════════════════════════════════════
  Future<void> _saveWalletToFirestore(String uid, String newAddress) async {
    await _walletService.linkWalletToUser(
      uid: uid,
      walletAddress: newAddress,
      conflictMessage:
          "This MetaMask wallet is already linked to another account.",
    );
  }

  // ════════════════════════════════════════════════════════
  // UI HELPERS
  // ════════════════════════════════════════════════════════

  /// POL → PKR conversion rate (approximate; update periodically)
  double _convertPolToPkr(double pol) => pol * 280.0;

  String _shorten(String addr) {
    if (addr.isEmpty) return "N/A";
    if (addr.length <= 10) return addr;
    return "${addr.substring(0, 6)}...${addr.substring(addr.length - 2)}";
  }

  String _formatTime(String rawTime) {
    final ts = int.tryParse(rawTime) ?? 0;
    if (ts == 0) return "Unknown";
    final ms = ts > 9999999999 ? ts : ts * 1000;
    final time = DateTime.fromMillisecondsSinceEpoch(ms);
    final diff = DateTime.now().difference(time);
    if (diff.isNegative || diff.inSeconds < 60) return "Just now";
    if (diff.inMinutes < 60) return "${diff.inMinutes}m ago";
    if (diff.inHours < 24) return "${diff.inHours}h ago";
    if (diff.inDays < 7) return "${diff.inDays}d ago";
    if (diff.inDays < 30) return "${(diff.inDays / 7).floor()}w ago";
    if (diff.inDays < 365) return "${(diff.inDays / 30).floor()}mo ago";
    return "${(diff.inDays / 365).floor()}y ago";
  }

  // ── FIX: resolve image URL from asset map, covering all common field names ──
  String? _resolveImageUrl(Map<String, dynamic>? asset) {
    if (asset == null) return null;
    final candidates = [
      asset["imageUrl"],
      asset["image"],
      asset["thumbnailUrl"],
      asset["photoUrl"],
      asset["photo"],
      asset["assetImage"],
      asset["fileUrl"],
      asset["url"],
      asset["coverImage"],
      asset["coverUrl"],
      asset["nftImage"],
      asset["mediaUrl"],
      asset["assetUrl"],
      asset["imgUrl"],
      asset["thumbnail"],
    ];
    for (final c in candidates) {
      if (c is String && c.trim().isNotEmpty) return c.trim();
    }
    return null;
  }

  void _confirmAction({
    required String title,
    required Future<void> Function() onConfirm,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.appSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          title,
          style: TextStyle(
            color: context.appTextPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          "Are you sure you want to continue?",
          style: TextStyle(color: context.appTextSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              "Cancel",
              style: TextStyle(color: context.appTextSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await onConfirm();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: kTeal,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text("Confirm"),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appScaffold,
      appBar: _buildAppBar(),
      body: _loading
          ? _buildSkeleton()
          : !_isWalletReady
          ? _buildConnectView()
          : _buildWalletView(),
    );
  }

  // ─── AppBar ──────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: context.appSurface,
      elevation: 0,
      centerTitle: true,
      systemOverlayStyle: context.isDarkMode
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: const BoxDecoration(
              color: kTeal,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            "Wallet",
            style: TextStyle(
              color: context.appTextPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 18,
              letterSpacing: -0.4,
            ),
          ),
        ],
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(color: context.appBorder, height: 1),
      ),
      actions: [
        if (_address != null)
          IconButton(
            icon: Icon(Icons.more_vert, color: context.appTextPrimary),
            onPressed: _showWalletOptions,
          ),
      ],
    );
  }

  // ─── Loading Skeleton ────────────────────────────────────
  Widget _buildSkeleton() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _shimmerBox(height: 200, radius: 24),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _shimmerBox(height: 90)),
            const SizedBox(width: 12),
            Expanded(child: _shimmerBox(height: 90)),
          ],
        ),
        const SizedBox(height: 16),
        _shimmerBox(height: 22, radius: 6),
        const SizedBox(height: 12),
        _shimmerBox(height: 60),
        const SizedBox(height: 8),
        _shimmerBox(height: 60),
        const SizedBox(height: 8),
        _shimmerBox(height: 60),
      ],
    );
  }

  Widget _shimmerBox({double height = 80, double radius = 16}) {
    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (_, __) => Opacity(
        opacity: _pulseAnim.value,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: context.appSurfaceMuted,
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      ),
    );
  }

  // ─── Connect View ────────────────────────────────────────
  Widget _buildConnectView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(color: kTeal, shape: BoxShape.circle),
              child: const Icon(
                Icons.account_balance_wallet_outlined,
                size: 48,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 28),
            Text(
              "Connect your wallet",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: context.appTextPrimary,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              "Link a Web3 wallet to view your balance, NFTs and transactions.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.appTextSecondary,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 36),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: (_connecting || _loading) ? null : _connect,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kTeal,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: kTeal.withOpacity(0.4),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: _connecting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.account_balance_wallet, size: 20),
                label: Text(
                  _connecting ? "Opening wallet…" : "Connect Wallet",
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Wallet View ─────────────────────────────────────────
  Widget _buildWalletView() {
    return RefreshIndicator(
      color: kTeal,
      onRefresh: _loadAllData,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        children: [
          _buildBalanceCard(),
          const SizedBox(height: 16),
          _buildStatsRow(),
          const SizedBox(height: 24),
          _buildTransactions(),
        ],
      ),
    );
  }

  // ─── Balance Card ────────────────────────────────────────
  Widget _buildBalanceCard() {
    final pkr = _convertPolToPkr(_balance);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [kTealAccent, kTealDark],
        ),
        boxShadow: [
          BoxShadow(
            color: kTeal.withOpacity(0.40),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── User row ──
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.22),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _userName ?? "User",
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: _address ?? ""));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text("Address copied"),
                            backgroundColor: Colors.black87,
                            behavior: SnackBarBehavior.floating,
                            duration: const Duration(seconds: 1),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        );
                      },
                      child: Row(
                        children: [
                          Text(
                            _shorten(_address ?? ""),
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.82),
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.copy,
                            size: 12,
                            color: Colors.white.withOpacity(0.7),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Verified badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.4),
                    width: 1,
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.verified, size: 12, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      "Verified",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 28),

          const Text(
            "TOTAL BALANCE",
            style: TextStyle(
              color: Colors.white60,
              fontSize: 11,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),

          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  _hideBalance
                      ? "••••••• POL"
                      : "${_balance.toStringAsFixed(4)} POL",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.0,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => setState(() => _hideBalance = !_hideBalance),
                child: Icon(
                  _hideBalance ? Icons.visibility_off : Icons.visibility,
                  color: Colors.white70,
                  size: 20,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            "≈ ₨${pkr.toStringAsFixed(2)} PKR",
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),

          const SizedBox(height: 20),

          // ── Asset pill with Polygon logo ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Network chip
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, size: 7, color: Colors.white),
                    SizedBox(width: 6),
                    Text(
                      "Polygon Amoy",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              // POL asset mini-pill
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: kTeal,
                      ),
                      child: const Center(
                        child: Text(
                          "⬡",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      "POL",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              // Refresh button
              GestureDetector(
                onTap: _loadAllData,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.refresh_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Stats Row ───────────────────────────────────────────
  Widget _buildStatsRow() {
    // IntrinsicHeight forces both cards to match the height of the taller one
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _buildStatCard(
              label: "Transactions",
              value: "$_txCount",
              icon: Icons.swap_horiz_rounded,
              iconColor: Colors.white,
              iconBg: kTeal,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              label: "NFTs",
              value: "$_nftCount",
              icon: Icons.image_rounded,
              iconColor: Colors.white,
              iconBg: kTeal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required String label,
    required String value,
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.appBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: kTeal.withOpacity(0.07),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: context.appShadow,
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: context.appTextPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.appTextSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Transaction List ────────────────────────────────────
  Widget _buildTransactions() {
    if (_transactions.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Recent Activity",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: context.appTextPrimary,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(32),
            decoration: _card(context),
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: context.appSurfaceMuted,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.receipt_long_outlined,
                    color: kTeal,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  "No transactions yet",
                  style: TextStyle(
                    color: context.appTextSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: kTeal,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  "Recent Activity",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: context.appTextPrimary,
                  ),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: kTeal,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                "${_transactions.length} items",
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: _card(context),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _transactions.length,
            separatorBuilder: (_, __) =>
                Divider(height: 1, color: context.appBorder, indent: 72),
            itemBuilder: (_, i) => _buildTxTile(_transactions[i]),
          ),
        ),
      ],
    );
  }

  Widget _buildTxTile(TransactionModel tx) {
    // ── Safety re-classification: if type=="sent" but title looks like an
    //    asset name (not a generic label), treat it as an NFT purchase.
    final bool titleLooksLikeAsset =
        tx.title.isNotEmpty &&
        tx.title != "Transaction" &&
        tx.title != "Sent POL" &&
        tx.title != "Received POL" &&
        tx.title != "Contract Interaction" &&
        !tx.title.startsWith("0x"); // raw address → not an asset name

    final bool isSent = tx.type == "sent" && !titleLooksLikeAsset;
    final bool isNft =
        tx.type == "nft" || (tx.type == "sent" && titleLooksLikeAsset);
    final bool isContract = tx.type == "contract" && !titleLooksLikeAsset;

    // ── Colour + icon per type ─────────────────────────────
    final Color iconColor = isNft
        ? kTealAccent
        : isContract
        ? kTeal
        : isSent
        ? Colors.redAccent
        : kTealAccent;

    final IconData iconData = isNft
        ? Icons.image_rounded
        : isContract
        ? Icons.code
        : isSent
        ? Icons.arrow_upward_rounded
        : Icons.arrow_downward_rounded;

    // ── Asset name: prefer tx.title when it is meaningful ──
    final bool hasMeaningfulTitle =
        tx.title.isNotEmpty &&
        tx.title != "Transaction" &&
        tx.title != "Contract Interaction";

    // If tx.title looks like a raw asset ID, resolve it to the human-readable name
    String resolvedNftTitle = tx.title;
    if (isNft && hasMeaningfulTitle) {
      final byId = _assetById[tx.title.trim()];
      if (byId != null) {
        resolvedNftTitle = (byId["name"] as String?)?.trim().isNotEmpty == true
            ? byId["name"] as String
            : tx.title;
      }
    }

    final String mainLabel = isNft
        ? (hasMeaningfulTitle ? resolvedNftTitle : "NFT Transfer")
        : isContract
        ? (hasMeaningfulTitle ? tx.title : "Contract Interaction")
        : isSent
        ? "Sent POL"
        : "Received POL";

    // ── Subtitle: asset category or address ───────────────
    String subtitle;
    if (isNft) {
      // ── FIX: use trim() on lookup key ──
      final asset =
          _assetByName[mainLabel.trim().toLowerCase()] ??
          _assetById[tx.title.trim()] ??
          _assetById[resolvedNftTitle.trim()];
      final category = asset?["category"] as String?;
      subtitle = category?.isNotEmpty == true ? category! : "NFT Asset";
    } else if (isContract) {
      subtitle = _shorten(tx.to);
    } else {
      subtitle = _shorten(tx.to);
    }

    // ── Amount / price display ─────────────────────────────
    final double? polValue = double.tryParse(tx.value);
    final bool hasPrice = polValue != null && polValue > 0;

    Widget amountWidget;
    if (isNft || isContract) {
      if (hasPrice) {
        amountWidget = Text(
          "${polValue!.toStringAsFixed(4)} POL",
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: iconColor,
          ),
        );
      } else {
        amountWidget = Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            isNft ? "NFT" : "Contract",
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: iconColor,
            ),
          ),
        );
      }
    } else {
      amountWidget = Text(
        "${isSent ? '−' : '+'}${polValue?.toStringAsFixed(4) ?? tx.value} POL",
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 13,
          color: iconColor,
        ),
      );
    }

    return InkWell(
      onTap: () async {
        final url = Uri.parse("https://amoy.polygonscan.com/tx/${tx.hash}");
        if (await canLaunchUrl(url)) {
          launchUrl(url, mode: LaunchMode.externalApplication);
        }
      },
      borderRadius: BorderRadius.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // ── FIX: Icon / Asset Image with expanded field name resolution ──
            Builder(
              builder: (_) {
                if (isNft) {
                  // ── FIX: trim() the lookup key and also try resolvedNftTitle ──
                  final asset =
                      _assetByName[mainLabel.trim().toLowerCase()] ??
                      _assetById[tx.title.trim()] ??
                      _assetById[resolvedNftTitle.trim()];

                  // ── FIX: use _resolveImageUrl() which checks 15+ field names ──
                  final imgUrl = _resolveImageUrl(asset);

                  if (imgUrl != null) {
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(13),
                      child: CachedNetworkImage(
                        imageUrl: imgUrl,
                        width: 46,
                        height: 46,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: iconColor.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: const Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: kTeal,
                              ),
                            ),
                          ),
                        ),
                        errorWidget: (_, url, err) {
                          debugPrint("❌ Image load failed for $url: $err");
                          return Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: iconColor.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Icon(
                              Icons.broken_image_rounded,
                              color: iconColor,
                              size: 20,
                            ),
                          );
                        },
                      ),
                    );
                  }
                }

                // Fallback: coloured icon box
                return Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: isNft || isContract
                      ? Icon(iconData, color: iconColor, size: 22)
                      : Stack(
                          alignment: Alignment.center,
                          children: [
                            const _PolygonIcon(size: 28),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  color: iconColor,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 1.5,
                                  ),
                                ),
                                child: Icon(
                                  iconData,
                                  color: Colors.white,
                                  size: 9,
                                ),
                              ),
                            ),
                          ],
                        ),
                );
              },
            ),
            const SizedBox(width: 12),

            // ── Labels (asset name + subtitle) ────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          mainLabel,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: context.appTextPrimary,
                          ),
                        ),
                      ),
                      if (!isNft && !isContract) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: kTealLight,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            "POL",
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: kTeal,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.appTextSecondary,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 8),

            // ── Amount + time ──────────────────────────────
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                amountWidget,
                const SizedBox(height: 3),
                Text(
                  _formatTime(tx.time),
                  style: TextStyle(
                    fontSize: 11,
                    color: context.appTextSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      Icons.open_in_new,
                      size: 10,
                      color: context.appTextSecondary,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      "Explorer",
                      style: TextStyle(
                        fontSize: 10,
                        color: context.appTextSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── Wallet Options Bottom Sheet ─────────────────────────
  void _showWalletOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.appSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Address row
              Container(
                padding: const EdgeInsets.all(16),
                decoration: _card(context, radius: 16),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: kTeal,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.account_balance_wallet,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _shorten(_address!),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: context.appTextPrimary,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: kTeal,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.verified, size: 12, color: Colors.white),
                          SizedBox(width: 4),
                          Text(
                            "Verified",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              _buildActionButton(
                text: "Switch Account",
                icon: Icons.swap_horiz_rounded,
                color: kTealAccent,
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmAction(
                    title: "Switch Account?",
                    onConfirm: _switchAccount,
                  );
                },
              ),
              const SizedBox(height: 10),
              _buildActionButton(
                text: "Disconnect Wallet",
                icon: Icons.link_off_rounded,
                color: kTealDark,
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmAction(
                    title: "Disconnect Wallet?",
                    onConfirm: _disconnect,
                  );
                },
              ),
              const SizedBox(height: 10),
              _buildActionButton(
                text: "Remove Wallet",
                icon: Icons.delete_outline_rounded,
                color: kTealDark,
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmAction(
                    title: "Remove Wallet permanently?",
                    onConfirm: _removeWallet,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required String text,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withOpacity(0.08),
          foregroundColor: color,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: color.withOpacity(0.22)),
          ),
        ),
        icon: Icon(icon, size: 18),
        label: Text(
          text,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
    );
  }
}
