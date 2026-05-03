import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/profile_provider.dart';
import 'document_screen.dart';
import 'email_screen.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

// ── Postcode lookup result ─────────────────────────────────────────
class _PostcodeData {
  final String city;
  final String county;
  final String country;
  final List<String> streets;

  const _PostcodeData({
    required this.city,
    required this.county,
    required this.country,
    required this.streets,
  });
}

const aboutContent = """
# About Swift Label UK

Swift Label UK is a parcel shipping platform designed to simplify the process of creating shipping labels and managing parcel deliveries.

The platform allows businesses and individual users to generate shipping labels, manage shipments, and access multiple courier services from a single dashboard.

## Who We Support
- E-commerce sellers
- Small businesses
- Individual users

## What You Can Do
- Generate shipping labels quickly
- Manage shipment details
- Track deliveries through integrated courier services

By connecting multiple courier providers in one place, Swift Label UK helps users choose the most suitable shipping option.

## Integrations
The platform integrates with:
- eBay
- Shopify

This helps sellers manage orders and shipping efficiently.

## Availability
The app is available on:
- Apple App Store
- Google Play Store

## Technology
Swift Label UK uses secure systems for:
- Data storage
- Payment processing
- Shipping label generation

## Courier Partners
- Evri
- Royal Mail
- DPD
- Global Post
- Yodel
- FedEx
- ParcelForce

Swift Label UK is built to support modern shipping workflows and simplify parcel management.
""";

const faqContent = """
# Frequently Asked Questions (FAQ)

## **1. What is Swift Label UK?**
Swift Label UK is a parcel shipping platform that allows users to create and print shipping labels, manage shipments, and access multiple courier services from a single dashboard.

## **2. Which courier services are available?**
- Evri
- Royal Mail
- DPD
- Global Post
- Yodel
- FedEx
- ParcelForce

## **3. How do I create a shipping label?**
Steps:
- Log in to your account  
- Enter sender address  
- Enter recipient address  
- Select parcel size and weight  
- Choose courier service  
- Complete payment  
- Download and print the label  

Shipping labels are generated using ShipStation.

## **4. How are payments processed?**
- Payments are securely processed via Stripe  
- No full card details are stored  
- Stripe handles all transactions  

## **5. How is my data stored?**
- Stored securely  
- Encrypted database  
- Secure authentication and APIs  

## **6. What if my parcel is delayed or lost?**
- Contact the courier directly  
- Swift Label can assist with shipment details  

## **7. Can I cancel a shipping label?**
- Depends on courier and shipment status  
- Contact support if unused  

## **8. What items cannot be shipped?**
- Hazardous materials  
- Explosives  
- Illegal substances  
- Dangerous goods  

## **9. What if I face technical issues?**
- Contact support  
- Report login, payment, or label issues  
- Provide screenshots  

## **10. How can I contact support?**
swiftlabelsupport@gmail.com
""";

const helpContent = """
# Help & Support Policy

## Introduction
Swift Label UK provides reliable support for all users.

## Support Services
We assist with:
- Account access issues
- Shipping label generation
- Payment issues
- Shipment tracking
- Technical problems

## Contact Support
Email: swiftlabelsupport@gmail.com

Include:
- Account email
- Shipment reference (if available)
- Issue description

## Response Time
Response time depends on issue complexity.

## Shipping & Courier Issues
We integrate with:
- Evri
- Royal Mail
- DPD
- Global Post
- Yodel
- FedEx
- ParcelForce

Couriers handle delivery.
For delays, loss, or damage → contact courier directly.

## Payment Issues
- Payments handled via Stripe
- Contact support with transaction details

## Technical Issues
Provide:
- Screenshots
- Device or browser details

## Policy Updates
This policy may be updated periodically.

## Contact
swiftlabelsupport@gmail.com
""";

const privacyContent = """
# Privacy & Data Security Policy

## Introduction
Swift Label UK is committed to protecting user privacy and complying with UK GDPR and the Data Protection Act 2018.

## Information We Collect
- Name, email, phone number
- Shipping details
- Payment references
- Device and usage data

## Data Storage
Data is securely stored using Third Party Service:
- Encrypted database
- Secure API access
- Authentication systems

## Payment Processing
- Payments handled via Stripe
- PCI-compliant infrastructure
- No card details stored

## Shipping Label Generation
Labels are generated using ShipStation.

Shipping data may be securely shared to complete deliveries.

## Courier Integration
Data is shared only as required with:
- Evri
- Royal Mail
- DPD
- Global Post
- Yodel
- FedEx
- ParcelForce

## Security Measures
- HTTPS encryption
- Secure databases
- Access control
- Authentication systems

## Data Retention
Data is retained only as necessary for:
- Service delivery
- Legal compliance
- Dispute resolution

## User Rights
Users can:
- Request access
- Request correction
- Request deletion
- Restrict processing

## Cookies
Used for:
- Login sessions
- Platform functionality
- Analytics


## Contact
swiftlabelsupport@gmail.com
""";

const termsContent = """
# Terms and Conditions

## Introduction
By using Swift Label UK, you agree to these terms. If you do not agree, do not use the service.

## Definitions
- Platform: Swift Label UK app/website
- User: Individual or business using the platform
- Shipment: Parcel processed
- Courier: Delivery company

## Account Registration
- Users must provide accurate info
- Keep login credentials secure
- Responsible for account activity

## Shipping Services
Swift Label UK provides access to courier services:
- Evri
- Royal Mail
- DPD
- Global Post
- Yodel
- FedEx
- ParcelForce

Swift Label UK does not transport parcels.

## Shipping Labels
Generated using ShipStation.

Users must provide accurate:
- Sender details
- Receiver details
- Parcel size & weight

Incorrect info may cause delays or extra charges.

## Payments
- Processed via Stripe
- Users must pay all applicable charges
- No card details stored

## Prohibited Items
Users must NOT ship:
- Dangerous goods
- Explosives
- Illegal substances
- Hazardous materials

## Delivery Responsibility
Courier companies handle delivery.  
Swift Label UK does not guarantee delivery times.

## Liability
Swift Label UK is not responsible for:
- Lost parcels
- Delays
- Damages

Claims must be made with courier.

## Data Protection
Data is stored securely.

## Platform Availability
Service may be temporarily unavailable due to maintenance.

## Termination
Accounts may be suspended for:
- Violations
- Fraud
- Misuse

## Changes
Terms may be updated anytime.

## Governing Law
These terms are governed by UK law.

## Contact
swiftlabelsupport@gmail.com
""";

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey     = GlobalKey<FormState>();
  final _imagePicker = ImagePicker();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _addr1Ctrl;
  late final TextEditingController _addr2Ctrl;
  late final TextEditingController _cityCtrl;
  late final TextEditingController _postcodeCtrl;
  late final TextEditingController _doorCtrl;

  // Postcode lookup state
  bool   _isLookingUp     = false;
  bool   _postcodeValid   = false;
  String _postcodeError   = '';
  List<String> _streetList = [];
  String? _selectedStreet;
  Timer? _debounce;

  // Country is always United Kingdom — not editable
  static const String _country = 'United Kingdom';

  @override
  void initState() {
    super.initState();
    _nameCtrl     = TextEditingController();
    _phoneCtrl    = TextEditingController();
    _addr1Ctrl    = TextEditingController();
    _addr2Ctrl    = TextEditingController();
    _cityCtrl     = TextEditingController();
    _postcodeCtrl = TextEditingController();
    _doorCtrl     = TextEditingController();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final email = context.read<AuthProvider>().email;
      await context.read<ProfileProvider>().loadProfile(email);
      _syncControllersFromProvider();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in [
      _nameCtrl, _phoneCtrl, _addr1Ctrl, _addr2Ctrl,
      _cityCtrl, _postcodeCtrl, _doorCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _syncControllersFromProvider() {
    final p            = context.read<ProfileProvider>();
    _nameCtrl.text     = p.fullName;
    _phoneCtrl.text    = p.phone;
    _addr1Ctrl.text    = p.addressLine1;
    _addr2Ctrl.text    = p.addressLine2;
    _cityCtrl.text     = p.city;
    _postcodeCtrl.text = p.postcode;

    // Try to split door number from address line 1
    if (p.addressLine1.isNotEmpty) {
      final parts = p.addressLine1.split(' ');
      if (parts.length > 1 && RegExp(r'^\d+[A-Za-z]?$').hasMatch(parts[0])) {
        _doorCtrl.text  = parts[0];
        _addr1Ctrl.text = parts.sublist(1).join(' ');
      }
    }
    if (p.postcode.isNotEmpty) {
      _postcodeValid = true;
    }
  }

  // ── Postcode lookup via postcodes.io ──────────────────────────
  void _onPostcodeChanged(String value) {
    _debounce?.cancel();
    setState(() {
      _postcodeValid  = false;
      _postcodeError  = '';
      _streetList     = [];
      _selectedStreet = null;
    });

    final cleaned = value.trim().replaceAll(' ', '').toUpperCase();
    if (cleaned.length < 5) return;

    _debounce = Timer(const Duration(milliseconds: 600), () {
      _lookupPostcode(cleaned);
    });
  }

  Future<void> _lookupPostcode(String postcode) async {
    setState(() {
      _isLookingUp   = true;
      _postcodeError = '';
    });

    try {
      // ── Step 1: Validate + get city via postcodes.io ─────────────────
      final res = await http.get(
        Uri.parse('https://api.postcodes.io/postcodes/$postcode'),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(res.body);

      if (res.statusCode != 200 || data['status'] != 200) {
        setState(() {
          _postcodeError = 'Invalid postcode. Please check and try again.';
          _isLookingUp   = false;
        });
        return;
      }

      final result = data['result'];

      // Extract city
      final city = result['admin_district'] ??
          result['parish']         ??
          result['region']         ??
          'Unknown';

      // Auto-fill city
      _cityCtrl.text = city;

      // Format postcode with space
      final formatted = _formatPostcode(postcode);
      _postcodeCtrl.text = formatted;

      setState(() { _postcodeValid = true; });

      // ── Step 2: Load nearby streets ───────────────────────────────────
      final lat = result['latitude']  as double?;
      final lng = result['longitude'] as double?;

      if (lat != null && lng != null) {
        await _loadNearbyStreets(lat, lng, formatted);
      }
    } on TimeoutException {
      setState(() { _postcodeError = 'Request timed out. Please try again.'; });
    } on SocketException {
      setState(() { _postcodeError = 'No internet connection.'; });
    } catch (e) {
      debugPrint('Postcode lookup error: $e');
      setState(() { _postcodeError = 'Could not look up postcode.'; });
    }

    setState(() { _isLookingUp = false; });
  }

  // ── Get nearby streets (Nominatim + Overpass) ─────────────────
  Future<void> _loadNearbyStreets(double lat, double lng, String postcode) async {
    try {
      final Set<String> streets = {};

      // ── 1. Reverse geocode for the primary road ───────────────────────
      final revRes = await http.get(
        Uri.parse(
          'https://nominatim.openstreetmap.org/reverse'
              '?lat=$lat&lon=$lng'
              '&format=json'
              '&addressdetails=1'
              '&zoom=16',
        ),
        headers: {'User-Agent': 'SwiftLabel Flutter App'},
      ).timeout(const Duration(seconds: 10));

      if (revRes.statusCode == 200) {
        final addr = (jsonDecode(revRes.body) as Map)['address'];
        final road = addr?['road'] ?? addr?['street'] ?? addr?['path'];
        if (road != null) streets.add(road.toString());
      }

      // ── 2. Nominatim bounded search (~400 m box) ──────────────────────
      const delta = 0.004; // ~400 m in degrees
      final bbox  = '${lng - delta},${lat - delta},${lng + delta},${lat + delta}';

      final searchRes = await http.get(
        Uri.parse(
          'https://nominatim.openstreetmap.org/search'
              '?q=road&format=json&addressdetails=1&limit=50'
              '&bounded=1&viewbox=$bbox',
        ),
        headers: {'User-Agent': 'SwiftLabel Flutter App'},
      ).timeout(const Duration(seconds: 10));

      if (searchRes.statusCode == 200) {
        final List items = jsonDecode(searchRes.body);
        for (final item in items) {
          final addr = item['address'] as Map?;
          final road = addr?['road'] ?? addr?['street'] ?? addr?['path'];
          if (road != null && road.toString().isNotEmpty) {
            streets.add(road.toString());
          }
          // Also grab first segment of display_name for road entries
          final display = item['display_name']?.toString() ?? '';
          if (display.isNotEmpty) {
            final segment = display.split(',').first.trim();
            if (segment.isNotEmpty && !segment.contains(RegExp(r'\d{3}'))) {
              streets.add(segment);
            }
          }
        }
      }

      // ── 3. Overpass API — most reliable for actual road names ─────────
      final overpassQuery =
          '[out:json][timeout:12];'
          'way(around:400,$lat,$lng)[highway][name];'
          'out tags;';

      final overpassRes = await http.post(
        Uri.parse('https://overpass-api.de/api/interpreter'),
        body: overpassQuery,
      ).timeout(const Duration(seconds: 14));

      if (overpassRes.statusCode == 200) {
        final elements =
            (jsonDecode(overpassRes.body) as Map)['elements'] as List? ?? [];
        for (final el in elements) {
          final name = el['tags']?['name'];
          if (name != null && name.toString().isNotEmpty) {
            streets.add(name.toString());
          }
        }
      }

      final sortedStreets = streets.toList()..sort();

      if (mounted) {
        setState(() {
          _streetList = sortedStreets.isNotEmpty
              ? sortedStreets
              : ['Enter street name manually'];
        });
      }
    } catch (e) {
      debugPrint('Street lookup error: $e');
      // Silently fail — user can type street manually
    }
  }

  String _formatPostcode(String raw) {
    final clean = raw.replaceAll(' ', '').toUpperCase();
    if (clean.length >= 5) {
      return '${clean.substring(0, clean.length - 3)} ${clean.substring(clean.length - 3)}';
    }
    return clean;
  }

  // ── Image picker ──────────────────────────────────────────────
  void _showImagePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: const Color(0xFFE0E0E0),
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 20),
            const Text('Update Profile Photo',
                style: TextStyle(fontFamily: 'Syne', fontSize: 16,
                    fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
            const SizedBox(height: 20),
            _PickerOption(
              icon: Icons.photo_library_outlined,
              label: 'Choose from Gallery',
              onTap: () { Navigator.pop(context); _pickImage(ImageSource.gallery); },
            ),
            const SizedBox(height: 10),
            _PickerOption(
              icon: Icons.camera_alt_outlined,
              label: 'Take a Photo',
              onTap: () { Navigator.pop(context); _pickImage(ImageSource.camera); },
            ),
            if (context.read<ProfileProvider>().hasAvatar) ...[
              const SizedBox(height: 10),
              _PickerOption(
                icon: Icons.delete_outline_rounded,
                label: 'Remove Photo',
                color: Colors.red,
                onTap: () { Navigator.pop(context); },
              ),
            ],
            const SizedBox(height: 10),
          ]),
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _imagePicker.pickImage(
        source: source, maxWidth: 512, maxHeight: 512, imageQuality: 85,
      );
      if (picked == null) return;
      final email = context.read<AuthProvider>().email;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Row(children: [
            SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
            SizedBox(width: 12),
            Text('Uploading photo...'),
          ]),
          backgroundColor: Color(0xFFFF5A00),
          duration: Duration(seconds: 15),
          behavior: SnackBarBehavior.floating,
        ));
      }
      final url = await context.read<ProfileProvider>().uploadAvatar(
        email: email, imageFile: File(picked.path),
      );
      if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(url != null ? '✓ Photo updated!' : '✗ Upload failed.'),
          backgroundColor: url != null ? const Color(0xFF059669) : Colors.red,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
        ));
      }
    } catch (e) {
      debugPrint('Image picker error: $e');
    }
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;
    final email = context.read<AuthProvider>().email;

    // Combine door + street for address line 1
    final door      = _doorCtrl.text.trim();
    final street    = _addr1Ctrl.text.trim();
    final fullAddr1 = door.isNotEmpty ? '$door $street' : street;

    final success = await context.read<ProfileProvider>().saveProfile(
      email:        email,
      fullName:     _nameCtrl.text.trim(),
      phone:        _phoneCtrl.text.trim(),
      addressLine1: fullAddr1,
      addressLine2: _addr2Ctrl.text.trim(),
      city:         _cityCtrl.text.trim(),
      postcode:     _postcodeCtrl.text.trim().toUpperCase(),
      country:      _country, // always United Kingdom
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(success ? 'Profile saved!' : 'Failed to save. Try again.'),
        backgroundColor: success ? const Color(0xFF059669) : Colors.red,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
      ));
    }
  }

  void _handleLogout() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Log Out',
            style: TextStyle(fontFamily: 'Syne',
                fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
        content: const Text('Are you sure you want to log out of SwiftLabel?',
            style: TextStyle(color: Color(0xFF6B6B6B), height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF6B6B6B))),
          ),
          TextButton(
            onPressed: () async {
              await context.read<AuthProvider>().reset();
              await context.read<ProfileProvider>().clearProfile();
              if (mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const EmailScreen()),
                      (route) => false,
                );
              }
            },
            child: const Text('Log Out',
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile     = context.watch<ProfileProvider>();
    final auth        = context.read<AuthProvider>();
    final isEditing   = profile.isEditing;
    final isSaving    = profile.isSaving;
    final isUploading = profile.isUploadingImage;

    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F7),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Column(children: [

            // ── Top Nav ──────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
              ),
              child: Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    'assets/images/logo.png',
                    width: 30,
                    height: 30,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 30, height: 30,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF5A00),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.inventory_2_outlined, color: Colors.white, size: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Text('SwiftLabel',
                    style: TextStyle(fontFamily: 'Syne', fontSize: 17,
                        fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Row(children: [
                    Icon(Icons.arrow_back_ios, size: 14, color: Color(0xFF6B6B6B)),
                    Text('Dashboard',
                        style: TextStyle(fontSize: 13, color: Color(0xFF6B6B6B))),
                  ]),
                ),
              ]),
            ),

            // ── Body ─────────────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 28),

                    // Title + edit toggle
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('My Profile',
                            style: TextStyle(fontFamily: 'Syne', fontSize: 22,
                                fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
                        if (!isEditing)
                          _OutlineBtn(
                            label: 'Edit Profile',
                            icon: Icons.edit_outlined,
                            onTap: () => profile.toggleEditing(),
                          )
                        else
                          Row(children: [
                            _OutlineBtn(
                              label: 'Cancel',
                              icon: Icons.close,
                              color: const Color(0xFF6B6B6B),
                              borderColor: const Color(0xFFDDDDDD),
                              onTap: () {
                                _syncControllersFromProvider();
                                profile.cancelEditing();
                              },
                            ),
                            const SizedBox(width: 8),
                            _OutlineBtn(
                              label: 'Save',
                              icon: Icons.check,
                              color: const Color(0xFFFF5A00),
                              borderColor: const Color(0xFFFF5A00),
                              bgColor: const Color(0xFFFFF5EE),
                              onTap: isSaving ? null : _handleSave,
                            ),
                          ]),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // ── Avatar Card ───────────────────────────────────
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: const Color(0xFFEEEEEE)),
                          borderRadius: BorderRadius.circular(16)),
                      child: Column(children: [
                        Stack(children: [
                          GestureDetector(
                            onTap: isEditing ? _showImagePicker : null,
                            child: Container(
                              width: 90, height: 90,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFFFFF5EE),
                                border: Border.all(
                                    color: const Color(0xFFFFDDCC), width: 2),
                                image: profile.hasAvatar
                                    ? DecorationImage(
                                    image: NetworkImage(profile.avatarUrl),
                                    fit: BoxFit.cover)
                                    : null,
                              ),
                              child: isUploading
                                  ? const Center(
                                  child: SizedBox(
                                    width: 24, height: 24,
                                    child: CircularProgressIndicator(
                                        color: Color(0xFFFF5A00),
                                        strokeWidth: 2),
                                  ))
                                  : !profile.hasAvatar
                                  ? Center(
                                  child: Text(profile.initials,
                                      style: const TextStyle(
                                          fontFamily: 'Syne',
                                          fontSize: 28,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFFFF5A00))))
                                  : null,
                            ),
                          ),
                          if (isEditing)
                            Positioned(
                              bottom: 0, right: 0,
                              child: GestureDetector(
                                onTap: _showImagePicker,
                                child: Container(
                                  width: 28, height: 28,
                                  decoration: BoxDecoration(
                                      color: const Color(0xFFFF5A00),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: Colors.white, width: 2)),
                                  child: const Icon(Icons.camera_alt_rounded,
                                      size: 14, color: Colors.white),
                                ),
                              ),
                            ),
                        ]),
                        const SizedBox(height: 14),
                        Text(
                          profile.fullName.isNotEmpty
                              ? profile.fullName : 'Your Name',
                          style: TextStyle(
                              fontFamily: 'Syne', fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: profile.fullName.isNotEmpty
                                  ? const Color(0xFF1A1A1A)
                                  : const Color(0xFFB0B0B0)),
                        ),
                        const SizedBox(height: 4),
                        Text(auth.email,
                            style: const TextStyle(
                                fontSize: 13, color: Color(0xFF9B9B9B))),
                        const SizedBox(height: 10),
                        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          _Badge(
                              label: '✓ Email Verified',
                              color: const Color(0xFF059669)),
                          if (profile.isProfileComplete) ...[
                            const SizedBox(width: 8),
                            _Badge(
                                label: '✓ Profile Complete',
                                color: const Color(0xFF0284C7)),
                          ],
                        ]),
                        if (isEditing) ...[
                          const SizedBox(height: 10),
                          const Text('Tap photo to update',
                              style: TextStyle(
                                  fontSize: 11, color: Color(0xFFB0B0B0))),
                        ],
                      ]),
                    ),

                    const SizedBox(height: 16),

                    // ── Account Info ──────────────────────────────────
                    _SectionCard(title: 'Account Information', children: [
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Email Address',
                            style: TextStyle(fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF6B6B6B))),
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 13),
                          decoration: BoxDecoration(
                              color: const Color(0xFFF9F9F9),
                              border: Border.all(color: const Color(0xFFF0F0F0)),
                              borderRadius: BorderRadius.circular(10)),
                          child: Row(children: [
                            const Icon(Icons.email_outlined,
                                size: 17, color: Color(0xFF9B9B9B)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(auth.email,
                                  style: const TextStyle(
                                      fontSize: 14, color: Color(0xFF6B6B6B))),
                            ),
                            const Icon(Icons.lock_outline_rounded,
                                size: 14, color: Color(0xFFB0B0B0)),
                          ]),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Email cannot be changed — used for authentication.',
                          style: TextStyle(fontSize: 11, color: Color(0xFFB0B0B0)),
                        ),
                      ]),
                    ]),

                    const SizedBox(height: 16),

                    // ── Personal Info ─────────────────────────────────
                    _SectionCard(title: 'Personal Information', children: [
                      _Field(
                        label: 'Full Name *',
                        controller: _nameCtrl,
                        icon: Icons.person_outline_rounded,
                        enabled: isEditing,
                        validator: (v) => v == null || v.isEmpty
                            ? 'Full name is required' : null,
                      ),
                      // Phone
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Phone Number *',
                            style: TextStyle(fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF6B6B6B))),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _phoneCtrl,
                          enabled: isEditing,
                          keyboardType: TextInputType.phone,
                          style: const TextStyle(
                              fontSize: 14, color: Color(0xFF1A1A1A)),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Phone is required';
                            }

                            final digits = v.replaceAll(RegExp(r'\D'), '');

                            if (digits.length < 10) {
                              return 'Phone number must be at least 10 digits';
                            }

                            if (digits.length > 11) {
                              return 'Phone number must not exceed 11 digits';
                            }

                            return null;
                          },
                          decoration: InputDecoration(
                            hintText: 'e.g. 07700 900000 or +44 7700 900000',
                            hintStyle: const TextStyle(
                                color: Color(0xFFB0B0B0), fontSize: 13),
                            prefixIcon: const Icon(Icons.phone_outlined,
                                size: 17, color: Color(0xFF9B9B9B)),
                            filled: true,
                            fillColor: isEditing
                                ? Colors.white : const Color(0xFFF9F9F9),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 13),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(
                                    color: Color(0xFFE0E0E0))),
                            enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(
                                    color: Color(0xFFE0E0E0))),
                            focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(
                                    color: Color(0xFFFF5A00), width: 1.5)),
                            disabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(
                                    color: Color(0xFFF0F0F0))),
                          ),
                        ),
                      ]),
                    ]),

                    const SizedBox(height: 16),

                    // ── Delivery Address ──────────────────────────────
                    _SectionCard(title: 'Default Delivery Address', children: [

                      // ── POSTCODE ──────────────────────────────────
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Postcode *',
                            style: TextStyle(fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF6B6B6B))),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _postcodeCtrl,
                          enabled: isEditing,
                          textCapitalization: TextCapitalization.characters,
                          style: const TextStyle(
                              fontSize: 14, color: Color(0xFF1A1A1A)),
                          onChanged: isEditing ? _onPostcodeChanged : null,
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return 'Postcode is required';
                            }
                            if (!RegExp(
                                r'^[A-Z]{1,2}\d[A-Z\d]? ?\d[A-Z]{2}$',
                                caseSensitive: false)
                                .hasMatch(v.trim())) {
                              return 'Enter a valid UK postcode';
                            }
                            return null;
                          },
                          decoration: InputDecoration(
                            hintText: 'e.g. SW1A 1AA',
                            hintStyle: const TextStyle(
                                color: Color(0xFFB0B0B0), fontSize: 14),
                            filled: true,
                            fillColor: isEditing
                                ? Colors.white : const Color(0xFFF9F9F9),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 13),
                            suffixIcon: _isLookingUp
                                ? const Padding(
                                padding: EdgeInsets.all(14),
                                child: SizedBox(
                                  width: 16, height: 16,
                                  child: CircularProgressIndicator(
                                      color: Color(0xFFFF5A00),
                                      strokeWidth: 2),
                                ))
                                : _postcodeValid
                                ? const Icon(Icons.check_circle_rounded,
                                color: Color(0xFF059669), size: 20)
                                : null,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(
                                    color: Color(0xFFE0E0E0))),
                            enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                    color: _postcodeValid
                                        ? const Color(0xFF059669)
                                        : _postcodeError.isNotEmpty
                                        ? Colors.red
                                        : const Color(0xFFE0E0E0))),
                            focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(
                                    color: Color(0xFFFF5A00), width: 1.5)),
                            disabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(
                                    color: Color(0xFFF0F0F0))),
                            errorBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide:
                                const BorderSide(color: Colors.red)),
                          ),
                        ),
                        if (_postcodeError.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(_postcodeError,
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.red)),
                        ],
                        if (_postcodeValid && !_isLookingUp) ...[
                          const SizedBox(height: 4),
                          const Text(
                            '✓ Postcode verified — city and streets auto-filled',
                            style: TextStyle(
                                fontSize: 11, color: Color(0xFF059669)),
                          ),
                        ],
                      ]),

                      const SizedBox(height: 4),

                      // ── STREET ────────────────────────────────────
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Street Name *',
                            style: TextStyle(fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF6B6B6B))),
                        const SizedBox(height: 6),

                        if (isEditing && _streetList.isNotEmpty)
                          DropdownButtonFormField<String>(
                            value: _selectedStreet,
                            isExpanded: true,
                            hint: const Text('Select your street',
                                style: TextStyle(
                                    color: Color(0xFFB0B0B0), fontSize: 14)),
                            style: const TextStyle(
                                fontSize: 14, color: Color(0xFF1A1A1A)),
                            decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.signpost_outlined,
                                  size: 17, color: Color(0xFF9B9B9B)),
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 13),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(
                                      color: Color(0xFFE0E0E0))),
                              enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(
                                      color: Color(0xFFE0E0E0))),
                              focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(
                                      color: Color(0xFFFF5A00), width: 1.5)),
                            ),
                            items: [
                              ..._streetList.map((s) => DropdownMenuItem(
                                  value: s,
                                  child: Text(s,
                                      overflow: TextOverflow.ellipsis))),
                              const DropdownMenuItem(
                                  value: '__manual__',
                                  child: Text('✏️ Enter manually',
                                      style: TextStyle(
                                          color: Color(0xFFFF5A00),
                                          fontWeight: FontWeight.w600))),
                            ],
                            onChanged: (val) {
                              setState(() {
                                if (val == '__manual__') {
                                  _selectedStreet = null;
                                  _streetList     = [];
                                  _addr1Ctrl.clear();
                                } else {
                                  _selectedStreet = val;
                                  _addr1Ctrl.text = val ?? '';
                                }
                              });
                            },
                            validator: (v) =>
                            (v == null || v.isEmpty || v == '__manual__')
                                ? 'Please select a street'
                                : null,
                          )
                        else
                          TextFormField(
                            controller: _addr1Ctrl,
                            enabled: isEditing,
                            style: const TextStyle(
                                fontSize: 14, color: Color(0xFF1A1A1A)),
                            validator: (v) => v == null || v.isEmpty
                                ? 'Street name is required' : null,
                            decoration: InputDecoration(
                              hintText: 'e.g. Baker Street',
                              hintStyle: const TextStyle(
                                  color: Color(0xFFB0B0B0), fontSize: 14),
                              prefixIcon: const Icon(Icons.signpost_outlined,
                                  size: 17, color: Color(0xFF9B9B9B)),
                              filled: true,
                              fillColor: isEditing
                                  ? Colors.white : const Color(0xFFF9F9F9),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 13),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(
                                      color: Color(0xFFE0E0E0))),
                              enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(
                                      color: Color(0xFFE0E0E0))),
                              focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(
                                      color: Color(0xFFFF5A00), width: 1.5)),
                              disabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(
                                      color: Color(0xFFF0F0F0))),
                            ),
                          ),

                        if (isEditing &&
                            _postcodeValid &&
                            _streetList.isEmpty &&
                            !_isLookingUp) ...[
                          const SizedBox(height: 4),
                          const Text('Type your street name above',
                              style: TextStyle(
                                  fontSize: 11, color: Color(0xFF9B9B9B))),
                        ],
                      ]),

                      const SizedBox(height: 4),

                      // ── DOOR / FLAT NUMBER ────────────────────────
                      _Field(
                        label: 'Door / Flat / Building Number',
                        controller: _doorCtrl,
                        icon: Icons.tag_rounded,
                        enabled: isEditing,
                        hint: 'e.g. 12 or Flat 3B',
                        keyboardType: TextInputType.text,
                        validator: (v) => v == null || v.isEmpty
                            ? 'Door number is required' : null,
                      ),

                      // ── ADDRESS LINE 2 ────────────────────────────
                      _Field(
                        label: 'Address Line 2 (Optional)',
                        controller: _addr2Ctrl,
                        icon: Icons.apartment_outlined,
                        enabled: isEditing,
                        hint: 'Estate / Building name',
                      ),

                      // ── CITY (auto-filled) ────────────────────────
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('City / Town',
                            style: TextStyle(fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF6B6B6B))),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _cityCtrl,
                          enabled: isEditing,
                          style: const TextStyle(
                              fontSize: 14, color: Color(0xFF1A1A1A)),
                          validator: (v) => v == null || v.isEmpty
                              ? 'City is required' : null,
                          decoration: InputDecoration(
                            hintText: 'Auto-filled from postcode',
                            hintStyle: const TextStyle(
                                color: Color(0xFFB0B0B0), fontSize: 14),
                            prefixIcon: const Icon(Icons.location_city_outlined,
                                size: 17, color: Color(0xFF9B9B9B)),
                            suffixIcon: _postcodeValid &&
                                _cityCtrl.text.isNotEmpty
                                ? Tooltip(
                                message: 'Auto-filled from postcode',
                                child: const Icon(
                                    Icons.auto_awesome_rounded,
                                    size: 16,
                                    color: Color(0xFFFF5A00)))
                                : null,
                            filled: true,
                            fillColor: _postcodeValid && isEditing
                                ? const Color(0xFFFFF8F5)
                                : isEditing
                                ? Colors.white
                                : const Color(0xFFF9F9F9),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 13),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(
                                    color: Color(0xFFE0E0E0))),
                            enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                    color: _postcodeValid
                                        ? const Color(0xFFFF5A00)
                                        .withOpacity(0.4)
                                        : const Color(0xFFE0E0E0))),
                            focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(
                                    color: Color(0xFFFF5A00), width: 1.5)),
                            disabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(
                                    color: Color(0xFFF0F0F0))),
                          ),
                        ),
                        if (_postcodeValid &&
                            _cityCtrl.text.isNotEmpty &&
                            isEditing) ...[
                          const SizedBox(height: 4),
                          const Text(
                            '✨ Auto-filled from postcode — you can edit if needed',
                            style: TextStyle(
                                fontSize: 11, color: Color(0xFFFF5A00)),
                          ),
                        ],
                      ]),

                      // ── COUNTRY (read-only, always United Kingdom) ─
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Country',
                            style: TextStyle(fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF6B6B6B))),
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 13),
                          decoration: BoxDecoration(
                              color: const Color(0xFFF9F9F9),
                              border: Border.all(color: const Color(0xFFF0F0F0)),
                              borderRadius: BorderRadius.circular(10)),
                          child: Row(children: [
                            const Icon(Icons.flag_outlined,
                                size: 17, color: Color(0xFF9B9B9B)),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                _country,
                                style: TextStyle(
                                    fontSize: 14, color: Color(0xFF6B6B6B)),
                              ),
                            ),
                            const Icon(Icons.lock_outline_rounded,
                                size: 14, color: Color(0xFFB0B0B0)),
                          ]),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Deliveries are currently available in the UK only.',
                          style: TextStyle(
                              fontSize: 11, color: Color(0xFFB0B0B0)),
                        ),
                      ]),
                    ]),

                    if (isEditing) ...[
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity, height: 48,
                        child: ElevatedButton(
                          onPressed: isSaving ? null : _handleSave,
                          child: isSaving
                              ? const SizedBox(
                              height: 20, width: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                              : const Text('Save Changes',
                              style: TextStyle(fontFamily: 'Syne',
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],

                    if (!isEditing) ...[
                      const SizedBox(height: 20),
                      _SectionCard(title: 'Account', children: [
                        _SettingRow(
                          icon: Icons.security,
                          label: 'Terms and Conditions',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const DocumentScreen(
                                  title: 'Terms and Conditions',
                                  content: termsContent,
                                ),
                              ),
                            );
                          },
                        ),
                        _SettingRow(
                          icon: Icons.lock_outline_rounded,
                          label: 'Privacy & Security',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const DocumentScreen(
                                  title: 'Privacy & Security',
                                  content: privacyContent,
                                ),
                              ),
                            );
                          },
                        ),
                        // Help
                        _SettingRow(
                          icon: Icons.help_outline_rounded,
                          label: 'Help & Support',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const DocumentScreen(
                                  title: 'Help & Support',
                                  content: helpContent,
                                ),
                              ),
                            );
                          },
                        ),

// FAQ
                        _SettingRow(
                          icon: Icons.question_answer_outlined,
                          label: 'FAQ',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const DocumentScreen(
                                  title: 'FAQ',
                                  content: faqContent,
                                ),
                              ),
                            );
                          },
                        ),

// About
                        _SettingRow(
                          icon: Icons.info_outline_rounded,
                          label: 'About SwiftLabel',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const DocumentScreen(
                                  title: 'About SwiftLabel',
                                  content: aboutContent,
                                ),
                              ),
                            );
                          },
                        ),
                      ]),
                      const SizedBox(height: 16),
                      GestureDetector(
                        onTap: _handleLogout,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.04),
                              border: Border.all(
                                  color: Colors.red.withOpacity(0.15)),
                              borderRadius: BorderRadius.circular(12)),
                          child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.logout_rounded,
                                    color: Colors.red, size: 17),
                                SizedBox(width: 8),
                                Text('Log Out',
                                    style: TextStyle(
                                        color: Colors.red,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14)),
                              ]),
                        ),
                      ),
                    ],

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Reusable Widgets ───────────────────────────────────────────────

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.2))),
    child: Text(label,
        style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color)),
  );
}

class _PickerOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  const _PickerOption({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = const Color(0xFF1A1A1A),
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: const Color(0xFFF9F9F9),
          border: Border.all(color: const Color(0xFFEEEEEE)),
          borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 12),
        Text(label,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: color)),
      ]),
    ),
  );
}

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SectionCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFEEEEEE)),
        borderRadius: BorderRadius.circular(16)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title,
          style: const TextStyle(
              fontFamily: 'Syne',
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A1A))),
      const SizedBox(height: 16),
      ...children.map(
              (c) => Padding(padding: const EdgeInsets.only(bottom: 12), child: c)),
    ]),
  );
}

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final IconData? icon;
  final bool enabled;
  final TextInputType keyboardType;
  final String? hint;
  final String? Function(String?)? validator;
  final TextCapitalization textCapitalization;

  const _Field({
    required this.label,
    required this.controller,
    required this.icon,
    required this.enabled,
    this.keyboardType = TextInputType.text,
    this.hint,
    this.validator,
    this.textCapitalization = TextCapitalization.words,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label,
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6B6B6B))),
      const SizedBox(height: 6),
      TextFormField(
        controller: controller,
        enabled: enabled,
        keyboardType: keyboardType,
        textCapitalization: textCapitalization,
        style: const TextStyle(fontSize: 14, color: Color(0xFF1A1A1A)),
        validator: validator,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(
              color: Color(0xFFB0B0B0), fontSize: 14),
          prefixIcon: icon != null
              ? Icon(icon, size: 17, color: const Color(0xFF9B9B9B))
              : null,
          filled: true,
          fillColor: enabled ? Colors.white : const Color(0xFFF9F9F9),
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 13),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(
                  color: Color(0xFFFF5A00), width: 1.5)),
          disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFF0F0F0))),
        ),
      ),
    ],
  );
}

class _SettingRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;
  const _SettingRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(9)),
          child: Icon(icon, size: 17, color: const Color(0xFF6B6B6B)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF1A1A1A))),
        ),
        trailing ??
            const Icon(Icons.chevron_right,
                color: Color(0xFFB0B0B0), size: 18),
      ]),
    ),
  );
}

class _OutlineBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final Color color;
  final Color borderColor;
  final Color? bgColor;

  const _OutlineBtn({
    required this.label,
    required this.icon,
    required this.onTap,
    this.color = const Color(0xFFFF5A00),
    this.borderColor = const Color(0xFFFFDDCC),
    this.bgColor,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
          color: bgColor ?? Colors.white,
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color)),
      ]),
    ),
  );
}