import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:image/image.dart' as img;

import 'chat_list_screen.dart';
import 'profile_screen.dart';
import 'asset_screen.dart';
import '../services/push_notification_service.dart';
import 'shared_screens.dart';
import 'qr_generator_screen.dart';
import 'qr_scanner_enhanced.dart';
import '../blockchain/blockchain_service.dart';
import '../blockchain/ipfs_service.dart';
import '../blockchain/wallet_service.dart';
import 'wallet_screen.dart';
import '../theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

final db = FirebaseFirestore.instance;
final auth = FirebaseAuth.instance;
const uuid = Uuid();

extension _Cap on String {
  String capitalize() =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}

// UTILITIES (Compression & Storage)
Future<String> compressImageToBase64(
  Uint8List bytes, {
  int quality = 70,
}) async {
  final image = img.decodeImage(bytes);
  if (image == null) return base64Encode(bytes);

  img.Image resized = image;
  if (image.width > 800) {
    resized = img.copyResize(image, width: 800);
  }

  final compressed = img.encodeJpg(resized, quality: quality);
  final base64Str = base64Encode(compressed);

  if (base64Str.length > 900000) {
    return compressImageToBase64(bytes, quality: quality - 10);
  }

  return base64Str;
}

String _formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1048576).toStringAsFixed(1)} MB';
}

String _normalizeDeviceIdentifier(String value) {
  return value.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
}

String _compactNumericIdentifier(String value) {
  return value.replaceAll(RegExp(r'[\s-]'), '');
}

bool _validateImeiIdentifier(String value) {
  final imei = _compactNumericIdentifier(value);
  if (!RegExp(r'^\d{15}$').hasMatch(imei)) return false;

  int total = 0;
  for (int i = 0; i < 15; i++) {
    int digit = int.parse(imei[i]);
    if (i.isOdd) {
      digit *= 2;
      if (digit > 9) digit -= 9;
    }
    total += digit;
  }
  return total % 10 == 0;
}

String _friendlyErrorText(Object error) {
  return error.toString().replaceFirst('Exception: ', '');
}

class DocumentStorage {
  static const int smallFileLimit = 100 * 1024;
  static const int mediumFileLimit = 500 * 1024;
  static const int maxChunkSize = 900 * 1024;

  static Future<Map<String, dynamic>> storeDocument(
    Uint8List bytes,
    String fileName,
    String fileType,
  ) async {
    final originalSize = bytes.length;

    if (originalSize <= smallFileLimit) {
      return _storeSmallFile(bytes, fileName, fileType, originalSize);
    } else if (originalSize <= mediumFileLimit) {
      return await _storeMediumFile(bytes, fileName, fileType, originalSize);
    } else {
      return await _storeLargeFile(bytes, fileName, fileType, originalSize);
    }
  }

  static Map<String, dynamic> _storeSmallFile(
    Uint8List bytes,
    String fileName,
    String fileType,
    int originalSize,
  ) {
    final base64Str = base64Encode(bytes);
    return {
      'name': fileName,
      'type': fileType,
      'storageStrategy': 'direct_base64',
      'data': base64Str,
      'originalSize': originalSize,
      'compressedSize': base64Str.length,
      'requiresChunks': false,
      'chunkCount': 1,
    };
  }

  static Future<Map<String, dynamic>> _storeMediumFile(
    Uint8List bytes,
    String fileName,
    String fileType,
    int originalSize,
  ) async {
    final isImage = ['jpg', 'jpeg', 'png'].contains(fileType.toLowerCase());

    if (isImage) {
      final base64Str = await compressImageToBase64(bytes, quality: 60);
      final compressedBytes = base64Decode(base64Str);
      return {
        'name': fileName,
        'type': fileType,
        'storageStrategy': 'compressed_image',
        'data': base64Str,
        'originalSize': originalSize,
        'compressedSize': compressedBytes.length,
        'compressionRatio': originalSize > 0
            ? compressedBytes.length / originalSize
            : 1.0,
        'requiresChunks': false,
        'chunkCount': 1,
      };
    } else {
      final base64Str = base64Encode(bytes);
      if (base64Str.length <= maxChunkSize) {
        return {
          'name': fileName,
          'type': fileType,
          'storageStrategy': 'direct_base64',
          'data': base64Str,
          'originalSize': originalSize,
          'compressedSize': base64Str.length,
          'requiresChunks': false,
          'chunkCount': 1,
        };
      } else {
        return await _splitIntoChunks(bytes, fileName, fileType, originalSize);
      }
    }
  }

  static Future<Map<String, dynamic>> _storeLargeFile(
    Uint8List bytes,
    String fileName,
    String fileType,
    int originalSize,
  ) async {
    final isImage = ['jpg', 'jpeg', 'png'].contains(fileType.toLowerCase());

    if (isImage) {
      final base64Str = await compressImageToBase64(bytes, quality: 50);
      final compressedBytes = base64Decode(base64Str);

      if (base64Str.length <= maxChunkSize) {
        return {
          'name': fileName,
          'type': fileType,
          'storageStrategy': 'compressed_image',
          'data': base64Str,
          'originalSize': originalSize,
          'compressedSize': compressedBytes.length,
          'compressionRatio': originalSize > 0
              ? compressedBytes.length / originalSize
              : 1.0,
          'requiresChunks': false,
          'chunkCount': 1,
        };
      }
    }
    return await _splitIntoChunks(bytes, fileName, fileType, originalSize);
  }

  static Future<Map<String, dynamic>> _splitIntoChunks(
    Uint8List bytes,
    String fileName,
    String fileType,
    int originalSize,
  ) async {
    final base64Str = base64Encode(bytes);
    final chunks = <String>[];
    final chunkSize = (maxChunkSize * 0.8).toInt();

    for (int i = 0; i < base64Str.length; i += chunkSize) {
      final end = (i + chunkSize < base64Str.length)
          ? i + chunkSize
          : base64Str.length;
      chunks.add(base64Str.substring(i, end));
    }

    return {
      'name': fileName,
      'type': fileType,
      'storageStrategy': 'chunked',
      'chunks': chunks,
      'originalSize': originalSize,
      'compressedSize': base64Str.length,
      'requiresChunks': true,
      'chunkCount': chunks.length,
    };
  }
}

class SupplierHomeScreen extends StatefulWidget {
  final String type;
  const SupplierHomeScreen({super.key, required this.type});

  @override
  State<SupplierHomeScreen> createState() => _SupplierHomeScreenState();
}

class _SupplierHomeScreenState extends State<SupplierHomeScreen> {
  int _selectedIndex = 0;
  bool _showHelp = false;
  final Set<int> _loadedTabs = {0};

  @override
  void initState() {
    super.initState();
    _checkHelpStatus();
  }

  Future<void> _checkHelpStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool('seen_supplier_help') ?? false;
    if (!seen) {
      if (mounted) setState(() => _showHelp = true);
      await prefs.setBool('seen_supplier_help', true);
    }
  }

  void _onTap(int idx) {
    if (idx == 1) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const QRScannerEnhanced()),
      );
      return;
    }
    setState(() {
      _loadedTabs.add(idx);
      _selectedIndex = idx;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      //  appBar: AppBar(title: Text('${widget.type.capitalize()} Supplier')),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          SupplierHome(type: widget.type, showHelp: () => _showHelp),
          const SizedBox(),
          _loadedTabs.contains(2)
              ? const MyAssetsScreen()
              : const SizedBox.shrink(),
          _loadedTabs.contains(3)
              ? const ProfileScreen(showFavorites: false)
              : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: _onTap,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(
            icon: Icon(Icons.qr_code_scanner),
            label: 'Scan',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.inventory),
            label: 'My Assets',
          ),

          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

class SupplierHome extends StatelessWidget {
  final String type;
  final bool Function() showHelp;
  const SupplierHome({super.key, required this.type, required this.showHelp});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appScaffold,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: 20,
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/logos.png',
                width: 40,
                height: 40,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${type.capitalize()} Supplier',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: context.appTextPrimary,
                  ),
                ),
                Text(
                  'My Assets',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.appTextSecondary,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.account_balance_wallet_outlined,
              color: context.appTextPrimary,
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
              int unreadCount = snapshot.data?.docs.length ?? 0;
              return Badge(
                label: Text(unreadCount.toString()),
                isLabelVisible: unreadCount > 0,
                offset: const Offset(-4, 4),
                child: IconButton(
                  icon: Icon(
                    Icons.notifications_outlined,
                    color: context.appTextPrimary,
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
          const SizedBox(width: 4),
        ],
      ),
      body: AssetManagementScreen(type: type),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.small(
            heroTag: 'chat_fab',
            backgroundColor: context.appSurface,
            foregroundColor: AppTheme.primaryStart,
            elevation: 2,
            child: const Icon(Icons.chat_bubble_outline_rounded),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ChatListScreen()),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class AssetManagementScreen extends StatelessWidget {
  final String type;
  const AssetManagementScreen({super.key, required this.type});

  void _showDistributeRentDialog(
    BuildContext context,
    String docId,
    int propertyId,
  ) {
    final TextEditingController _rentCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Distribute Rent'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter amount in MATIC to distribute to all fraction holders.',
            ),
            TextField(
              controller: _rentCtrl,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Amount (MATIC)',
                suffixText: 'MATIC',
              ),
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
              // 1. INPUT VALIDATION: Check numbers BEFORE blocking call
              final textAmount = _rentCtrl.text.trim().replaceAll(',', '');
              if (textAmount.isEmpty) return;

              final amountEth = double.tryParse(textAmount);
              if (amountEth == null || amountEth <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Invalid Amount: Please enter a number like 0.1 or 10',
                    ),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              Navigator.pop(ctx);

              try {
                final service = BlockchainServiceEnhanced();
                await service.init();

                if (!service.isConnected) {
                  await service.connectWallet(context);
                }

                if (!context.mounted) return;

                final amountWei = service.etherToWei(amountEth);

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Confirm transaction in wallet...'),
                  ),
                );

                await service.distributeLandRent(
                  propertyId: propertyId,
                  amount: amountWei,
                );

                if (!context.mounted) return;

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Rent Distributed Successfully!'),
                    backgroundColor: AppTheme.primaryStart,
                  ),
                );
              } catch (e) {
                if (context.mounted) {
                  // Display exact error from Blockchain Service
                  showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Error'),
                      content: Text(e.toString()),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  );
                }
              }
            },
            child: const Text('Distribute'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: db
          .collection('assets')
          .where('ownerId', isEqualTo: auth.currentUser!.uid)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Error loading assets:\n${snap.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red, fontSize: 13),
              ),
            ),
          );
        }
        if (!snap.hasData)
          return const Center(child: CircularProgressIndicator());
        // Client-side filter: only show assets listed for sale by this supplier
        final docs = snap.data!.docs.where((doc) {
          final d = doc.data() as Map<String, dynamic>;
          final category = (d['category'] ?? '').toString().toLowerCase();
          if (category != type.toLowerCase()) return false;

          // Only show assets the supplier has explicitly listed for sale
          if (d['isForSale'] != true) return false;

          // Ownership check
          if (d['ownerId'] != auth.currentUser!.uid) return false;

          return true;
        }).toList();
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryStart.withOpacity(0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    type == 'land'
                        ? Icons.landscape_rounded
                        : Icons.devices_rounded,
                    size: 48,
                    color: AppTheme.primaryStart,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'No assets yet',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Tap + Add Asset to mint your first NFT',
                  style: TextStyle(fontSize: 13, color: Colors.grey[400]),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, i) {
            final doc = docs[i];
            final data = doc.data() as Map<String, dynamic>;
            final rawTokenId = data['blockchainTokenId'];
            final tokenId = rawTokenId != null
                ? (rawTokenId is int
                      ? rawTokenId
                      : int.tryParse(rawTokenId.toString()))
                : null;
            final isMinted = tokenId != null;
            final title = data['title'] ?? 'Untitled';
            final price = data['price']?.toString() ?? '—';

            // Asset thumbnail image
            final images = data['images'] as List?;
            final hasImage = images != null && images.isNotEmpty;

            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey[200]!),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                    child: hasImage
                        ? Image.memory(
                            base64Decode(images.first as String),
                            width: double.infinity,
                            height: 160,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _imageFallback(type),
                          )
                        : _imageFallback(type),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: Colors.black87,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: isMinted
                                ? AppTheme.primaryStart.withOpacity(0.1)
                                : Colors.grey[100],
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isMinted
                                  ? AppTheme.primaryStart.withOpacity(0.3)
                                  : Colors.grey[300]!,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isMinted
                                    ? Icons.verified_rounded
                                    : Icons.edit_note_rounded,
                                size: 11,
                                color: isMinted
                                    ? AppTheme.primaryStart
                                    : Colors.grey[500],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isMinted ? 'NFT Minted' : 'Draft',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: isMinted
                                      ? AppTheme.primaryStart
                                      : Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
                    child: Row(
                      children: [
                        Icon(
                          Icons.payments_outlined,
                          size: 14,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'PKR $price',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                        if (isMinted) ...[
                          const Spacer(),
                          Text(
                            'Token #$tokenId',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[400],
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  Divider(height: 1, color: Colors.grey[100]),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    child: type == 'land' && isMinted
                        ? Column(
                            children: [
                              // Row 1: Distribute Rent (full width)
                              _actionButton(
                                icon: Icons.monetization_on_rounded,
                                label: 'Distribute Rent',
                                color: Colors.amber[700]!,
                                bgColor: Colors.amber[50]!,
                                onTap: () => _showDistributeRentDialog(
                                  context,
                                  doc.id,
                                  tokenId,
                                ),
                              ),
                              const SizedBox(height: 8),
                              // Row 2: QR Code + Edit
                              Row(
                                children: [
                                  Expanded(
                                    child: _actionButton(
                                      icon: Icons.qr_code_rounded,
                                      label: 'QR Code',
                                      color: AppTheme.primaryStart,
                                      bgColor: AppTheme.primaryStart
                                          .withOpacity(0.08),
                                      onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => QRGeneratorScreen(
                                            assetId: doc.id,
                                            category: type,
                                            blockchainTokenId: tokenId,
                                            title: data['title'] ?? 'Asset',
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _actionButton(
                                      icon: Icons.edit_rounded,
                                      label: 'Edit',
                                      color: Colors.indigo[600]!,
                                      bgColor: Colors.indigo[50]!,
                                      onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => EditAssetScreen(
                                            assetId: doc.id,
                                            type: type,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          )
                        : Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: _actionButton(
                                      icon: Icons.qr_code_rounded,
                                      label: 'QR Code',
                                      color: AppTheme.primaryStart,
                                      bgColor: AppTheme.primaryStart
                                          .withOpacity(0.08),
                                      onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => QRGeneratorScreen(
                                            assetId: doc.id,
                                            category: type,
                                            blockchainTokenId: tokenId,
                                            title: data['title'] ?? 'Asset',
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _actionButton(
                                      icon: Icons.edit_rounded,
                                      label: 'Edit',
                                      color: Colors.indigo[600]!,
                                      bgColor: Colors.indigo[50]!,
                                      onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => EditAssetScreen(
                                            assetId: doc.id,
                                            type: type,
                                          ),
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
            );
          },
        );
      },
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required Color bgColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _imageFallback(String type) {
    return Container(
      width: double.infinity,
      height: 160,
      color: AppTheme.primaryStart.withOpacity(0.06),
      child: Icon(
        type == 'land' ? Icons.landscape_rounded : Icons.devices_rounded,
        size: 48,
        color: AppTheme.primaryStart.withOpacity(0.35),
      ),
    );
  }
}

// ASSET FORM

class AssetForm extends StatefulWidget {
  final String type;
  final Map<String, dynamic>? initialData;
  final bool isEdit;
  final Future<void> Function(Map<String, dynamic> data) onSubmit;

  const AssetForm({
    super.key,
    required this.type,
    this.initialData,
    this.isEdit = false,
    required this.onSubmit,
  });

  @override
  State<AssetForm> createState() => _AssetFormState();
}

class _AssetFormState extends State<AssetForm> {
  final _formKey = GlobalKey<FormState>();
  final List<Uint8List> _images = [];
  List<Map<String, dynamic>> _documents = [];
  String _condition = 'new';
  String _plotUnit = 'marla';
  bool _uploadingDocuments = false;

  // PKR → POL live conversion
  double? _polRateInPkr; // price of 1 POL in PKR
  String _polDisplay = ''; // e.g. "≈ 0.23 POL"
  bool _isFetchingRate = true; // false once fetch succeeds or fails

  late final TextEditingController _titleCtrl = TextEditingController(
    text: widget.initialData?['title']?.toString() ?? '',
  );
  late final TextEditingController _descCtrl = TextEditingController(
    text: widget.initialData?['description']?.toString() ?? '',
  );
  late final TextEditingController _priceCtrl = TextEditingController(
    text: widget.initialData?['price']?.toString() ?? '',
  );
  late final TextEditingController _plotCtrl = TextEditingController(
    text: widget.initialData?['plotArea']?.toString() ?? '',
  );
  late final TextEditingController _cityCtrl = TextEditingController(
    text: widget.initialData?['city']?.toString() ?? '',
  );
  late final TextEditingController _brandCtrl = TextEditingController(
    text: widget.initialData?['brand']?.toString() ?? '',
  );
  late final TextEditingController _modelCtrl = TextEditingController(
    text: widget.initialData?['model']?.toString() ?? '',
  );
  late final TextEditingController _serialCtrl = TextEditingController(
    text: widget.initialData?['serial']?.toString() ?? '',
  );
  late final TextEditingController _warrantyCtrl = TextEditingController(
    text: widget.initialData?['warranty']?.toString() ?? '',
  );
  late final TextEditingController _fractionsCtrl = TextEditingController(
    text: widget.initialData?['totalFractions']?.toString() ?? '100',
  );

  @override
  void initState() {
    super.initState();
    _condition = widget.initialData?['condition']?.toString() ?? 'new';
    _plotUnit = widget.initialData?['plotUnit']?.toString() ?? 'marla';

    if (widget.initialData?['documents'] != null) {
      final docs = widget.initialData!['documents'] as List<dynamic>;
      _documents = docs.cast<Map<String, dynamic>>();
    }

    _fetchPolRate();
    _priceCtrl.addListener(_updatePolDisplay);
  }

  Future<void> _fetchPolRate() async {
    try {
      final polRes = await http
          .get(
            Uri.parse(
              'https://api.binance.com/api/v3/ticker/price?symbol=POLUSDT',
            ),
          )
          .timeout(const Duration(seconds: 8));

      final fxRes = await http
          .get(Uri.parse('https://open.er-api.com/v6/latest/USD'))
          .timeout(const Duration(seconds: 8));

      if (polRes.statusCode == 200 && fxRes.statusCode == 200) {
        final polUsd = double.parse(jsonDecode(polRes.body)['price'] as String);
        final pkrPerUsd = (jsonDecode(fxRes.body)['rates']['PKR'] as num)
            .toDouble();
        final rate = polUsd * pkrPerUsd;
        if (mounted) {
          setState(() {
            _polRateInPkr = rate;
            _isFetchingRate = false;
          });
          _updatePolDisplay();
        }
        return;
      }
    } catch (_) {}

    try {
      final res = await http
          .get(
            Uri.parse(
              'https://api.coingecko.com/api/v3/simple/price?ids=matic-network&vs_currencies=pkr',
            ),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final rate = (data['matic-network']['pkr'] as num).toDouble();
        if (mounted) {
          setState(() {
            _polRateInPkr = rate;
            _isFetchingRate = false;
          });
          _updatePolDisplay();
          return;
        }
      }
    } catch (_) {}

    if (mounted) setState(() => _isFetchingRate = false);
  }

  void _updatePolDisplay() {
    if (_polRateInPkr == null) return;
    final pkr = double.tryParse(_priceCtrl.text.replaceAll(',', ''));
    if (pkr != null && pkr > 0) {
      final pol = pkr / _polRateInPkr!;
      final formatted = pol < 0.001
          ? pol.toStringAsExponential(2)
          : pol.toStringAsFixed(4);
      if (mounted) setState(() => _polDisplay = '≈ $formatted POL');
    } else {
      if (mounted) setState(() => _polDisplay = '');
    }
  }

  @override
  void dispose() {
    _priceCtrl.removeListener(_updatePolDisplay);
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _plotCtrl.dispose();
    _cityCtrl.dispose();
    _brandCtrl.dispose();
    _modelCtrl.dispose();
    _serialCtrl.dispose();
    _warrantyCtrl.dispose();
    _fractionsCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage(imageQuality: 80);
    if (picked.isEmpty) return;
    for (final p in picked) {
      final b = await p.readAsBytes();
      setState(() => _images.add(b));
    }
  }

  Future<void> _takePhoto() async {
    final picker = ImagePicker();
    final XFile? photo = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 70,
      maxWidth: 800,
    );
    if (photo != null) {
      final bytes = await photo.readAsBytes();
      setState(() => _images.add(bytes));
    }
  }

  Future<void> _pickDocuments() async {
    setState(() => _uploadingDocuments = true);
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx'],
        allowMultiple: true,
        withData: true,
      );

      if (res != null) {
        for (final file in res.files) {
          if (file.bytes != null) {
            setState(() {
              _documents.add({
                'bytes': file.bytes!,
                'name': file.name,
                'type': file.extension ?? 'unknown',
                'size': file.size,
                'originalSize': file.size,
              });
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error: $e');
    } finally {
      setState(() => _uploadingDocuments = false);
    }
  }

  Future<Map<String, dynamic>?> _collect() async {
    final price = double.tryParse(_priceCtrl.text.replaceAll(',', ''));
    if (price == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invalid Price Format')));
      return null;
    }

    // 1. Process Images for Firestore
    final compressedImages = <String>[];
    for (final imgBytes in _images) {
      compressedImages.add(await compressImageToBase64(imgBytes));
    }

    // 2. Process Documents for Firestore
    final processedDocs = <Map<String, dynamic>>[];
    for (final doc in _documents) {
      if (doc.containsKey('bytes')) {
        final bytes = doc['bytes'] as Uint8List;
        final processed = await DocumentStorage.storeDocument(
          bytes,
          doc['name'],
          doc['type'],
        );
        processedDocs.add(processed);
      } else {
        processedDocs.add(doc);
      }
    }

    final Map<String, dynamic> out = {
      'title': _titleCtrl.text.trim(),
      'description': _descCtrl.text.trim(),
      'price': price,
      'images': compressedImages,
      'searchKeywords': _titleCtrl.text.trim().toLowerCase().split(
        RegExp(r'\s+'),
      ),
      'documents': processedDocs,
      'rawImages': _images,
      'rawDocuments': _documents.where((d) => d.containsKey('bytes')).toList(),
    };

    if (widget.type == 'land') {
      final area = int.tryParse(_plotCtrl.text.replaceAll(',', ''));
      final fracs = int.tryParse(_fractionsCtrl.text.replaceAll(',', ''));
      if (area == null || fracs == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid Plot Area or Fractions')),
        );
        return null;
      }
      out['plotArea'] = area; // Store as int
      out['plotUnit'] = _plotUnit;
      out['city'] = _cityCtrl.text.trim();
      out['totalFractions'] = fracs; // Store as int
    } else {
      final identifier = _serialCtrl.text.trim();
      out['brand'] = _brandCtrl.text.trim();
      out['model'] = _modelCtrl.text.trim();
      out['serial'] = identifier;
      out['serialNormalized'] = _normalizeDeviceIdentifier(identifier);
      out['identifierType'] = _validateImeiIdentifier(identifier)
          ? 'imei'
          : 'serial';
      out['warranty'] = _warrantyCtrl.text.trim();
      out['condition'] = _condition;
    }
    return out;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey[200]!),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: AppTheme.primaryStart),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppTheme.primaryStartDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: ctrl,
        keyboardType: keyboardType,
        maxLines: maxLines,
        validator: validator,
        style: const TextStyle(fontSize: 14, color: Colors.black87),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(fontSize: 13, color: Colors.grey[500]),
          prefixIcon: Icon(icon, size: 18, color: AppTheme.primaryStart),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          filled: true,
          fillColor: AppTheme.primaryLight,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey[200]!),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(
              color: AppTheme.primaryStart,
              width: 1.5,
            ),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.red),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.red, width: 1.5),
          ),
        ),
      ),
    );
  }

  InputDecoration _dropdownDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(fontSize: 13, color: Colors.grey[500]),
      prefixIcon: Icon(icon, size: 18, color: AppTheme.primaryStart),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      filled: true,
      fillColor: AppTheme.primaryLight,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey[200]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppTheme.primaryStart, width: 1.5),
      ),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isLand = widget.type == 'land';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Basic Info ──────────────────────────────────────────
            _sectionCard(
              title: 'Basic Information',
              icon: Icons.info_outline_rounded,
              child: Column(
                children: [
                  _field(
                    _titleCtrl,
                    'Title',
                    Icons.title_rounded,
                    validator: (v) => v!.trim().isEmpty ? 'Required' : null,
                  ),
                  _field(
                    _descCtrl,
                    'Description',
                    Icons.notes_rounded,
                    maxLines: 3,
                  ),
                  // Price field with live PKR→POL conversion
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextFormField(
                      controller: _priceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                      validator: (v) =>
                          double.tryParse(v?.replaceAll(',', '') ?? '') == null
                          ? 'Enter a valid price'
                          : null,
                      decoration: InputDecoration(
                        labelText: 'Price (PKR)',
                        labelStyle: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[500],
                        ),
                        prefixIcon: const Icon(
                          Icons.sell_outlined,
                          size: 18,
                          color: AppTheme.primaryStart,
                        ),
                        // Live POL conversion badge on the right
                        suffix: _polDisplay.isNotEmpty
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryStart.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: AppTheme.primaryStart.withOpacity(
                                      0.25,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  _polDisplay,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.primaryStart,
                                  ),
                                ),
                              )
                            : _isFetchingRate
                            ? const SizedBox(
                                width: 10,
                                height: 10,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: AppTheme.primaryStart,
                                ),
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        filled: true,
                        fillColor: AppTheme.primaryLight,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey[200]!),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: AppTheme.primaryStart,
                            width: 1.5,
                          ),
                        ),
                        errorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Colors.red),
                        ),
                        focusedErrorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: Colors.red,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ── Land / Electronics fields ───────────────────────────
            if (isLand) ...[
              _sectionCard(
                title: 'Land Details',
                icon: Icons.landscape_rounded,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: DropdownButtonFormField<String>(
                        value: _plotUnit,
                        items: const [
                          DropdownMenuItem(
                            value: 'marla',
                            child: Text('Marla'),
                          ),
                          DropdownMenuItem(
                            value: 'kanal',
                            child: Text('Kanal'),
                          ),
                        ],
                        onChanged: (v) => setState(() => _plotUnit = v!),
                        decoration: _dropdownDecoration(
                          'Plot Unit',
                          Icons.straighten_rounded,
                        ),
                      ),
                    ),
                    _field(
                      _plotCtrl,
                      'Plot Area (Integer)',
                      Icons.crop_square_rounded,
                      keyboardType: TextInputType.number,
                    ),
                    _field(
                      _cityCtrl,
                      'City / Address',
                      Icons.location_on_outlined,
                    ),
                    _field(
                      _fractionsCtrl,
                      'Total Fractions (Default 100)',
                      Icons.pie_chart_outline_rounded,
                      keyboardType: TextInputType.number,
                    ),
                  ],
                ),
              ),
            ] else ...[
              _sectionCard(
                title: 'Device Details',
                icon: Icons.devices_rounded,
                child: Column(
                  children: [
                    _field(_brandCtrl, 'Brand', Icons.business_rounded),
                    _field(_modelCtrl, 'Model', Icons.smartphone_rounded),
                    _field(
                      _serialCtrl,
                      'IMEI Number',
                      Icons.fingerprint_rounded,
                      keyboardType:
                          TextInputType.number, // Enforces numeric keyboard
                      validator: (v) {
                        final value = v?.trim() ?? '';
                        if (value.isEmpty) {
                          return '15-digit IMEI Number is required';
                        }
                        if (!_validateImeiIdentifier(value)) {
                          return 'Enter a valid 15-digit IMEI passing Luhn verification';
                        }
                        return null;
                      },
                    ),
                    _field(
                      _warrantyCtrl,
                      'Warranty (Date/Months)',
                      Icons.verified_user_outlined,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: DropdownButtonFormField<String>(
                        value: _condition,
                        items: const [
                          DropdownMenuItem(value: 'new', child: Text('New')),
                          DropdownMenuItem(value: 'used', child: Text('Used')),
                        ],
                        onChanged: (v) => setState(() => _condition = v!),
                        decoration: _dropdownDecoration(
                          'Condition',
                          Icons.star_outline_rounded,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),

            // ── Images ──────────────────────────────────────────────
            _sectionCard(
              title: 'Images',
              icon: Icons.photo_library_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_images.isNotEmpty) ...[
                    SizedBox(
                      height: 100,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _images.length,
                        itemBuilder: (_, i) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.memory(
                                  _images[i],
                                  width: 100,
                                  height: 100,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: GestureDetector(
                                  onTap: () =>
                                      setState(() => _images.removeAt(i)),
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      color: Colors.black54,
                                      shape: BoxShape.circle,
                                    ),
                                    padding: const EdgeInsets.all(3),
                                    child: const Icon(
                                      Icons.close,
                                      color: Colors.white,
                                      size: 14,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickImages,
                          icon: const Icon(
                            Icons.photo_library_outlined,
                            size: 18,
                          ),
                          label: const Text('Gallery'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.primaryStart,
                            side: const BorderSide(
                              color: AppTheme.primaryStart,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _takePhoto,
                          icon: const Icon(Icons.camera_alt_outlined, size: 18),
                          label: const Text('Camera'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.primaryStart,
                            side: const BorderSide(
                              color: AppTheme.primaryStart,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ── Documents ───────────────────────────────────────────
            _sectionCard(
              title: widget.type == 'land'
                  ? 'Documents (Required for Land) *'
                  : 'Documents (IPFS & Secure Storage)',
              icon: Icons.folder_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_documents.isEmpty)
                    Text(
                      'No documents attached.',
                      style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                    ),
                  ..._documents.map(
                    (d) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.insert_drive_file,
                            size: 18,
                            color: AppTheme.primaryStart,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  d['name'] ?? 'Document',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  _formatFileSize(d['size'] ?? 0),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey[500],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          GestureDetector(
                            onTap: () => setState(() => _documents.remove(d)),
                            child: const Icon(
                              Icons.close,
                              size: 16,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _uploadingDocuments ? null : _pickDocuments,
                      icon: _uploadingDocuments
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.primaryStart,
                              ),
                            )
                          : const Icon(Icons.attach_file, size: 18),
                      label: Text(
                        _uploadingDocuments
                            ? 'Uploading...'
                            : 'Attach Documents',
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primaryStart,
                        side: const BorderSide(color: AppTheme.primaryStart),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Submit Button ───────────────────────────────────────
            Container(
              height: 54,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.primaryStartDark, AppTheme.primaryStart],
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryStart.withOpacity(0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () async {
                    if (_formKey.currentState!.validate()) {
                      // CRITICAL FIX: Block land creation if no documents are attached
                      if (widget.type == 'land' && _documents.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Please upload at least one document for the land asset.',
                            ),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      final payload = await _collect();
                      if (payload != null) await widget.onSubmit(payload);
                    }
                  },
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          widget.isEdit
                              ? Icons.save_outlined
                              : Icons.rocket_launch_outlined,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          widget.isEdit
                              ? 'Save Changes'
                              : 'Mint NFT & Upload to IPFS',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// ADD ASSET SCREEN (Logic Wrapper: Firestore + IPFS + Blockchain)

class AddAssetScreen extends StatefulWidget {
  final String type;
  const AddAssetScreen({super.key, required this.type});

  @override
  State<AddAssetScreen> createState() => _AddAssetScreenState();
}

class _AddAssetScreenState extends State<AddAssetScreen> {
  bool _isLoading = false;
  String _statusMessage = '';

  Future<String?> _reserveElectronicsIdentifier(
    Map<String, dynamic> data,
  ) async {
    if (widget.type != 'electronics') return null;

    final rawIdentifier = (data['serial'] as String? ?? '').trim();
    final normalizedIdentifier = (data['serialNormalized'] as String? ?? '')
        .trim();

    if (rawIdentifier.isEmpty || normalizedIdentifier.isEmpty) {
      throw Exception('Serial / IMEI is required for electronics assets.');
    }

    final existingAssets = await db
        .collection('assets')
        .where('category', isEqualTo: 'electronics')
        .get();

    for (final doc in existingAssets.docs) {
      final existing = doc.data();
      final existingNormalizedField =
          existing['serialNormalized']?.toString().trim() ?? '';
      final existingNormalized = existingNormalizedField.isNotEmpty
          ? existingNormalizedField.toUpperCase()
          : _normalizeDeviceIdentifier(
              (existing['serial'] ??
                      existing['imei'] ??
                      existing['serialNumber'] ??
                      '')
                  .toString(),
            );

      if (existingNormalized != normalizedIdentifier) continue;

      final sameSupplier = existing['supplierId'] == auth.currentUser!.uid;
      throw Exception(
        sameSupplier
            ? 'This Serial / IMEI is already registered in your inventory.'
            : 'This Serial / IMEI is already registered by another supplier.',
      );
    }

    final ref = db.collection('asset_identifiers').doc(normalizedIdentifier);
    await db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (snap.exists) {
        final existing = snap.data() as Map<String, dynamic>? ?? {};
        final sameSupplier = existing['supplierId'] == auth.currentUser!.uid;
        final hasAssetId =
            (existing['assetId']?.toString().trim().isNotEmpty ?? false);

        if (!sameSupplier || hasAssetId) {
          throw Exception(
            sameSupplier
                ? 'This Serial / IMEI is already registered in your inventory.'
                : 'This Serial / IMEI is already registered by another supplier.',
          );
        }
      }

      tx.set(ref, {
        'rawValue': rawIdentifier,
        'normalizedValue': normalizedIdentifier,
        'identifierType': data['identifierType'],
        'category': 'electronics',
        'supplierId': auth.currentUser!.uid,
        'status': 'reserved',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });

    return normalizedIdentifier;
  }

  Future<void> _ensureWalletBelongsToCreator({
    required String creatorUid,
    required String walletAddress,
  }) async {
    await SimpleWalletService().linkWalletToUser(
      uid: creatorUid,
      walletAddress: walletAddress,
      conflictMessage:
          'This MetaMask wallet is already linked to another account. Connect the wallet linked to this supplier account before adding an asset.',
    );
  }

  Future<void> _handleCreate(Map<String, dynamic> data) async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Initializing...';
    });

    String? reservedIdentifier;
    bool assetSaved = false;
    bool identifierConfirmedOnChain = false;
    String? blockchainTxHash;

    try {
      final creatorUid = auth.currentUser?.uid;
      if (creatorUid == null) {
        throw Exception('You must be logged in to add an asset.');
      }

      reservedIdentifier = await _reserveElectronicsIdentifier(data);

      final blockchain = BlockchainServiceEnhanced();
      // Initialize services
      await blockchain.init();
      final ipfs = IPFSService();

      // WALLET CONNECTION
      if (!blockchain.isConnected) {
        setState(() => _statusMessage = 'Waiting for Wallet Connection...');
        // This opens MetaMask. When you return, it waits up to 30s for the address.
        await blockchain.connectWallet(context);
      }
      if (!mounted) return;
      if (!blockchain.isConnected) {
        throw Exception(
          'Wallet connection failed or timed out. Please make sure you are on the Amoy Testnet.',
        );
      }

      final creatorWalletAddress = blockchain.connectedAddress!;
      await _ensureWalletBelongsToCreator(
        creatorUid: creatorUid,
        walletAddress: creatorWalletAddress,
      );

      //  UPLOAD IMAGE TO IPFS (Optimized)
      String? imageHash;
      if (data['rawImages'] != null && (data['rawImages'] as List).isNotEmpty) {
        setState(() => _statusMessage = 'Compressing & Uploading Image...');

        // Compress image before upload to prevent infinite loading on large files
        final rawBytes = (data['rawImages'] as List)[0] as Uint8List;
        final compressedBase64 = await compressImageToBase64(
          rawBytes,
          quality: 60,
        );
        final compressedBytes = base64Decode(compressedBase64);

        final res = await ipfs.uploadFile(
          fileBytes: compressedBytes,
          fileName: 'nft_image.jpg',
        );

        if (!res.success) throw Exception('Image Upload Failed: ${res.error}');
        imageHash = res.ipfsHash;
      }

      if (!mounted) return;

      //  UPLOAD DOCUMENTS
      String? primaryDocHash;
      if (data['rawDocuments'] != null) {
        setState(() => _statusMessage = 'Uploading Documents to IPFS...');
        final rawDocs = data['rawDocuments'] as List<Map<String, dynamic>>;

        for (var doc in rawDocs) {
          final res = await ipfs.uploadFile(
            fileBytes: doc['bytes'],
            fileName: doc['name'],
          );
          if (res.success) {
            primaryDocHash ??= res.ipfsHash;
            // Update the firestore data structure with IPFS links
            final fsDocs = data['documents'] as List<Map<String, dynamic>>;
            final match = fsDocs.firstWhere(
              (d) => d['name'] == doc['name'],
              orElse: () => {},
            );
            if (match.isNotEmpty) {
              match['ipfsHash'] = res.ipfsHash;
              match['ipfsUrl'] = res.ipfsUrl;
            }
          }
        }
      }

      if (!mounted) return;

      //  PREPARE METADATA
      setState(() => _statusMessage = 'Generating Metadata...');
      Map<String, dynamic> metadata;

      final safeTitle = data['title']?.toString() ?? 'Asset';
      final safeCity = data['city']?.toString() ?? 'Unknown';

      if (widget.type == 'electronics') {
        metadata = ipfs.createElectronicsMetadata(
          brand: data['brand'] ?? 'Unknown',
          model: data['model'] ?? 'Unknown',
          serialNumber: data['serial'] ?? 'Unknown',
          warrantyExpiry: data['warranty'] ?? 'Unknown',
          condition: data['condition'] ?? 'New',
          imageHash: imageHash,
          warrantyDocHash: primaryDocHash,
        );
      } else {
        final plotAreaInt = data['plotArea'] as int? ?? 0;
        final totalFractionsInt = data['totalFractions'] as int? ?? 100;
        final priceDouble = data['price'] as double? ?? 0.0;

        metadata = ipfs.createLandMetadata(
          location: safeTitle,
          city: safeCity,
          totalArea: plotAreaInt,
          areaUnit: data['plotUnit'] ?? 'marla',
          totalFractions: totalFractionsInt,
          pricePerFraction: priceDouble.toString(),
          imageHash: imageHash,
          deedHash: primaryDocHash,
        );
      }

      //  UPLOAD METADATA
      setState(() => _statusMessage = 'Uploading Metadata to IPFS...');
      final metaRes = await ipfs.uploadJSON(
        jsonData: metadata,
        name: '${safeTitle}_metadata',
      );
      if (!metaRes.success) throw Exception('Metadata Upload Failed');
      final metadataHash = metaRes.ipfsHash!;

      if (!mounted) return;

      // MINT ON BLOCKCHAIN
      setState(
        () => _statusMessage = 'Please Confirm Transaction in Wallet...',
      );
      String? txHash;

      if (widget.type == 'electronics') {
        txHash = await blockchain.mintElectronics(
          toAddress: creatorWalletAddress,
          serialNumber: data['serial'] ?? '000',
          brand: data['brand'] ?? 'Unknown',
          model: data['model'] ?? 'Unknown',
          warrantyExpiry: data['warranty'] ?? 'Unknown',
          tokenURI: 'ipfs://$metadataHash',
        );
      } else {
        final plotAreaInt = data['plotArea'] as int? ?? 0;
        final totalFractionsInt = data['totalFractions'] as int? ?? 100;
        final priceDouble = data['price'] as double? ?? 0.0;

        txHash = await blockchain.createLandProperty(
          location: safeTitle,
          city: safeCity,
          totalArea: plotAreaInt,
          areaUnit: data['plotUnit'] ?? 'marla',
          totalFractions: totalFractionsInt,
          pricePerFraction: blockchain.etherToWei(priceDouble),
          ipfsMetadata: 'ipfs://$metadataHash',
        );
      }
      // SAVE TO DATABASE

      if (txHash == null) throw Exception('Transaction failed or rejected');
      blockchainTxHash = txHash;
      setState(() => _statusMessage = 'Waiting for blockchain confirmation...');

      // Wait for the transaction to be mined (up to ~60 seconds)
      final confirmed = await blockchain.waitForConfirmation(
        txHash,
        retries: 30,
      );
      if (!confirmed) {
        throw Exception(
          'Mint transaction was not confirmed on-chain. Please check MetaMask activity before trying again.',
        );
      }
      identifierConfirmedOnChain = true;

      // Query the contract to get the newly minted token ID
      setState(() => _statusMessage = 'Retrieving Token ID...');
      int? newTokenId;
      newTokenId = await blockchain.getMintedAssetIdFromReceipt(
        type: widget.type,
        txHash: txHash,
      );
      newTokenId ??= widget.type == 'electronics'
          ? await blockchain.getLastElectronicsTokenId()
          : await blockchain.getLastLandPropertyId();
      debugPrint('✅ New blockchain Token ID: $newTokenId');

      if (newTokenId == null) {
        throw Exception(
          'Could not read the minted token ID from the blockchain receipt.',
        );
      }

      final chainOwner = await blockchain.getOwnerOf(widget.type, newTokenId);
      if (chainOwner == null ||
          chainOwner.toLowerCase() != creatorWalletAddress.toLowerCase()) {
        throw Exception(
          'The minted blockchain asset owner did not match your connected MetaMask wallet. '
          'Please try again before saving this asset.',
        );
      }

      setState(() => _statusMessage = 'Saving to Database...');

      data.remove('rawImages');
      data.remove('rawDocuments');

      final assetRef = db.collection('assets').doc();
      await assetRef.set({
        ...data,
        'category': widget.type,
        'ownerId': creatorUid,
        'ownerUid': creatorUid,
        'supplierId': creatorUid,
        'createdBy': creatorUid,
        'currentOwnerAddress': creatorWalletAddress,
        'originalOwnerAddress': creatorWalletAddress,
        'blockchainTx': txHash,
        'blockchainTokenId': newTokenId, // ← now correctly saved
        'ipfsMetadataHash': metadataHash,
        'isMinted': true,
        'isForSale':
            false, // ← supplier must explicitly list for sale from inventory
        'verified': false, // ← pending admin approval
        'isListedForResale': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      assetSaved = true;

      if (reservedIdentifier != null) {
        await db.collection('asset_identifiers').doc(reservedIdentifier).set({
          'assetId': assetRef.id,
          'blockchainTokenId': newTokenId,
          'status': 'active',
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Success! Asset Minted & Uploaded.'),
          backgroundColor: AppTheme.primaryStart,
        ),
      );
      await addTransaction(
        userId: creatorUid,
        type: "nft",
        title: data['title'] ?? "Asset",
        toAddress: "self",
      );
      Navigator.pop(context);
    } catch (e) {
      if (reservedIdentifier != null && !assetSaved) {
        try {
          final identifierRef = db
              .collection('asset_identifiers')
              .doc(reservedIdentifier);

          if (identifierConfirmedOnChain) {
            await identifierRef.set({
              'status': 'pending_asset_sync',
              'blockchainTx': blockchainTxHash,
              'lastError': _friendlyErrorText(e),
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          } else {
            await identifierRef.delete();
          }
        } catch (cleanupError) {
          debugPrint('Identifier cleanup failed: $cleanupError');
        }
      }

      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Error'),
            content: Text(_friendlyErrorText(e)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: context.appScaffold,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: const SizedBox(),
          title: Text(
            'Add ${widget.type.capitalize()}',
            style: TextStyle(
              color: context.appTextPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          centerTitle: true,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryStart.withOpacity(0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const CircularProgressIndicator(
                    color: AppTheme.primaryStart,
                    strokeWidth: 3,
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  _statusMessage,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: context.appTextPrimary,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  'Please do not close this screen',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.appTextSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: context.appScaffold,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, size: 28),
          color: Colors.black87,
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Add ${widget.type.capitalize()}',
          style: const TextStyle(
            color: Colors.black87,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: AssetForm(type: widget.type, onSubmit: _handleCreate),
    );
  }
}
// EDIT SCREEN

class EditAssetScreen extends StatefulWidget {
  final String assetId;
  final String type;
  const EditAssetScreen({super.key, required this.assetId, required this.type});

  @override
  State<EditAssetScreen> createState() => _EditAssetScreenState();
}

class _EditAssetScreenState extends State<EditAssetScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _saving = false;

  // Editable off-chain controllers
  late TextEditingController _priceCtrl;
  late TextEditingController _descCtrl;
  List<Map<String, dynamic>> _documents = [];
  final List<Uint8List> _newImages = [];

  @override
  void initState() {
    super.initState();
    _priceCtrl = TextEditingController();
    _descCtrl = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final doc = await db.collection('assets').doc(widget.assetId).get();
      if (doc.exists) {
        final d = doc.data()!;
        setState(() {
          _data = d;
          _priceCtrl.text = d['price']?.toString() ?? '';
          _descCtrl.text = d['description']?.toString() ?? '';
          if (d['documents'] != null) {
            _documents = (d['documents'] as List).cast<Map<String, dynamic>>();
          }
        });
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _pickNewImages() async {
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage(imageQuality: 80);
    for (final p in picked) {
      final b = await p.readAsBytes();
      setState(() => _newImages.add(b));
    }
  }

  Future<void> _pickDocuments() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx'],
      allowMultiple: true,
      withData: true,
    );
    if (res != null) {
      for (final file in res.files) {
        if (file.bytes != null) {
          setState(() {
            _documents.add({
              'bytes': file.bytes!,
              'name': file.name,
              'type': file.extension ?? 'unknown',
              'size': file.size,
            });
          });
        }
      }
    }
  }

  Future<void> _save() async {
    final price = double.tryParse(_priceCtrl.text.replaceAll(',', ''));
    if (price == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invalid price format')));
      return;
    }

    final category = (_data?['category'] ?? widget.type).toString();

    setState(() => _saving = true);
    try {
      // Process any new images
      final List<String> existingImages =
          (_data?['images'] as List?)?.cast<String>() ?? [];
      for (final bytes in _newImages) {
        existingImages.add(await compressImageToBase64(bytes));
      }

      // Process documents
      final processedDocs = <Map<String, dynamic>>[];
      for (final doc in _documents) {
        if (doc.containsKey('bytes')) {
          final processed = await DocumentStorage.storeDocument(
            doc['bytes'],
            doc['name'],
            doc['type'],
          );
          processedDocs.add(processed);
        } else {
          processedDocs.add(doc);
        }
      }

      // Block land editing updates if documents are completely cleared
      if (category.toLowerCase() == 'land' && processedDocs.isEmpty) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Please upload at least one document for the land asset.',
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Only update off-chain fields — never touch blockchain-origin fields
      await db.collection('assets').doc(widget.assetId).update({
        'price': price,
        'description': _descCtrl.text.trim(),
        'images': existingImages,
        'documents': processedDocs,
        'lastEditedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Asset updated successfully'),
            backgroundColor: AppTheme.primaryStart,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _lockedField(String label, String? value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.primaryLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: AppTheme.primaryStart),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[500],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value?.isNotEmpty == true ? value! : '—',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.lock_outline, size: 14, color: Colors.grey),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required Widget child,
    Color? titleColor,
    IconData? icon,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey[200]!),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 16,
                    color: titleColor ?? AppTheme.primaryStart,
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: titleColor ?? AppTheme.primaryStartDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.chevron_left, size: 28),
            color: Colors.black87,
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text(
            'Edit Asset',
            style: TextStyle(
              color: Colors.black87,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          centerTitle: true,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final d = _data ?? {};
    final isMinted = d['blockchainTokenId'] != null;
    final title = d['title']?.toString() ?? 'Asset';
    final category = (d['category'] ?? widget.type).toString();

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: AppTheme.background,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.chevron_left, size: 28),
              color: Colors.black87,
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text(
              'Edit Asset',
              style: TextStyle(
                color: Colors.black87,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            centerTitle: true,
            expandedHeight: 120,
            flexibleSpace: FlexibleSpaceBar(
              background: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 60, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.black87,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.grey[300]!),
                            ),
                            child: Text(
                              category.toUpperCase(),
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (isMinted) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryStart.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: AppTheme.primaryStart.withOpacity(0.3),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.verified_rounded,
                                    color: AppTheme.primaryStart,
                                    size: 10,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Token #${d['blockchainTokenId']}',
                                    style: const TextStyle(
                                      color: AppTheme.primaryStart,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            ),
            iconTheme: const IconThemeData(color: Colors.black87),
          ),

          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Blockchain locked section
                if (isMinted) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.amber[50]!, Colors.orange[50]!],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber[200]!),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Colors.orange[700],
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            '🔒 Fields below are recorded on the blockchain and are permanently immutable.',
                            style: TextStyle(fontSize: 12, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),

                  _sectionCard(
                    title: 'Blockchain Record',
                    icon: Icons.link,
                    child: Column(
                      children: widget.type == 'electronics'
                          ? [
                              _lockedField(
                                'Brand',
                                d['brand']?.toString(),
                                Icons.business_outlined,
                              ),
                              _lockedField(
                                'Model',
                                d['model']?.toString(),
                                Icons.phone_android_outlined,
                              ),
                              _lockedField(
                                'Serial / IMEI',
                                d['serial']?.toString(),
                                Icons.tag_outlined,
                              ),
                              _lockedField(
                                'Warranty',
                                d['warranty']?.toString(),
                                Icons.shield_outlined,
                              ),
                              _lockedField(
                                'Condition',
                                d['condition']?.toString(),
                                Icons.star_outline,
                              ),
                            ]
                          : [
                              _lockedField(
                                'Location / Title',
                                d['title']?.toString(),
                                Icons.location_on_outlined,
                              ),
                              _lockedField(
                                'City',
                                d['city']?.toString(),
                                Icons.location_city_outlined,
                              ),
                              _lockedField(
                                'Plot Area',
                                '${d['plotArea']} ${d['plotUnit'] ?? ''}'
                                    .trim(),
                                Icons.square_foot_outlined,
                              ),
                              _lockedField(
                                'Total Fractions',
                                d['totalFractions']?.toString(),
                                Icons.pie_chart_outline,
                              ),
                            ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Editable fields
                _sectionCard(
                  title: 'Editable Details',
                  icon: Icons.edit_outlined,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _priceCtrl,
                        decoration: InputDecoration(
                          labelText: 'Price (PKR)',
                          filled: true,
                          fillColor: AppTheme.background,
                          prefixIcon: const Icon(
                            Icons.monetization_on_outlined,
                            color: AppTheme.primaryStart,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _descCtrl,
                        decoration: InputDecoration(
                          labelText: 'Description',
                          alignLabelWithHint: true,
                          filled: true,
                          fillColor: AppTheme.background,
                          prefixIcon: const Icon(
                            Icons.description_outlined,
                            color: AppTheme.primaryStart,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                        ),
                        maxLines: 4,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                _sectionCard(
                  title: 'Images',
                  icon: Icons.image_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Existing images
                      if ((d['images'] as List?)?.isNotEmpty == true)
                        SizedBox(
                          height: 100,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: (d['images'] as List).length,
                            itemBuilder: (_, i) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.memory(
                                  base64Decode((d['images'] as List)[i]),
                                  width: 100,
                                  height: 100,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ),
                        ),
                      // New images with delete
                      if (_newImages.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'New images:',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 100,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: _newImages.length,
                            itemBuilder: (_, i) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Image.memory(
                                      _newImages[i],
                                      width: 100,
                                      height: 100,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: GestureDetector(
                                      onTap: () => setState(
                                        () => _newImages.removeAt(i),
                                      ),
                                      child: Container(
                                        decoration: const BoxDecoration(
                                          color: Colors.black54,
                                          shape: BoxShape.circle,
                                        ),
                                        padding: const EdgeInsets.all(3),
                                        child: const Icon(
                                          Icons.close,
                                          color: Colors.white,
                                          size: 14,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _pickNewImages,
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        label: const Text('Add Images'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primaryStart,
                          side: const BorderSide(color: AppTheme.primaryStart),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                _sectionCard(
                  title: 'Documents',
                  icon: Icons.folder_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_documents.isEmpty)
                        Text(
                          'No documents attached.',
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 13,
                          ),
                        ),
                      ..._documents.map(
                        (doc) => Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryLight,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.insert_drive_file,
                                size: 18,
                                color: AppTheme.primaryStart,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  doc['name'] ?? 'Document',
                                  style: const TextStyle(fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              GestureDetector(
                                onTap: () =>
                                    setState(() => _documents.remove(doc)),
                                child: const Icon(
                                  Icons.close,
                                  size: 16,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _pickDocuments,
                        icon: const Icon(Icons.attach_file),
                        label: const Text('Attach Documents'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primaryStart,
                          side: const BorderSide(color: AppTheme.primaryStart),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                Container(
                  height: 54,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: _saving
                          ? [Colors.grey[400]!, Colors.grey[400]!]
                          : [AppTheme.primaryStartDark, AppTheme.primaryStart],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: _saving
                        ? []
                        : [
                            BoxShadow(
                              color: AppTheme.primaryStart.withOpacity(0.35),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _saving ? null : _save,
                      child: Center(
                        child: _saving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.save_outlined,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  SizedBox(width: 10),
                                  Text(
                                    'Save Changes',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
