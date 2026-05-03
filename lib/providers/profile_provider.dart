import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileProvider extends ChangeNotifier {
  final _supabase = Supabase.instance.client;

  String _fullName     = '';
  String _phone        = '';
  String _addressLine1 = '';
  String _addressLine2 = '';
  String _city         = '';
  String _postcode     = '';
  String _country      = 'United Kingdom';
  String _avatarUrl    = ''; // ← Supabase Storage URL
  bool   _isEditing    = false;
  bool   _isSaving     = false;
  bool   _isUploadingImage = false;

  String get fullName        => _fullName;
  String get phone           => _phone;
  String get addressLine1    => _addressLine1;
  String get addressLine2    => _addressLine2;
  String get city            => _city;
  String get postcode        => _postcode;
  String get country         => _country;
  String get avatarUrl       => _avatarUrl;
  bool   get isEditing       => _isEditing;
  bool   get isSaving        => _isSaving;
  bool   get isUploadingImage => _isUploadingImage;

  bool get isProfileComplete =>
      _fullName.isNotEmpty &&
          _phone.isNotEmpty &&
          _addressLine1.isNotEmpty &&
          _city.isNotEmpty &&
          _postcode.isNotEmpty;

  bool get hasAvatar => _avatarUrl.isNotEmpty;

  String get initials {
    final parts = _fullName.trim().split(' ');
    if (parts.length >= 2 && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    if (parts[0].isNotEmpty) return parts[0][0].toUpperCase();
    return 'U';
  }

  // ── Load profile from Supabase + local cache ──────────────────
  Future<void> loadProfile(String email) async {
    try {
      // First load from local cache (fast)
      final prefs = await SharedPreferences.getInstance();
      _fullName     = prefs.getString('profile_fullName')  ?? '';
      _phone        = prefs.getString('profile_phone')     ?? '';
      _addressLine1 = prefs.getString('profile_addr1')     ?? '';
      _addressLine2 = prefs.getString('profile_addr2')     ?? '';
      _city         = prefs.getString('profile_city')      ?? '';
      _postcode     = prefs.getString('profile_postcode')  ?? '';
      _country      = prefs.getString('profile_country')   ?? 'United Kingdom';
      _avatarUrl    = prefs.getString('profile_avatarUrl') ?? '';
      notifyListeners();

      // Then fetch fresh data from Supabase
      final data = await _supabase
          .from('users')
          .select()
          .eq('email', email)
          .maybeSingle();

      if (data != null) {
        _fullName     = data['full_name']     ?? '';
        _phone        = data['phone']         ?? '';
        _addressLine1 = data['address_line1'] ?? '';
        _addressLine2 = data['address_line2'] ?? '';
        _city         = data['city']          ?? '';
        _postcode     = data['postcode']      ?? '';
        _country      = data['country']       ?? 'United Kingdom';
        _avatarUrl    = data['avatar_url']    ?? '';

        // Update local cache
        await _saveToCache();
        notifyListeners();
        debugPrint('ProfileProvider: Loaded from Supabase ✓');
      }
    } catch (e) {
      debugPrint('ProfileProvider: loadProfile error: $e');
    }
  }

  // ── Save profile to Supabase ──────────────────────────────────
  Future<bool> saveProfile({
    required String email,
    required String fullName,
    required String phone,
    required String addressLine1,
    required String addressLine2,
    required String city,
    required String postcode,
    required String country,
  }) async {
    _isSaving = true;
    notifyListeners();

    try {
      debugPrint('ProfileProvider: Saving for $email');

      // Upsert — updates if exists, inserts if not
      await _supabase.from('users').upsert({
        'email':         email,
        'full_name':     fullName,
        'phone':         phone,
        'address_line1': addressLine1,
        'address_line2': addressLine2,
        'city':          city,
        'postcode':      postcode,
        'country':       country,
        if (_avatarUrl.isNotEmpty) 'avatar_url': _avatarUrl,
      }, onConflict: 'email');

      _fullName     = fullName;
      _phone        = phone;
      _addressLine1 = addressLine1;
      _addressLine2 = addressLine2;
      _city         = city;
      _postcode     = postcode;
      _country      = country;

      await _saveToCache();

      _isEditing = false;
      _isSaving  = false;
      notifyListeners();
      debugPrint('ProfileProvider: Saved ✓');
      return true;
    } catch (e) {
      debugPrint('ProfileProvider: saveProfile error: $e');
      _isSaving = false;
      notifyListeners();
      return false;
    }
  }

  // ── Upload avatar image to Supabase Storage ───────────────────
  Future<String?> uploadAvatar({
    required String email,
    required File imageFile,
  }) async {
    _isUploadingImage = true;
    notifyListeners();

    try {
      // Create unique filename using email + timestamp
      final fileExt  = imageFile.path.split('.').last.toLowerCase();
      final fileName = '${email.replaceAll('@', '_').replaceAll('.', '_')}_${DateTime.now().millisecondsSinceEpoch}.$fileExt';
      final filePath = 'avatars/$fileName';

      debugPrint('ProfileProvider: Uploading avatar to $filePath');

      // Upload to Supabase Storage bucket "avatars"
      await _supabase.storage
          .from('avatars')
          .upload(filePath, imageFile,
          fileOptions: const FileOptions(upsert: true));

      // Get public URL
      final publicUrl = _supabase.storage
          .from('avatars')
          .getPublicUrl(filePath);

      debugPrint('ProfileProvider: Avatar URL: $publicUrl');

      // Save URL to DB
      await _supabase.from('users').upsert({
        'email':      email,
        'avatar_url': publicUrl,
      }, onConflict: 'email');

      _avatarUrl = publicUrl;

      // Save to local cache
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('profile_avatarUrl', _avatarUrl);

      _isUploadingImage = false;
      notifyListeners();
      return publicUrl;
    } catch (e) {
      debugPrint('ProfileProvider: uploadAvatar error: $e');
      _isUploadingImage = false;
      notifyListeners();
      return null;
    }
  }

  // ── Save to local SharedPreferences cache ─────────────────────
  Future<void> _saveToCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profile_fullName',  _fullName);
    await prefs.setString('profile_phone',     _phone);
    await prefs.setString('profile_addr1',     _addressLine1);
    await prefs.setString('profile_addr2',     _addressLine2);
    await prefs.setString('profile_city',      _city);
    await prefs.setString('profile_postcode',  _postcode);
    await prefs.setString('profile_country',   _country);
    await prefs.setString('profile_avatarUrl', _avatarUrl);
  }

  void toggleEditing() { _isEditing = !_isEditing; notifyListeners(); }
  void cancelEditing() { _isEditing = false; notifyListeners(); }

  // ── Clear on logout ───────────────────────────────────────────
  Future<void> clearProfile() async {
    _fullName = ''; _phone = ''; _addressLine1 = ''; _addressLine2 = '';
    _city = ''; _postcode = ''; _country = 'United Kingdom';
    _avatarUrl = ''; _isEditing = false; _isSaving = false;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('profile_fullName');
      await prefs.remove('profile_phone');
      await prefs.remove('profile_addr1');
      await prefs.remove('profile_addr2');
      await prefs.remove('profile_city');
      await prefs.remove('profile_postcode');
      await prefs.remove('profile_country');
      await prefs.remove('profile_avatarUrl');
    } catch (_) {}

    notifyListeners();
  }
}