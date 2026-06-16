// lib/screens/asset_detail_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:uuid/uuid.dart';
import 'shared_screens.dart';
import 'reviews_list.dart';
import 'qr_generator_screen.dart';
import 'land_fractions_screen.dart';
import 'transfer_screen.dart';
import 'transfer_history_screen.dart';
import '../blockchain/blockchain_service.dart';
import '../blockchain/ipfs_service.dart';
import '../services/resale_service.dart';
import '../theme.dart';
import '../widgets/rent_actions.dart';
import 'rent_distribution_screen.dart';
final db = FirebaseFirestore.instance;
final auth = FirebaseAuth.instance;

Future<String?> _existingTransactionId(String transactionId) async {
  final trimmedId = transactionId.trim();
  if (trimmedId.isEmpty) return null;

  final txSnap = await db.collection('transactions').doc(trimmedId).get();
  if (!txSnap.exists) {
    debugPrint(
      'Skipping missing transaction update for fraction request: $trimmedId',
    );
    return null;
  }
  return trimmedId;
}

// ─────────────────────────────────────────────────────────────────────────────
// FRACTION REQUESTS PANEL
// ─────────────────────────────────────────────────────────────────────────────
class FractionRequestsPanel extends StatelessWidget {
  final String assetId;
  final int blockchainPropertyId;

  const FractionRequestsPanel({
    super.key,
    required this.assetId,
    required this.blockchainPropertyId,
  });

  Future<void> _updateRequest(
      BuildContext context,
      String requestId,
      String transactionId,
      String newStatus,
      ) async {
    final existingTransactionId = await _existingTransactionId(transactionId);
    final batch = db.batch();
    batch.update(db.collection('fraction_requests').doc(requestId), {
      'status': newStatus,
      'respondedAt': FieldValue.serverTimestamp(),
    });
    if (existingTransactionId != null) {
      batch.update(db.collection('transactions').doc(existingTransactionId), {
        'status': newStatus == 'approved' ? 'approved' : 'rejected',
      });
    }
    await batch.commit();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newStatus == 'approved'
                ? '✅ Request approved. You can now execute the blockchain transfer.'
                : '❌ Request rejected.',
          ),
          backgroundColor: newStatus == 'approved'
              ? AppTheme.accent
              : AppTheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db
          .collection('fraction_requests')
          .where('assetId', isEqualTo: assetId)
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }
        final requests = snap.data!.docs;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.inbox, color: AppTheme.primaryStart, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Pending Fraction Requests (${requests.length})',
                  style: AppTheme.heading(15, color: AppTheme.primaryStart),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...requests.map((doc) {
              final r = doc.data();
              final fractionsRequested = r['fractionsRequested'] ?? 0;
              final totalCostWei = r['totalCost'] ?? '0';
              final buyerUid = r['buyerUid'] ?? '';
              final transactionId = r['transactionId'] ?? '';

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: AppTheme.primaryStart.withOpacity(0.2)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FutureBuilder<DocumentSnapshot>(
                        future: db.collection('users').doc(buyerUid).get(),
                        builder: (ctx, userSnap) {
                          final name = userSnap.hasData && userSnap.data!.exists
                              ? (userSnap.data!.data()
                          as Map<String, dynamic>)['name'] ??
                              'Buyer'
                              : _shorten(buyerUid);
                          return Row(
                            children: [
                              const Icon(
                                Icons.person_outline,
                                size: 14,
                                color: AppTheme.textMid,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Fractions: $fractionsRequested',
                            style: AppTheme.body(13),
                          ),
                          Text(
                            'Est. total: ${_weiDisplay(totalCostWei)} MATIC',
                            style: AppTheme.heading(13, color: AppTheme.primaryStart),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _updateRequest(
                                context,
                                doc.id,
                                transactionId,
                                'rejected',
                              ),
                              icon: const Icon(
                                Icons.close,
                                size: 16,
                                color: AppTheme.error,
                              ),
                              label: const Text('Reject'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.error,
                                side: const BorderSide(color: AppTheme.error),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _updateRequest(
                                context,
                                doc.id,
                                transactionId,
                                'approved',
                              ),
                              icon: const Icon(Icons.check, size: 16),
                              label: const Text('Approve'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.accent,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }

  String _weiDisplay(String weiStr) {
    try {
      final wei = BigInt.tryParse(weiStr) ?? BigInt.zero;
      final ether = wei / BigInt.from(10).pow(18);
      return ether.toStringAsFixed(4);
    } catch (_) {
      return '—';
    }
  }

  String _shorten(String id) {
    if (id.length <= 10) return id;
    return '${id.substring(0, 6)}...${id.substring(id.length - 4)}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ASSET DETAIL SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class AssetDetailScreen extends StatefulWidget {
  final String assetId;
  const AssetDetailScreen({super.key, required this.assetId});

  @override
  State<AssetDetailScreen> createState() => _AssetDetailScreenState();
}

class _AssetDetailScreenState extends State<AssetDetailScreen> {
  final _blockchainService = BlockchainServiceEnhanced();
  final _ipfsService = IPFSService();
  final _resaleSvc = ResaleService();
  final _uuid = const Uuid();

  // Guard against double-tap opening two resale sheets simultaneously
  bool _listingInProgress = false;

  late Future<Map<String, dynamic>> _loadFuture;
  Map<String, dynamic>? _blockchainData;
  Map<String, dynamic>? _ipfsData;
  bool _isDataHealthy = true;

  Future<Map<String, dynamic>> _load() async {
    final assetSnap = await db.collection('assets').doc(widget.assetId).get();
    final role = await fetchCurrentRole();

    String ownerName = 'Unknown';
    if (assetSnap.exists) {
      final ownerId =
          assetSnap.data()?['ownerId'] ?? assetSnap.data()?['ownerUid'];
      if (ownerId != null) {
        try {
          final ownerSnap = await db.collection('users').doc(ownerId).get();
          if (ownerSnap.exists) {
            ownerName =
                ownerSnap.data()?['name'] ??
                    ownerSnap.data()?['email'] ??
                    'Unknown';
          }
        } catch (_) {}
      }

      final blockchainId = assetSnap.data()?['blockchainTokenId'] as int?;
      if (blockchainId != null) {
        await _loadBlockchainData(assetSnap.data()!['category'], blockchainId);
      }
    }

    Map<String, dynamic>? activeTx;
    if (role.toLowerCase().contains('supplier') && auth.currentUser != null) {
      final txQuery = await db
          .collection('transactions')
          .where('assetId', isEqualTo: widget.assetId)
          .where('sellerUid', isEqualTo: auth.currentUser!.uid)
          .where('status', whereIn: ['approved', 'accepted'])
          .limit(1)
          .get();

      if (txQuery.docs.isNotEmpty) {
        activeTx = txQuery.docs.first.data();
        activeTx['transactionId'] = txQuery.docs.first.id;
      }
    }

    return {
      'assetSnap': assetSnap,
      'role': role,
      'ownerName': ownerName,
      'activeTx': activeTx,
    };
  }

  Future<void> _loadBlockchainData(String category, int tokenId) async {
    try {
      await _blockchainService.init();
      if (category == 'electronics') {
        _blockchainData = await _blockchainService.getDevice(tokenId);
      } else if (category == 'land') {
        _blockchainData = await _blockchainService.getLandProperty(tokenId);
      }

      if (_blockchainData != null) {
        // SECURITY & SELF-HEALING: Verify Firestore vs Blockchain
        _isDataHealthy = await _blockchainService.verifyAndHealAsset(
          type: category,
          blockchainId: tokenId,
          firestoreDocId: widget.assetId,
          firestore: db,
        );

        final ipfsHash =
            _blockchainData!['ipfsMetadata'] ?? _blockchainData!['tokenURI'];
        if (ipfsHash != null && ipfsHash.isNotEmpty) {
          final hash = _ipfsService.extractHashFromUrl(ipfsHash);
          if (hash != null) {
            _ipfsData = await _ipfsService.retrieveJSON(hash);
          }
        }
      }
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error loading blockchain data: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _loadFuture = _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Asset Detail', style: AppTheme.heading(20, color: Colors.white)),
        flexibleSpace: Container(decoration: const BoxDecoration(gradient: AppTheme.primaryGradient)),
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_2_rounded, color: Colors.white),
            onPressed: () => _showQRCode(context),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _loadFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: AppTheme.error),
                  const SizedBox(height: 16),
                  Text('Error: ${snapshot.error}', style: AppTheme.body(14)),
                ],
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final assetSnap = snapshot.data!['assetSnap'] as DocumentSnapshot;
          final role = snapshot.data!['role'] as String;
          final ownerName = snapshot.data!['ownerName'] as String;
          final activeTx = snapshot.data!['activeTx'] as Map<String, dynamic>?;

          if (!assetSnap.exists) {
            return const Center(child: Text('Asset not found'));
          }

          final data = assetSnap.data() as Map<String, dynamic>;

          db
              .collection('assets')
              .doc(widget.assetId)
              .update({'views': FieldValue.increment(1)})
              .catchError((_) {});

          return _buildAssetDetails(context, data, role, ownerName, activeTx);
        },
      ),
    );
  }

  Widget _buildAssetDetails(
      BuildContext context,
      Map<String, dynamic> data,
      String role,
      String ownerName,
      Map<String, dynamic>? activeTx,
      ) {
    final images = (data['images'] as List?)?.cast<String>() ?? [];
    final hasBlockchainId = data['blockchainTokenId'] != null;
    final isLand = data['category'] == 'land';
    final isSupplier = role.toLowerCase().contains('supplier');

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Image carousel ───────────────────────────────────────────────
          if (images.isNotEmpty)
            CarouselSlider(
              options: CarouselOptions(
                height: 250,
                autoPlay: true,
                enlargeCenterPage: true,
              ),
              items: images.map((img) {
                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  child: buildAssetImage(
                    img,
                    width: double.infinity,
                    height: 250,
                    fit: BoxFit.cover,
                  ),
                );
              }).toList(),
            )
          else
            Container(
              height: 250,
              color: AppTheme.primaryStart.withOpacity(0.05),
              child: Center(
                child: Icon(Icons.image, size: 80, color: AppTheme.textMid),
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Title + NFT badge ──────────────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        data['title'] ?? 'Untitled',
                        style: AppTheme.heading(24, color: AppTheme.textPrimary),
                      ),
                    ),
                    if (hasBlockchainId)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.accent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.verified, color: Colors.white, size: 16),
                            SizedBox(width: 4),
                            Text(
                              'NFT',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 12),
                Text(
                  data['isForRent'] == true
                      ? 'PKR ${data['monthlyRent'] ?? data['price']} / Month'
                      : 'PKR ${data['price']}',
                  style: AppTheme.heading(28, color: AppTheme.primaryStart),
                ),
                // 🪙 Live Conversion Hint
                Text(
                  '≈ ${((data['isForRent'] == true ? (data['monthlyRent'] ?? data['price']) : data['price']) ?? 0) / 200.0} MATIC',
                  style: AppTheme.body(14, color: AppTheme.textMid),
                ),
                if (data['isForRent'] == true && data['securityDeposit'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Security Deposit: PKR ${data['securityDeposit']}',
                      style: AppTheme.body(14, color: AppTheme.textMid),
                    ),
                  ),

                const SizedBox(height: 16),

                // ── Description ───────────────────────────────────────────
                if (data['description'] != null) ...[
                  Text(
                    'Description',
                    style: AppTheme.heading(18),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    data['description'],
                    style: AppTheme.body(15, color: AppTheme.textPrimary),
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Blockchain section ────────────────────────────────────
                if (hasBlockchainId && _blockchainData != null) ...[
                  _buildBlockchainSection(data['category'] ?? '', data),
                  const SizedBox(height: 16),
                ],

                // ── Details card ──────────────────────────────────────────
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Details',
                          style: AppTheme.heading(18),
                        ),
                        const SizedBox(height: 12),
                        StreamBuilder<DocumentSnapshot>(
                          stream: db
                              .collection('assets')
                              .doc(widget.assetId)
                              .snapshots(),
                          builder: (ctx, assetLive) {
                            if (!assetLive.hasData || !assetLive.data!.exists) {
                              return _buildDetailRow(
                                'Current Owner',
                                ownerName,
                              );
                            }
                            final liveData =
                            assetLive.data!.data() as Map<String, dynamic>;
                            final liveOwnerId =
                                liveData['ownerId'] ?? liveData['ownerUid'];
                            if (liveOwnerId == null) {
                              return _buildDetailRow(
                                'Current Owner',
                                ownerName,
                              );
                            }
                            return FutureBuilder<DocumentSnapshot>(
                              future: db
                                  .collection('users')
                                  .doc(liveOwnerId)
                                  .get(),
                              builder: (ctx2, userSnap) {
                                String displayName = ownerName;
                                if (userSnap.hasData && userSnap.data!.exists) {
                                  final ud =
                                  userSnap.data!.data()
                                  as Map<String, dynamic>;
                                  displayName =
                                      ud['name'] ?? ud['email'] ?? ownerName;
                                }
                                final isSold =
                                    liveOwnerId !=
                                        (data['ownerId'] ?? data['ownerUid']);
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildDetailRow(
                                      'Current Owner',
                                      displayName,
                                    ),
                                    if (isSold)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.swap_horiz,
                                              size: 14,
                                              color: Colors.orange[700],
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Ownership recently transferred',
                                              style: AppTheme.body(11, color: Colors.orange[700]!),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                );
                              },
                            );
                          },
                        ),
                        if (isLand) ...[
                          if (data['isForRent'] == true) ...[
                            _buildDetailRow('Listing Type', 'For Rent', color: AppTheme.accent),
                            _buildDetailRow('Monthly Rent', 'PKR ${data['monthlyRent'] ?? '—'}'),
                            _buildDetailRow('Security Deposit', 'PKR ${data['securityDeposit'] ?? '—'}'),
                          ] else ...[
                            _buildDetailRow('Listing Type', 'For Sale / Investment'),
                          ],
                          _buildDetailRow('City', data['city'] ?? _blockchainData?['city'] ?? '—'),
                          _buildDetailRow(
                            'Location',
                            data['location'] ??
                                data['address'] ??
                                data['area'] ??
                                _blockchainData?['location'] ??
                                _blockchainData?['address'] ??
                                '—',
                          ),
                        ] else ...[
                          _buildDetailRow('Brand', data['brand'] ?? '—'),
                          _buildDetailRow('Model', data['model'] ?? '—'),
                          _buildDetailRow(
                            'Condition',
                            data['condition'] ?? '—',
                          ),
                          if (data['serial'] != null)
                            _buildDetailRow('Serial', data['serial']),
                          if (data['warranty'] != null &&
                              data['warranty'].isNotEmpty)
                            _buildDetailRow('Warranty', data['warranty']),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ── Documents ─────────────────────────────────────────────
                if (data['documents'] is List &&
                    (data['documents'] as List).isNotEmpty) ...[
                  _buildDocumentsSection(data['documents'] as List),
                  const SizedBox(height: 16),
                ],

                // ── Fraction requests panel (supplier + land) ─────────────
                if (isSupplier &&
                    isLand &&
                    data['blockchainTokenId'] != null) ...[
                  FractionRequestsPanel(
                    assetId: widget.assetId,
                    blockchainPropertyId: data['blockchainTokenId'] as int,
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Action buttons ────────────────────────────────────────
                // Logic:
                // 1. If owner: Show Supplier Management (Transfer/QR) AND User Actions (Resale)
                // 2. If NOT owner: Show User Actions (Request to Buy)
                Builder(builder: (context) {
                  final uid = auth.currentUser?.uid;
                  final ownerId = data['ownerId'] ?? data['ownerUid'];
                  final isOwner = uid != null && uid == ownerId;

                  return Column(
                    children: [
                      if (isOwner && isSupplier) ...[
                        _buildSupplierActions(context, data, role, activeTx),
                        const SizedBox(height: 16),
                      ],
                      _buildUserActions(context, data),
                    ],
                  );
                }),

                const SizedBox(height: 24),

                // ── Reviews ───────────────────────────────────────────────
                // Note: reviews are written from transfer_screen.dart /
                // BuyerOwnershipAcceptScreen after a completed transfer,
                // where a transactionId is available. There is no
                // standalone "Write a Review" entry point here.
                Text(
                  'Reviews',
                  style: AppTheme.heading(20),
                ),
                const SizedBox(height: 12),
                ReviewsList(
                  revieweeUid: data['ownerId'] ?? data['ownerUid'] ?? '',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlockchainSection(String category, Map<String, dynamic> data) {
    return Card(
      color: const Color(0xFFE8F4F6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.verified_user, color: AppTheme.primaryStart),
                const SizedBox(width: 8),
                Text(
                  'Blockchain Verified',
                  style: AppTheme.heading(18, color: AppTheme.textPrimary),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_blockchainData != null) ...[
              if (category == 'electronics') ...[
                _buildDetailRow('Brand', _blockchainData!['brand'] ?? '—'),
                _buildDetailRow('Model', _blockchainData!['model'] ?? '—'),
                _buildDetailRow(
                  'Serial',
                  _blockchainData!['serialNumber'] ?? '—',
                ),
                if (_blockchainData!['warrantyStart'] != null &&
                    _blockchainData!['warrantyStart'].toString().isNotEmpty)
                  _buildDetailRow(
                    'Warranty Start',
                    _blockchainData!['warrantyStart'].toString(),
                  ),
                if (_blockchainData!['originalOwner'] != null &&
                    _blockchainData!['originalOwner'].toString().isNotEmpty &&
                    _blockchainData!['originalOwner'] !=
                        '0x0000000000000000000000000000000000000000')
                  _buildDetailRow(
                    'Original Owner',
                    '${_blockchainData!['originalOwner'].toString().substring(0, 10)}...',
                  ),
                _buildDetailRow(
                  'Status',
                  _blockchainData!['isVerified'] == true
                      ? '✅ Verified'
                      : '⏳ Pending',
                ),
                const Divider(height: 24),
                Row(
                  children: [
                    Icon(
                      _isDataHealthy ? Icons.shield_rounded : Icons.sync_problem_rounded,
                      color: _isDataHealthy ? AppTheme.accent : Colors.orange,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isDataHealthy ? 'Blockchain Secured' : 'Healed from Blockchain',
                            style: AppTheme.heading(14, color: _isDataHealthy ? AppTheme.accent : Colors.orange),
                          ),
                          Text(
                            _isDataHealthy
                                ? 'Data matches immutable blockchain record'
                                : 'Firestore data was restored from source of truth',
                            style: AppTheme.body(11, color: AppTheme.textMid),
                          ),
                        ],
                      ),
                    ),
                    if (_isDataHealthy && (data['verified'] == true || data['isVerified'] == true))
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.verified_user_rounded, color: Colors.green, size: 24),
                      ),
                  ],
                ),
              ] else if (category == 'land') ...[
                _buildDetailRow(
                  'Location',
                  _blockchainData!['location'] ?? '—',
                ),
                _buildDetailRow('City', _blockchainData!['city'] ?? '—'),
                _buildDetailRow(
                  'Total Fractions',
                  _blockchainData!['totalFractions']?.toString() ?? '—',
                ),
                _buildDetailRow(
                  'Price per Fraction',
                  '${_blockchainService.weiToEther(_blockchainData!['pricePerFraction'])} MATIC',
                ),
                if (_blockchainData!['originalOwner'] != null &&
                    _blockchainData!['originalOwner'].toString().isNotEmpty &&
                    _blockchainData!['originalOwner'] !=
                        '0x0000000000000000000000000000000000000000')
                  _buildDetailRow(
                    'Original Owner',
                    '${_blockchainData!['originalOwner'].toString().substring(0, 10)}...',
                  ),
                const Divider(height: 24),
                Row(
                  children: [
                    Icon(
                      _isDataHealthy ? Icons.shield_rounded : Icons.sync_problem_rounded,
                      color: _isDataHealthy ? AppTheme.accent : Colors.orange,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isDataHealthy ? 'Blockchain Secured' : 'Healed from Blockchain',
                            style: AppTheme.heading(14, color: _isDataHealthy ? AppTheme.accent : Colors.orange),
                          ),
                          Text(
                            _isDataHealthy
                                ? 'Land data matches immutable blockchain record'
                                : 'Firestore data was restored from source of truth',
                            style: AppTheme.body(11, color: AppTheme.textMid),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
              if (_ipfsData != null) ...[
                const SizedBox(height: 8),
                const Divider(),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.cloud_done, color: AppTheme.primaryStart),
                    const SizedBox(width: 8),
                    Text(
                      'Documents stored on IPFS',
                      style: AppTheme.heading(14, color: AppTheme.textPrimary),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentsSection(List documents) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Documents',
              style: AppTheme.heading(18),
            ),
            const SizedBox(height: 12),
            ...documents.map((doc) {
              final d = doc as Map<String, dynamic>;
              final hash = d['hash'] as String?;
              final name = d['name'] ?? 'Document';

              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: getDocumentIcon(d['type'] ?? 'file'),
                title: Text(name),
                subtitle: Text(
                  '${(d['type'] ?? 'FILE').toString().toUpperCase()} • '
                      '${formatFileSize(d['size'] ?? 0)}',
                ),
                trailing: hash == null ? null : IconButton(
                  icon: const Icon(Icons.download, color: AppTheme.primaryStart),
                  onPressed: () async {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Downloading $name...')),
                    );
                    final path = await _ipfsService.downloadFile(hash, name);
                    if (mounted) {
                      if (path != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('✅ Saved to: $path'),
                            backgroundColor: AppTheme.accent,
                            action: SnackBarAction(
                              label: 'Open',
                              textColor: Colors.white,
                              onPressed: () => _openFile(path),
                            ),
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('❌ Download failed')),
                        );
                      }
                    }
                  },
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Future<void> _openFile(String path) async {
    try {
      // Simple open logic using url_launcher if it's a path the OS can handle
      // Or just notify the user it's in Downloads.
      // For real file opening, we'd use open_file package, but it's not in pubspec.
      // So we'll just show the path for now.
    } catch (e) {
      debugPrint('Error opening file: $e');
    }
  }

  // ── Resale helpers (owner-only) ───────────────────────────────────────────

  Future<void> _listForResale(Map<String, dynamic> data) async {
    if (_listingInProgress) return;

    final assetTitle = data['title'] ?? 'this asset';

    // Show the "Publish Now" confirmation dialog (mirrors Image 2 design).
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
        title: Row(
          children: [
            Icon(Icons.storefront_outlined, color: AppTheme.primaryStart, size: 28),
            const SizedBox(width: 10),
            Text('List for Sale', style: AppTheme.heading(18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '"$assetTitle" will be published immediately.',
              style: AppTheme.body(15, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 16),
            _publishBullet(Icons.home_outlined, 'Visible on the User Home tab'),
            const SizedBox(height: 10),
            _publishBullet(Icons.store_outlined, 'Visible on the Supplier Home tab'),
            const SizedBox(height: 10),
            _publishBullet(Icons.people_outline, 'Buyers can view and request purchase'),
            const SizedBox(height: 8),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: AppTheme.body(15, color: AppTheme.textMid),
            ),
          ),
          SizedBox(
            width: 200,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryStart,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Publish Now', style: AppTheme.button(15)),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _listingInProgress = true);
    try {
      // Directly publish: mark the asset as listed for resale in Firestore.
      // Uses the asset's existing price so no separate price-entry form is needed.
      await db.collection('assets').doc(widget.assetId).update({
        'isForSale': true,
        'isListedForResale': true,
        'resalePrice': data['resalePrice'] ?? data['price'],
        'resaleDescription': data['description'] ?? '',
        'listedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Asset listed for resale on marketplace!'),
            backgroundColor: Color(0xFF2A7F8F),
          ),
        );
        setState(() {
          _loadFuture = _load();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to list asset: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _listingInProgress = false);
    }
  }

  /// Bullet row used inside the "Publish Now" confirmation dialog.
  Widget _publishBullet(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppTheme.primaryStart),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: AppTheme.body(14, color: AppTheme.textPrimary)),
        ),
      ],
    );
  }

  Future<void> _removeListing() async {
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
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Remove', style: AppTheme.button(14)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _resaleSvc.removeListing(widget.assetId);
      // Also clear isForSale so the supplier home screen hides it too.
      await db.collection('assets').doc(widget.assetId).update({
        'isForSale': false,
        'isListedForResale': false,
        'listedAt': FieldValue.delete(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Listing removed. Asset hidden from marketplace.'),
          ),
        );
        setState(() {
          _loadFuture = _load();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.error),
        );
      }
    }
  }

  Widget _buildUserActions(BuildContext context, Map<String, dynamic> data) {
    final uid = auth.currentUser?.uid;
    final ownerId = data['ownerId'] ?? data['ownerUid'];
    final isOwner = uid != null && uid == ownerId;
    final hasBlockchainId = data['blockchainTokenId'] != null;

    // ── Owner view: resale actions ─────────────────────────────────────────
    if (isOwner) {
      final isListed = data['isListedForResale'] == true;
      final resalePrice = data['resalePrice'];
      // NFT must be minted before the asset can be listed for resale
      final canList = hasBlockchainId;

      return Column(
        children: [
          // Status banner — shown only when actively listed
          if (isListed)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange[300]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.storefront, size: 16, color: Colors.orange[700]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      resalePrice != null
                          ? 'Listed on marketplace · PKR $resalePrice'
                          : 'Listed for Resale',
                      style: AppTheme.heading(13, color: Colors.orange[700]!),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

          Row(
            children: [
              // List / Remove listing button
              Expanded(
                child: isListed
                    ? ElevatedButton.icon(
                  onPressed: _removeListing,
                  icon: const Icon(Icons.remove_circle_outline),
                  label: const Text('Remove Listing'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    backgroundColor: AppTheme.error,
                    foregroundColor: Colors.white,
                  ),
                )
                    : ListForSaleButton(
                  onPressed: !canList ? null : () => _listForResale(data),
                  isLoading: _listingInProgress,
                ),
              ),

              // Certificate button (only when NFT exists)
              if (hasBlockchainId) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => NFTCertificateScreen(
                          assetId: widget.assetId,
                          assetData: data,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.verified_user),
                    label: const Text('Certificate'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 50),
                      foregroundColor: AppTheme.primaryStart,
                      side: const BorderSide(color: AppTheme.primaryStart),
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (data['category'] == 'land' && !isListed) ...[
            const SizedBox(height: 12),
            ListForRentButton(
              onPressed: (!canList || data['blockchainTokenId'] == null)
                  ? null
                  : () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RentDistributionScreen(
                      assetId: widget.assetId,
                      propertyId: (data['blockchainTokenId'] as num).toInt(),
                      isOwner: true,
                    ),
                  ),
                );
              },
            ),
          ],
          if (hasBlockchainId) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TransferHistoryScreen(assetId: widget.assetId),
                  ),
                ),
                icon: const Icon(Icons.history),
                label: const Text('View Transfer History'),
              ),
            ),
          ],
        ],
      );
    }

    // ── Non-owner / buyer view: existing purchase actions ──────────────────
    if (data['isForRent'] == true) {
      return Column(
        children: [
          RequestRentButton(
            onPressed: () => _requestToRent(
              context,
              widget.assetId,
              data['ownerId'] ?? data['ownerUid'],
              data,
            ),
          ),
          const SizedBox(height: 12),
          _buildBuyerSecondaryActions(context, data),
        ],
      );
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _requestToBuy(
                  context,
                  widget.assetId,
                  data['ownerId'] ?? data['ownerUid'],
                  data,
                ),
                icon: const Icon(Icons.shopping_cart),
                label: Text(
                  data['category'] == 'land'
                      ? 'Purchase/Invest'
                      : 'Request to Buy',
                ),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (hasBlockchainId)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => NFTCertificateScreen(
                        assetId: widget.assetId,
                        assetData: data,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.verified_user),
                  label: const Text('Certificate'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 50),
                    foregroundColor: AppTheme.primaryStart,
                    side: const BorderSide(color: AppTheme.primaryStart),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _buildBuyerSecondaryActions(context, data),
      ],
    );
  }

  Widget _buildBuyerSecondaryActions(BuildContext context, Map<String, dynamic> data) {
    final hasBlockchainId = data['blockchainTokenId'] != null;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _toggleFavorite(context, widget.assetId),
                icon: const Icon(Icons.favorite_border),
                label: const Text('Favorite'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.share),
                label: const Text('Share'),
              ),
            ),
          ],
        ),
        if (hasBlockchainId) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TransferHistoryScreen(assetId: widget.assetId),
                ),
              ),
              icon: const Icon(Icons.history),
              label: const Text('View Transfer History'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSupplierActions(
      BuildContext context,
      Map<String, dynamic> data,
      String role,
      Map<String, dynamic>? activeTx,
      ) {
    final isLand = data['category'] == 'land';
    final hasBlockchainId = data['blockchainTokenId'] != null;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _verifyAsset(context, widget.assetId),
                icon: const Icon(Icons.verified),
                label: const Text('Verify'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => QRGeneratorScreen(
                        assetId: widget.assetId,
                        category: data['category'],
                        blockchainTokenId: data['blockchainTokenId'],
                        title: data['title'] ?? 'Asset',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.qr_code_2),
                label: const Text('QR Code'),
              ),
            ),
          ],
        ),

        if (hasBlockchainId) ...[
          const SizedBox(height: 12),

          if (isLand) ...[
            _ApprovedFractionTransferButton(
              assetId: widget.assetId,
              blockchainPropertyId: data['blockchainTokenId'] as int,
              assetData: data,
              onTransferComplete: () => setState(() {
                _loadFuture = _load();
              }),
            ),
            const SizedBox(height: 8),
          ],

          // Transfer Ownership button removed from here - moved to Chat

          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      TransferHistoryScreen(assetId: widget.assetId),
                ),
              ),
              icon: const Icon(Icons.history),
              label: const Text('View Transfer History'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDetailRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: AppTheme.body(13, weight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTheme.heading(13, color: color ?? AppTheme.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  // ── Private methods ───────────────────────────────────────────────────────

  void _showQRCode(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final doc = await db.collection('assets').doc(widget.assetId).get();
      if (context.mounted) Navigator.pop(context);
      if (!doc.exists) return;
      final data = doc.data() as Map<String, dynamic>;
      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => QRGeneratorScreen(
              assetId: widget.assetId,
              category: data['category'] ?? 'electronics',
              blockchainTokenId: data['blockchainTokenId'],
              title: data['title'] ?? 'Asset',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading QR Code: $e')));
      }
    }
  }

  Future<void> _requestToBuy(
      BuildContext ctx,
      String assetId,
      String? sellerId,
      Map<String, dynamic> assetData,
      ) async {
    final user = auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(
        ctx,
      ).showSnackBar(const SnackBar(content: Text('Please login')));
      return;
    }

    final category = assetData['category'] ?? '';
    final blockchainTokenId = assetData['blockchainTokenId'] as int?;

    if (category == 'land' && blockchainTokenId != null) {
      final choice = await showDialog<String>(
        context: ctx,
        builder: (dialogCtx) => AlertDialog(
          title: const Text('Purchase Options'),
          content: const Text(
            'Would you like to purchase fractions of this property?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, 'cancel'),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, 'full'),
              child: const Text('Request Full Purchase'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogCtx, 'fractions'),
              child: const Text('Request Fractions'),
            ),
          ],
        ),
      );

      if (choice == 'fractions') {
        if (ctx.mounted) {
          Navigator.push(
            ctx,
            MaterialPageRoute(
              builder: (_) => LandFractionsScreen(
                assetId: assetId,
                blockchainPropertyId: blockchainTokenId,
              ),
            ),
          );
        }
        return;
      } else if (choice != 'full') {
        return;
      }
    }

    final existing = await db
        .collection('transactions')
        .where('assetId', isEqualTo: assetId)
        .where('buyerUid', isEqualTo: user.uid)
        .where('status', whereIn: ['pending', 'approved', 'completed'])
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(
            content: Text('You already have a request for this asset'),
          ),
        );
      }
      return;
    }

    final txId = _uuid.v4();
    await db.collection('transactions').doc(txId).set({
      'transactionId': txId,
      'assetId': assetId,
      'buyerUid': user.uid,
      'sellerUid': sellerId,
      'status': 'pending',
      'category': category,
      'blockchainTokenId': blockchainTokenId,
      'createdAt': FieldValue.serverTimestamp(),
    });

    await addTransaction(
      userId: user.uid,
      type: 'sent',
      title: assetData['title'] ?? 'Asset',
      toAddress: assetData['ownerUid'] ?? assetData['ownerId'],
      value: assetData['price']?.toString() ?? '0',
    );

    await db.collection('chats').doc(txId).set({
      'transactionId': txId,
      'assetId': assetId,
      'assetType': category,
      'buyerUid': user.uid,
      'sellerUid': sellerId,
      'participants': [user.uid, sellerId],
      'lastMessage': '',
      'lastMessageTime': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    });

    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(
          content: Text(
            '✅ Request sent! Chat will open when supplier approves.',
          ),
          backgroundColor: Color(0xFF2A7F8F),
        ),
      );
    }
  }

  Future<void> _requestToRent(
      BuildContext ctx,
      String assetId,
      String ownerUid,
      Map<String, dynamic> assetData,
      ) async {
    final user = auth.currentUser;
    if (user == null) return;

    final category = assetData['category'] ?? 'land';
    final blockchainTokenId = assetData['blockchainTokenId'];
    final monthlyRent = assetData['monthlyRent'] ?? assetData['rentAmount'] ?? 0.0;
    final securityDeposit = assetData['securityDeposit'] ?? 0.0;
    final leaseMonths = assetData['leaseMonths'] ?? 6;

    // Check for existing pending/active requests
    final existing = await db
        .collection('transactions')
        .where('assetId', isEqualTo: assetId)
        .where('buyerUid', isEqualTo: user.uid)
        .where('status', whereIn: ['pendingApproval', 'approved', 'active'])
        .get();

    if (existing.docs.isNotEmpty) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(
            content: Text('You already have a rental request or active lease.'),
          ),
        );
      }
      return;
    }

    // 🔗 Optional: Blockchain Request (Only for Land)
    String? txHash;
    if (category == 'land' && blockchainTokenId != null) {
      if (!ctx.mounted) return;

      // Show dismissible dialog — user must be able to switch to MetaMask
      showDialog(
        context: ctx,
        barrierDismissible: true,
        builder: (dialogCtx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Approve in MetaMask'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text(
                'A rent request transaction has been sent to MetaMask.\n\n'
                    'Please open MetaMask and tap Confirm.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Tap outside this dialog to switch to MetaMask manually.',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );

      try {
        txHash = await _blockchainService.requestLandRent(
          (blockchainTokenId as num).toInt(),
        );
        await _blockchainService.waitForConfirmation(txHash ?? '');
      } catch (e) {
        if (ctx.mounted) {
          Navigator.of(ctx, rootNavigator: true).pop(); // close dialog
          ScaffoldMessenger.of(ctx).showSnackBar(
            SnackBar(
              content: Text('Blockchain Error: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 8),
            ),
          );
        }
        return;
      }

      if (ctx.mounted) Navigator.of(ctx, rootNavigator: true).pop();
    }

    final txId = _uuid.v4();
    final batch = db.batch();

    batch.set(db.collection('transactions').doc(txId), {
      'transactionId': txId,
      'assetId': assetId,
      'buyerUid': user.uid,
      'sellerUid': ownerUid,
      'status': 'pendingApproval',
      'category': category,
      'requestType': 'rental',
      'blockchainTokenId': blockchainTokenId,
      'rentalFee': monthlyRent.toDouble(),
      'depositAmount': securityDeposit.toDouble(),
      'leaseMonths': leaseMonths,
      'txHash': txHash,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Create Chat
    batch.set(db.collection('chats').doc(txId), {
      'transactionId': txId,
      'assetId': assetId,
      'assetType': category,
      'buyerUid': user.uid,
      'sellerUid': ownerUid,
      'participants': [user.uid, ownerUid],
      'lastMessage': 'I am interested in renting this property.',
      'lastMessageTime': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();

    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(
          content: Text('✅ Rental request sent! Wait for owner approval.'),
          backgroundColor: AppTheme.accent,
        ),
      );
    }
  }

  void _showProcessingDialog(BuildContext context, String msg) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(msg),
          ],
        ),
      ),
    );
  }

  Future<void> _verifyAsset(BuildContext ctx, String assetId) async {
    // ── Step 1: Wallet check ────────────────────────────────────────────────
    if (!_blockchainService.isConnected) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Connect your wallet first.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    // ── Step 2: Load asset data ─────────────────────────────────────────────
    final doc = await db.collection('assets').doc(assetId).get();
    if (!doc.exists || !ctx.mounted) return;

    final data = doc.data()!;
    final tokenId = data['blockchainTokenId'];
    final category = data['category']?.toString().toLowerCase();

    if (tokenId == null) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(
          content: Text('❌ Asset has no blockchain token ID.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final id = (tokenId is int) ? tokenId : int.parse(tokenId.toString());

    // ── Step 3: Show MetaMask-aware dialog ──────────────────────────────────
    // This dialog stays visible while MetaMask is open in the background.
    // It is deliberately dismissible so the user can switch apps manually
    // if the deep link does not bring MetaMask to the foreground.
    if (!ctx.mounted) return;
    showDialog(
      context: ctx,
      barrierDismissible: true, // ← allows user to switch to MetaMask manually
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Approve in MetaMask'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            const Text(
              'A transaction has been sent to MetaMask.\n\n'
                  'Please open MetaMask and tap Confirm to verify this asset on-chain.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'You can tap outside this dialog to switch to MetaMask manually.',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );

    // ── Step 4: Execute blockchain verification ─────────────────────────────
    String? txHash;
    try {
      await _blockchainService.init();
      if (category == 'land') {
        txHash = await _blockchainService.verifyProperty(id);
      } else {
        txHash = await _blockchainService.verifyDevice(id);
      }
    } catch (e) {
      // Close the dialog and surface the real error (Timeout, Rejected, etc.)
      if (ctx.mounted) {
        Navigator.of(ctx, rootNavigator: true).pop(); // close dialog
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text('❌ Verification failed: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 8),
          ),
        );
      }
      return;
    }

    // Close the MetaMask dialog now that the wallet responded
    if (ctx.mounted) Navigator.of(ctx, rootNavigator: true).pop();

    if (txHash == null) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(
            content: Text('❌ Transaction was rejected.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // ── Step 5: Poll for on-chain confirmation ──────────────────────────────
    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(
          content: Text('⏳ Confirming on Polygon Amoy...'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 30),
        ),
      );
    }

    final confirmed = await _blockchainService.waitForConfirmation(txHash);
    if (!confirmed) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text(
              '⚠️ Tx submitted but not confirmed yet.\n'
                  'Hash: ${txHash.substring(0, 18)}...\n'
                  'Check Polygonscan Amoy if it does not update.',
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 10),
          ),
        );
      }
      // Still update Firestore optimistically — the tx IS on-chain
      await db.collection('assets').doc(assetId).update({
        'verified': true,
        'verifiedAt': FieldValue.serverTimestamp(),
        'verifyTxHash': txHash,
      });
      if (ctx.mounted) setState(() => _loadFuture = _load());
      return;
    }

    // ── Step 6: Confirmed — update Firestore ────────────────────────────────
    await db.collection('assets').doc(assetId).update({
      'verified': true,
      'verifiedAt': FieldValue.serverTimestamp(),
      'verifyTxHash': txHash,
    });

    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(
          content: Text('✅ Asset verified on-chain!'),
          backgroundColor: Colors.green,
        ),
      );
      setState(() => _loadFuture = _load());
    }
  }

  Future<void> _toggleFavorite(BuildContext ctx, String assetId) async {
    final user = auth.currentUser;
    if (user == null) return;

    final favRef = db
        .collection('users')
        .doc(user.uid)
        .collection('favorites')
        .doc(assetId);

    final doc = await favRef.get();
    if (doc.exists) {
      await favRef.delete();
      if (ctx.mounted) {
        ScaffoldMessenger.of(
          ctx,
        ).showSnackBar(const SnackBar(content: Text('Removed from favorites')));
      }
    } else {
      await favRef.set({
        'assetId': assetId,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (ctx.mounted) {
        ScaffoldMessenger.of(
          ctx,
        ).showSnackBar(const SnackBar(content: Text('Added to favorites')));
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _APPROVED FRACTION TRANSFER BUTTON
// ─────────────────────────────────────────────────────────────────────────────
class _ApprovedFractionTransferButton extends StatelessWidget {
  final String assetId;
  final int blockchainPropertyId;
  final Map<String, dynamic> assetData;
  final VoidCallback onTransferComplete;

  const _ApprovedFractionTransferButton({
    required this.assetId,
    required this.blockchainPropertyId,
    required this.assetData,
    required this.onTransferComplete,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('fraction_requests')
          .where('assetId', isEqualTo: assetId)
          .where('status', isEqualTo: 'approved')
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }
        final approvedRequests = snap.data!.docs;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.check_circle,
                  color: AppTheme.primaryStart,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  'Approved Fraction Transfers (${approvedRequests.length})',
                  style: AppTheme.heading(14, color: AppTheme.primaryStart),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...approvedRequests.map((doc) {
              final r = doc.data();
              final buyerUid = r['buyerUid'] ?? '';
              final fractionsRequested = r['fractionsRequested'] ?? 0;
              final transactionId = (r['transactionId'] ?? '').toString().trim();

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: AppTheme.primaryStart.withOpacity(0.2)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FutureBuilder<DocumentSnapshot>(
                        future: FirebaseFirestore.instance
                            .collection('users')
                            .doc(buyerUid)
                            .get(),
                        builder: (ctx, userSnap) {
                          final name = userSnap.hasData && userSnap.data!.exists
                              ? (userSnap.data!.data()
                          as Map<String, dynamic>)['name'] ??
                              'Buyer'
                              : buyerUid;
                          return Row(
                            children: [
                              const Icon(
                                Icons.person,
                                size: 14,
                                color: AppTheme.textMid,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Buyer: $name',
                                style: AppTheme.heading(13),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryStart.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '$fractionsRequested fractions',
                                  style: AppTheme.body(12, color: AppTheme.primaryStart),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => _executeFractionTransfer(
                            context,
                            doc.id,
                            buyerUid,
                            fractionsRequested,
                            transactionId,
                          ),
                          icon: const Icon(Icons.send, size: 16),
                          label: const Text('Execute Fraction Transfer'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryStart,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }

  Future<void> _executeFractionTransfer(
      BuildContext context,
      String fractionRequestId,
      String buyerUid,
      int fractionsRequested,
      String transactionId,
      ) async {
    final sellerUid = FirebaseAuth.instance.currentUser?.uid;
    if (sellerUid == null) return;

    final buyerDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(buyerUid)
        .get();
    final buyerName = buyerDoc.data()?['name'] ?? 'Buyer';
    final assetPrice = assetData['price']?.toString() ?? '0';

    if (!context.mounted) return;

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => TransferScreen(
          assetId: assetId,
          assetType: AssetType.land,
          transactionId: transactionId,
          buyerUid: buyerUid,
          sellerUid: sellerUid,
          propertyId: blockchainPropertyId,
          fractionAmount: fractionsRequested,
          assetPrice: assetPrice,
          buyerName: buyerName,
        ),
      ),
    );

    if (result == true) {
      final existingTransactionId = await _existingTransactionId(transactionId);
      final batch = FirebaseFirestore.instance.batch();
      batch.update(
        FirebaseFirestore.instance
            .collection('fraction_requests')
            .doc(fractionRequestId),
        {'status': 'completed', 'completedAt': FieldValue.serverTimestamp()},
      );
      if (existingTransactionId != null) {
        batch.update(
          FirebaseFirestore.instance
              .collection('transactions')
              .doc(existingTransactionId),
          {'status': 'completed', 'completedAt': FieldValue.serverTimestamp()},
        );
      }
      await batch.commit();

      await addTransaction(
        userId: sellerUid,
        type: 'received',
        title: assetData['title'] ?? 'Asset',
        toAddress: buyerUid,
        value: assetPrice,
      );
      await addTransaction(
        userId: buyerUid,
        type: 'nft',
        title: assetData['title'] ?? 'Asset',
        toAddress: sellerUid,
      );

      onTransferComplete();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Fraction transfer completed successfully!'),
            backgroundColor: Color(0xFF2A7F8F),
          ),
        );
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NFT CERTIFICATE SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class NFTCertificateScreen extends StatefulWidget {
  final String assetId;
  final Map<String, dynamic> assetData;

  const NFTCertificateScreen({
    super.key,
    required this.assetId,
    required this.assetData,
  });

  @override
  State<NFTCertificateScreen> createState() => _NFTCertificateScreenState();
}

class _NFTCertificateScreenState extends State<NFTCertificateScreen> {
  final _blockchainService = BlockchainServiceEnhanced();

  bool _loading = true;
  String? _error;

  Map<String, dynamic>? _chainData;
  int _priorTransferCount = 0;
  bool _isReportedStolen = false;
  String _originalOwnerWallet = '';
  String _originalOwnerName = 'Unknown';
  String _warrantyStart = '—';

  @override
  void initState() {
    super.initState();
    _loadCertificateData();
  }

  Future<void> _loadCertificateData() async {
    try {
      final tokenId = widget.assetData['blockchainTokenId'] as int?;
      final category = widget.assetData['category'] ?? 'electronics';

      if (tokenId != null) {
        await _blockchainService.init();
        _chainData = category == 'electronics'
            ? await _blockchainService.getDevice(tokenId)
            : await _blockchainService.getLandProperty(tokenId);
      }

      if (_chainData != null) {
        final raw = _chainData!['originalOwner']?.toString() ?? '';
        if (raw.isNotEmpty &&
            raw != '0x0000000000000000000000000000000000000000') {
          _originalOwnerWallet = raw;
        }

        final ws = _chainData!['warrantyStart'];
        if (ws is int && ws > 0) {
          final dt = DateTime.fromMillisecondsSinceEpoch(ws * 1000);
          _warrantyStart =
          '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
        } else if (ws is String && ws.isNotEmpty) {
          _warrantyStart = ws;
        }

        if (_warrantyStart == '—') {
          final fw = widget.assetData['warranty']?.toString() ?? '';
          if (fw.isNotEmpty) _warrantyStart = fw;
        }
      }

      final ownerId =
          widget.assetData['ownerId'] ?? widget.assetData['ownerUid'];
      if (ownerId != null) {
        try {
          final ownerSnap = await db
              .collection('users')
              .doc(ownerId as String)
              .get();
          if (ownerSnap.exists) {
            _originalOwnerName =
                ownerSnap.data()?['name'] ??
                    ownerSnap.data()?['email'] ??
                    'Unknown';
          }
        } catch (_) {}
      }

      try {
        final txSnap = await db
            .collection('transactions')
            .where('assetId', isEqualTo: widget.assetId)
            .where('status', whereIn: ['completed', 'transferred', 'done'])
            .get();
        _priorTransferCount = txSnap.docs.length;
      } catch (_) {}

      try {
        final assetSnap = await db
            .collection('assets')
            .doc(widget.assetId)
            .get();
        if (assetSnap.exists) {
          final d = assetSnap.data()!;
          _isReportedStolen =
              d['isStolen'] == true ||
                  d['reportedStolen'] == true ||
                  d['stolenReported'] == true;
        }
      } catch (_) {}

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted)
        setState(() {
          _error = e.toString();
          _loading = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final category = widget.assetData['category'] ?? 'electronics';
    final isElectronics = category == 'electronics';

    return Scaffold(
      backgroundColor: context.appScaffold,
      appBar: AppBar(
        title: Text(
          'NFT Certificate',
          style: AppTheme.heading(20, color: Colors.white),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppTheme.primaryGradient),
        ),
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
            size: 18,
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 64,
                color: AppTheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Failed to load certificate: $_error',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.appTextPrimary),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });
                  _loadCertificateData();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      )
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildCertificateHeader(),
            const SizedBox(height: 16),
            _buildModelDetailsCard(isElectronics),
            const SizedBox(height: 12),
            _buildVerificationChecksCard(),
            const SizedBox(height: 12),
            _buildBuyerConfirmationBanner(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildCertificateHeader() {
    final isVerified = _chainData != null ||
        _chainData?['isVerified'] == true ||
        widget.assetData['blockchainVerified'] == true;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isVerified
              ? [AppTheme.primaryStart, AppTheme.primaryEnd]
              : [Colors.orange[700]!, Colors.orange[400]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(
            isVerified ? Icons.verified_user : Icons.pending,
            size: 56,
            color: Colors.white,
          ),
          const SizedBox(height: 10),
          Text(
            isVerified
                ? 'Blockchain Verified Certificate'
                : 'Verification Pending',
            style: AppTheme.heading(18, color: Colors.white),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'Token ID: ${widget.assetData['blockchainTokenId'] ?? '—'}  •  Polygon Amoy',
            style: AppTheme.body(12, color: Colors.white.withOpacity(0.7)),
          ),
        ],
      ),
    );
  }

  Widget _buildModelDetailsCard(bool isElectronics) {
    return Card(
      color: context.appSurface,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _certSectionTitle(
              icon: Icons.info_outline,
              label: isElectronics ? 'Device Details' : 'Property Details',
            ),
            Divider(height: 20, color: context.appBorder),
            if (isElectronics) ...[
              _certRow(
                'Brand',
                _chainData?['brand'] ?? widget.assetData['brand'] ?? '—',
              ),
              _certRow(
                'Model',
                _chainData?['model'] ?? widget.assetData['model'] ?? '—',
              ),
              _certRow(
                'Serial Number',
                _chainData?['serialNumber'] ??
                    widget.assetData['serial'] ??
                    '—',
              ),
              _certRow('Condition', widget.assetData['condition'] ?? '—'),
              _certRow('Warranty Start / Expiry', _warrantyStart),
            ] else ...[
              _certRow(
                'Location',
                _chainData?['location'] ?? widget.assetData['location'] ?? '—',
              ),
              _certRow(
                'City',
                _chainData?['city'] ?? widget.assetData['city'] ?? '—',
              ),
              _certRow(
                'Plot Area',
                '${widget.assetData['plotArea'] ?? '—'} ${widget.assetData['plotUnit'] ?? ''}',
              ),
              _certRow(
                'Total Fractions',
                _chainData?['totalFractions']?.toString() ?? '—',
              ),
            ],
            const Divider(height: 20),
            _certSectionTitle(
              icon: Icons.person_outline,
              label: 'Original Owner',
            ),
            const SizedBox(height: 8),
            _certRow('Name', _originalOwnerName),
            if (_originalOwnerWallet.isNotEmpty)
              _certRow(
                'Wallet',
                '${_originalOwnerWallet.substring(0, 12)}...${_originalOwnerWallet.substring(_originalOwnerWallet.length - 6)}',
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildVerificationChecksCard() {
    final notResold = _priorTransferCount == 0;
    final notStolen = !_isReportedStolen;
    final isVerified = _chainData != null ||
        _chainData?['isVerified'] == true ||
        widget.assetData['blockchainVerified'] == true;

    return Card(
      color: context.appSurface,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _certSectionTitle(
              icon: Icons.checklist,
              label: 'Authenticity Checks',
            ),
            Divider(height: 20, color: context.appBorder),
            _checkRow(
              label: 'Blockchain Verified',
              passed: isVerified,
              passText: 'Confirmed on Polygon Amoy',
              failText: 'Verification pending',
            ),
            const SizedBox(height: 10),
            _checkRow(
              label: 'Resale History',
              passed: notResold,
              passText: 'Never previously resold',
              failText:
              'Resold $_priorTransferCount time${_priorTransferCount == 1 ? '' : 's'} before',
            ),
            const SizedBox(height: 10),
            _checkRow(
              label: 'Stolen Report',
              passed: notStolen,
              passText: 'No stolen reports found',
              failText: '⚠️ This unit has been reported stolen!',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBuyerConfirmationBanner() {
    final allClear = !_isReportedStolen && _priorTransferCount == 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: allClear
            ? (context.isDarkMode
            ? AppTheme.primaryStart.withOpacity(0.12)
            : AppTheme.primaryStart.withOpacity(0.05))
            : (context.isDarkMode
            ? AppTheme.error.withOpacity(0.14)
            : AppTheme.error.withOpacity(0.05)),
        border: Border.all(
          color: allClear ? AppTheme.accent : AppTheme.error,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            allClear ? Icons.thumb_up_alt_outlined : Icons.warning_amber,
            color: allClear ? AppTheme.primaryStart : AppTheme.error,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  allClear
                      ? 'This unit is safe to purchase'
                      : 'Caution before purchasing',
                  style: AppTheme.heading(
                    15,
                    color: allClear
                        ? (context.isDarkMode
                        ? AppTheme.primaryEnd
                        : AppTheme.primaryStart)
                        : AppTheme.error,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  allClear
                      ? 'This asset has not been previously resold and has no stolen reports. The certificate above is recorded immutably on the blockchain.'
                      : 'One or more checks above did not pass. Please review the details carefully before proceeding with any purchase.',
                  style: AppTheme.body(
                    13,
                    color: allClear
                        ? context.appTextPrimary
                        : AppTheme.error,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _certSectionTitle({required IconData icon, required String label}) {
    final sectionColor = context.isDarkMode
        ? AppTheme.primaryEnd
        : AppTheme.primaryStart;
    return Row(
      children: [
        Icon(icon, size: 20, color: sectionColor),
        const SizedBox(width: 8),
        Text(
          label,
          style: AppTheme.heading(15, color: sectionColor),
        ),
      ],
    );
  }

  Widget _certRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              '$label:',
              style: AppTheme.body(13, color: context.appTextSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTheme.heading(13, color: context.appTextPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _checkRow({
    required String label,
    required bool passed,
    required String passText,
    required String failText,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: passed ? AppTheme.primaryStart.withOpacity(0.1) : AppTheme.error.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            passed ? Icons.check : Icons.close,
            size: 16,
            color: passed ? AppTheme.primaryStart : AppTheme.error,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTheme.heading(14, color: context.appTextPrimary),
              ),
              const SizedBox(height: 2),
              Text(
                passed ? passText : failText,
                style: AppTheme.body(
                  12,
                  color: passed ? context.appTextSecondary : AppTheme.error,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}