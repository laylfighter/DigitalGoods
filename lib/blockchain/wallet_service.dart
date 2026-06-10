// ═══════════════════════════════════════════════════════════
// 1. SIMPLE WALLET SERVICE (Standard Modal + Signing Support)
// Place in: lib/blockchain/simple_wallet_service.dart
// ═══════════════════════════════════════════════════════════

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:reown_appkit/reown_appkit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'contract_config.dart';

class SimpleWalletService {
  static final SimpleWalletService _instance = SimpleWalletService._internal();
  factory SimpleWalletService() => _instance;
  SimpleWalletService._internal();

  late ReownAppKitModal _modal;
  bool _initialized = false;
  String? _address;

  // Getters
  bool get isConnected => _address != null;
  String? get address => _address;
  // ✅ Expose modal for BlockchainService to sign transactions
  ReownAppKitModal get appKitModal => _modal;
  bool get isInitialized => _initialized;

  // 💰 Balance & Escrow Management (Demo Implementation)
  static const double _initialAvailableBalance = 10.0;
  double _availableBalance = _initialAvailableBalance; // Initial test balance
  double _lockedBalance = 0.0;

  double get availableBalance => _availableBalance;
  double get lockedBalance => _lockedBalance;

  /// Moves funds from available to locked (Escrow)
  Future<void> lockFunds(double amount) async {
    if (_availableBalance < amount) {
      throw Exception('Insufficient funds in wallet for escrow.');
    }
    _availableBalance -= amount;
    _lockedBalance += amount;
    debugPrint('🔒 Funds Locked: $amount. New Locked: $_lockedBalance');
  }

  /// Moves funds from locked back to available (Refund)
  Future<void> unlockFunds(double amount) async {
    if (_lockedBalance < amount) {
      throw Exception('Insufficient locked funds.');
    }
    _lockedBalance -= amount;
    _availableBalance += amount;
    debugPrint('🔓 Funds Unlocked: $amount. New Available: $_availableBalance');
  }

  /// Permanently removes funds from locked (Payment completion)
  Future<void> consumeLockedFunds(double amount) async {
    if (_lockedBalance < amount) {
      throw Exception('Insufficient locked funds.');
    }
    _lockedBalance -= amount;
    debugPrint('💸 Funds Consumed: $amount. Remaining Locked: $_lockedBalance');
  }

  Future<void> init(BuildContext context) async {
    if (_initialized) return;

    final amoy = ReownAppKitModalNetworkInfo(
      name: 'Polygon Amoy',
      chainId: '80002',
      currency: 'MATIC',
      rpcUrl: ContractConfig.rpcUrl,
      explorerUrl: 'https://amoy.polygonscan.com',
      isTestNetwork: true,
    );

    ReownAppKitModalNetworks.addSupportedNetworks('eip155', [amoy]);

    _modal = ReownAppKitModal(
      context: context,
      projectId: '8f60adc0059124b9d8a76eedb8777bdb',
      metadata: const PairingMetadata(
        name: 'DigitalGoods',
        description: 'FYP NFT Marketplace',
        url: 'https://digitalgoods.app',
        icons: ['https://digitalgoods.app/icon.png'],
        redirect: Redirect(
          native: 'digital goods://',
          universal: 'https://digitalgoods.app/link',
        ),
      ),
      requiredNamespaces: {
        'eip155': RequiredNamespace(
          chains: ['eip155:80002'],
          methods: [
            'eth_sendTransaction',
            'personal_sign',
            'eth_signTypedData_v4',
          ],
          events: ['accountsChanged', 'chainChanged'],
        ),
      },
    );

    await _modal.init();

    // Listen for session changes
    _modal.addListener(_onConnectionChanged);

    if (_modal.isConnected) {
      _extractAddress();
    }

    _initialized = true;
  }

  /// 🔹 OPEN STANDARD WALLET MODAL
  Future<String?> connect(BuildContext context) async {
    await init(context);

    if (isConnected && _modal.isConnected) return _address;
    if (isConnected && !_modal.isConnected) {
      _resetInMemoryState();
    }

    // This opens the official QR/List modal
    await _modal.openModalView();

    return await _waitForConnection();
  }

  Future<void> disconnect() async {
    if (_initialized && _modal.isConnected) {
      await _modal.disconnect();
    }
    await resetSession(disconnectWallet: false);
  }

  Future<void> resetSession({bool disconnectWallet = true}) async {
    if (disconnectWallet && _initialized && _modal.isConnected) {
      try {
        await _modal.disconnect();
      } catch (e) {
        debugPrint('Wallet disconnect during reset failed: $e');
      }
    }
    _resetInMemoryState();
    await _clearSavedAddress();
  }

  Future<void> ensureWalletCanBeLinked({
    required String uid,
    required String walletAddress,
    String conflictMessage =
        'This MetaMask wallet is already linked to another account.',
  }) async {
    final normalizedAddress = walletAddress.trim();
    final normalizedAddressLower = normalizedAddress.toLowerCase();
    if (normalizedAddress.isEmpty) {
      throw Exception('Wallet address is missing. Please reconnect MetaMask.');
    }

    final linkedUsers = await Future.wait([
      FirebaseFirestore.instance
          .collection('users')
          .where('walletAddress', isEqualTo: normalizedAddress)
          .limit(2)
          .get(),
      FirebaseFirestore.instance
          .collection('users')
          .where('walletAddressLower', isEqualTo: normalizedAddressLower)
          .limit(2)
          .get(),
    ]);

    for (final snap in linkedUsers) {
      for (final doc in snap.docs) {
        if (doc.id != uid) throw Exception(conflictMessage);
      }
    }
  }

  Future<void> linkWalletToUser({
    required String uid,
    required String walletAddress,
    String conflictMessage =
        'This MetaMask wallet is already linked to another account.',
  }) async {
    final normalizedAddress = walletAddress.trim();
    final normalizedAddressLower = normalizedAddress.toLowerCase();

    await ensureWalletCanBeLinked(
      uid: uid,
      walletAddress: normalizedAddress,
      conflictMessage: conflictMessage,
    );

    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
    final doc = await userRef.get();
    final oldAddress = doc.data()?['walletAddress'] as String?;

    await userRef.set({
      'walletAddress': normalizedAddress,
      'walletAddressLower': normalizedAddressLower,
      'walletLinkedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (oldAddress != null &&
        oldAddress.toLowerCase() != normalizedAddressLower) {
      await userRef.collection('walletHistory').add({
        'oldWallet': oldAddress,
        'newWallet': normalizedAddress,
        'changedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  // Helper to handle session updates
  void _onConnectionChanged() {
    if (_modal.isConnected) {
      _extractAddress();
    } else {
      _resetInMemoryState();
      unawaited(_clearSavedAddress());
    }
  }

  void _extractAddress() async {
    final session = _modal.session;
    if (session == null) {
      _resetInMemoryState();
      return;
    }

    final accounts = session.namespaces?['eip155']?.accounts;
    if (accounts == null || accounts.isEmpty) {
      _resetInMemoryState();
      return;
    }

    _address = accounts.first.split(':').last;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('wallet_address', _address!);
  }

  void _resetInMemoryState() {
    _address = null;
    _availableBalance = _initialAvailableBalance;
    _lockedBalance = 0.0;
  }

  Future<void> _clearSavedAddress() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('wallet_address');
  }

  Future<String?> _waitForConnection() async {
    for (int i = 0; i < 30; i++) {
      if (isConnected && _modal.isConnected) return _address;
      if (isConnected && !_modal.isConnected) _resetInMemoryState();
      await Future.delayed(const Duration(seconds: 1));
    }
    return null;
  }
}

// ═══════════════════════════════════════════════════════════
// UI HELPER: BUTTON & STATUS WIDGET
// ═══════════════════════════════════════════════════════════

Future<String?> showSimpleWalletConnect(BuildContext context) async {
  return await SimpleWalletService().connect(context);
}

class WalletStatusWidget extends StatefulWidget {
  const WalletStatusWidget({super.key});

  @override
  State<WalletStatusWidget> createState() => _WalletStatusWidgetState();
}

class _WalletStatusWidgetState extends State<WalletStatusWidget> {
  final _service = SimpleWalletService();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Periodically refresh UI to stay in sync with wallet state
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _shorten(String addr) =>
      '${addr.substring(0, 6)}...${addr.substring(addr.length - 4)}';

  @override
  Widget build(BuildContext context) {
    if (!_service.isConnected) {
      return ElevatedButton.icon(
        onPressed: () => _service.connect(context),
        icon: const Icon(Icons.account_balance_wallet, size: 18),
        label: const Text('Connect'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
      );
    }

    return PopupMenuButton(
      child: Chip(
        avatar: const Icon(Icons.check_circle, color: Colors.green, size: 18),
        label: Text(_shorten(_service.address!)),
        backgroundColor: Colors.green[50],
        side: BorderSide(color: Colors.green.shade200),
      ),
      itemBuilder: (context) => [
        PopupMenuItem(
          child: const Text('Disconnect'),
          onTap: () => _service.disconnect(),
        ),
      ],
    );
  }
}
