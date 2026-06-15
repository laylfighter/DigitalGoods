
import 'package:flutter/material.dart';
import '../theme.dart';

class TermsScreen extends StatefulWidget {
  final int initialTabIndex; // 0 for Terms, 1 for Privacy
  const TermsScreen({super.key, this.initialTabIndex = 0});

  @override
  State<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends State<TermsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = AppTheme.primaryStart;
    final secondaryColor = context.appTextSecondary;

    return Scaffold(
      backgroundColor: context.appScaffold,
      appBar: AppBar(
        backgroundColor: context.appSurface,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'Legal Agreement',
          style: AppTheme.heading(
            18,
            color: context.appTextPrimary,
            weight: FontWeight.w600,
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
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: context.appSurfaceMuted,
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: context.appSurface,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              labelColor: primaryColor,
              unselectedLabelColor: secondaryColor,
              labelStyle: AppTheme.heading(13, weight: FontWeight.w600),
              unselectedLabelStyle: AppTheme.body(13, weight: FontWeight.w500),
              tabs: const [
                Tab(text: 'Terms of Service'),
                Tab(text: 'Privacy Policy'),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTermsContent(context),
          _buildPrivacyContent(context),
        ],
      ),
    );
  }

  Widget _buildTermsContent(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('1. Acceptance of Terms'),
          _buildParagraph(
            'Welcome to the Digital Goods Blockchain Platform. By accessing or using our application, you agree to comply with and be bound by these Terms of Service. If you do not agree, please do not use the services.',
          ),
          const SizedBox(height: 16),
          _buildSectionHeader('2. Blockchain Transactions & Assets'),
          _buildParagraph(
            'Our platform facilitates transaction logging, asset verification, and ownership tracking using distributed blockchain technology. Please be aware that blockchain transactions are irreversible and permanent. Once metadata is recorded, it cannot be deleted or modified.',
          ),
          const SizedBox(height: 16),
          _buildSectionHeader('3. User Registration & Security'),
          _buildParagraph(
            'To register as a User or Supplier, you must provide accurate, complete, and updated information (including name, phone number, and CNIC/NTN for suppliers). You are solely responsible for maintaining the confidentiality of your account credentials and all activities occurring under your account.',
          ),
          const SizedBox(height: 16),
          _buildSectionHeader('4. Supplier Responsibilities'),
          _buildParagraph(
            'Suppliers listing assets (such as electronic components or land fractions) warrant that they hold the legal rights, titles, and permissions to transfer or lease these assets. Misrepresentation of property metadata or selling stolen/counterfeit goods will result in account suspension and reference to relevant legal authorities.',
          ),
          const SizedBox(height: 16),
          _buildSectionHeader('5. Platform Fees & Payments'),
          _buildParagraph(
            'All transactions, including rents, fraction purchases, and deposits, are governed by Smart Contracts. The platform reserves the right to charge transactional fees. Verification of funds, currency processing, and wallet integrations are subject to independent blockchain validation.',
          ),
          const SizedBox(height: 16),
          _buildSectionHeader('6. Limitation of Liability'),
          _buildParagraph(
            'Under no circumstances shall the platform or its developers be liable for network fees, blockchain gas fees, smart contract execution errors, loss of private keys, system downtimes, or any indirect, incidental, or consequential damages resulting from your usage of the platform.',
          ),
          const SizedBox(height: 16),
          _buildSectionHeader('7. Changes to Terms'),
          _buildParagraph(
            'We reserve the right to modify these terms at any time. Changes will be posted within the application. Continued use of the platform following the posting of changes constitutes acceptance of the modified terms.',
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildPrivacyContent(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('1. Information We Collect'),
          _buildParagraph(
            'We collect information you provide directly during registration and usage, including:',
          ),
          _buildBulletPoint('Personal Identifiable Information: Name, email address, phone number.'),
          _buildBulletPoint('Verification Records: CNIC, NTN, and location details for registered Suppliers.'),
          _buildBulletPoint('Visual Profile data: profile pictures and documents submitted for Identity verification.'),
          _buildBulletPoint('Blockchain Data: Public wallet addresses, smart contract interactions, and transactional histories.'),
          const SizedBox(height: 16),
          _buildSectionHeader('2. How We Use Information'),
          _buildParagraph(
            'We use your information to operate, maintain, and provide platform features, including:',
          ),
          _buildBulletPoint('Establishing account identity and verifying ownership of physical or digital assets.'),
          _buildBulletPoint('Executing smart contracts for fractions, rent distributions, and transaction ledger logging.'),
          _buildBulletPoint('Sending system updates, alerts for security incidents (such as reported stolen goods), and customer support correspondence.'),
          const SizedBox(height: 16),
          _buildSectionHeader('3. Blockchain Transparency Notice'),
          _buildParagraph(
            'Please note that by design, details logged onto the blockchain (such as transaction values, wallet identifiers, and asset hashes) are public, transparent, and immutable. We do not control and cannot remove personal data once it has been processed and stored on a public ledger.',
          ),
          const SizedBox(height: 16),
          _buildSectionHeader('4. Data Sharing & Security'),
          _buildParagraph(
            'We do not sell your personal data to third parties. We employ industry-standard administrative, physical, and electronic security measures to protect your information from unauthorized access. However, no internet transmission or electronic storage is 100% secure.',
          ),
          const SizedBox(height: 16),
          _buildSectionHeader('5. User Rights'),
          _buildParagraph(
            'You have the right to update your profile data via the Account screen. If you wish to deactivate your account, please contact support. Data logged locally/in Firestore may be removed or anonymized, subject to regulatory compliance, but blockchain records cannot be altered.',
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, top: 12.0),
      child: Text(
        title,
        style: AppTheme.heading(
          15,
          color: AppTheme.primaryStart,
          weight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildParagraph(String text) {
    return Text(
      text,
      style: AppTheme.body(
        13,
        color: context.appTextSecondary,
      ),
      textAlign: TextAlign.justify,
    );
  }

  Widget _buildBulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 12.0, top: 4.0, bottom: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6.0, right: 8.0),
            child: Icon(
              Icons.circle,
              size: 6,
              color: AppTheme.accent,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: AppTheme.body(
                13,
                color: context.appTextSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
