// Hug - Profile screen (photo, name, menu, OCPS contact details, log out)

import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/colors.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  final String userName;

  const ProfileScreen({
    super.key,
    required this.userName,
  });
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // ---------------------------------------------------
  // LOGGED-IN USER DATA (saved in the metadata during sign up)
  // ---------------------------------------------------
  Map<String, dynamic>? get _meta =>
      Supabase.instance.client.auth.currentUser?.userMetadata;

  // First + middle + last name + suffix (empty parts are skipped)
  String get fullName {
    final m = _meta;
    final parts = [
      m?['first_name'],
      m?['middle_name'],
      m?['last_name'],
      m?['suffix'],
    ].map((e) => (e as String?)?.trim() ?? '').where((e) => e.isNotEmpty);
    return parts.isEmpty ? '--' : parts.join(' ');
  }

  String get studentNumber => (_meta?['student_number'] as String?) ?? '--';

  // ---------------------------------------------------
  // PROFILE PHOTO
  // ---------------------------------------------------
  final ImagePicker _picker = ImagePicker();

  // Link of the photo saved in Supabase Storage (null = no photo yet)
  String? _avatarUrl;

  // true while the photo is uploading
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _avatarUrl = _meta?['avatar_url'] as String?;
  }

  // Camera button: ask where the photo comes from (or remove it)
  Future<void> _choosePhotoSource() async {
    final bool hasPhoto = _avatarUrl != null && _avatarUrl!.isNotEmpty;
    final String? choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            // Only shown when the user already has a photo
            if (hasPhoto)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: kCoral),
                title: const Text(
                  'Remove photo',
                  style: TextStyle(color: kCoral),
                ),
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == 'camera') await _pickAndUpload(ImageSource.camera);
    if (choice == 'gallery') await _pickAndUpload(ImageSource.gallery);
    if (choice == 'remove') await _removePhoto();
  }

  // Delete the photo from Storage and clear the link in the metadata
  Future<void> _removePhoto() async {
    setState(() => _uploading = true);
    try {
      final client = Supabase.instance.client;
      final String userId = client.auth.currentUser!.id;
      await client.storage.from('avatars').remove(['$userId/avatar.jpg']);
      await client.auth.updateUser(UserAttributes(data: {'avatar_url': ''}));
      if (!mounted) return;
      setState(() => _avatarUrl = null);
    } catch (error) {
      debugPrint('HUG photo remove failed: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not remove photo. Try again.')),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  // Pick the photo, upload it, then save its link in the user's metadata
  Future<void> _pickAndUpload(ImageSource source) async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );
      if (picked == null) return;

      setState(() => _uploading = true);

      final client = Supabase.instance.client;
      final String userId = client.auth.currentUser!.id;
      final bytes = await picked.readAsBytes();
      final String path = '$userId/avatar.jpg';

      await client.storage
          .from('avatars')
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          );

      // The ?t= part makes the app show the new photo, not the old cached one
      final String url =
          '${client.storage.from('avatars').getPublicUrl(path)}'
          '?t=${DateTime.now().millisecondsSinceEpoch}';

      await client.auth.updateUser(UserAttributes(data: {'avatar_url': url}));

      if (!mounted) return;
      setState(() => _avatarUrl = url);
    } catch (error) {
      debugPrint('HUG photo upload failed: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update photo. Try again.')),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  // ---------------------------------------------------
  // OCPS CONTACT DETAILS
  // ---------------------------------------------------
  static const String ocpsEmail = 'guidance@pup.edu.ph';
  static const String ocpsPhone =
      '(63 2) 335-1PUP (335-1787) or\n335-1777 local 6321';
  static const String ocpsAddress =
      '2/F Charlie del Rosario Student\nDevelopment Center\n'
      'PUP A. Mabini Campus, Anonas St., Sta.\nMesa Manila, Philippines 1016';

  // Colors only used in this screen
  static const Color kBackground = Color(0xFFF4F4F4);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kBackground,
      child: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          // Extra space at the bottom so the bottom bar does not cover content
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 130),
          child: Column(
            children: [
              const Text(
                'Profile',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 18),
              buildPhoto(),
              const SizedBox(height: 10),
              Text(
                fullName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                studentNumber,
                style: const TextStyle(fontSize: 13, color: Colors.black87),
              ),
              const SizedBox(height: 18),
              buildMenuCard(context),
              const SizedBox(height: 12),
              buildContactCard(),
              const SizedBox(height: 12),
              buildLogoutRow(context),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------
  // PHOTO: round picture with a camera button
  // ---------------------------------------------------
  Widget buildPhoto() {
    // The grey person icon (shown when there is no photo yet)
    final Widget placeholder = Container(
      width: 96,
      height: 96,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFFD9D9D9),
      ),
      child: const Icon(Icons.person, size: 60, color: Colors.white),
    );

    final String? url = _avatarUrl;

    return SizedBox(
      width: 100,
      height: 100,
      child: Stack(
        children: [
          // The user's photo, or the placeholder
          if (url == null || url.isEmpty)
            placeholder
          else
            ClipOval(
              child: Image.network(
                url,
                width: 96,
                height: 96,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => placeholder,
              ),
            ),

          // Spinner while uploading
          if (_uploading)
            Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black38,
              ),
              child: const Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Colors.white,
                  ),
                ),
              ),
            ),

          // Camera button at the bottom right
          Positioned(
            right: 0,
            bottom: 0,
            child: GestureDetector(
              onTap: _uploading ? null : _choosePhotoSource,
              child: Container(
                width: 30,
                height: 30,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
                child: const Icon(
                  Icons.photo_camera_outlined,
                  size: 18,
                  color: Colors.black,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------
  // MENU CARD: list of settings rows
  // ---------------------------------------------------
  Widget buildMenuCard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        children: [
          buildMenuItem(
            icon: Icons.manage_accounts_outlined,
            label: 'Personal Information',
            onTap: () {
              // TODO: open the Personal Information screen here
            },
          ),
          buildMenuItem(
            icon: Icons.notifications_none,
            label: 'Notifications',
            onTap: () {
              // TODO: open the Notifications screen here
            },
          ),
          buildMenuItem(
            icon: Icons.settings_outlined,
            label: 'Account and Security',
            onTap: () {
              // TODO: open the Account and Security screen here
            },
          ),
          buildMenuItem(
            icon: Icons.fact_check_outlined,
            label: 'Terms and Conditions',
            onTap: () {
              // TODO: open the Terms and Conditions screen here
            },
          ),
          buildMenuItem(
            icon: Icons.verified_user_outlined,
            label: 'Privacy Policy',
            onTap: () {
              // TODO: open the Privacy Policy screen here
            },
          ),
        ],
      ),
    );
  }

  // One row of the menu: icon, label and arrow
  Widget buildMenuItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 24, color: Colors.black87),
            const SizedBox(width: 18),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 15, color: Colors.black),
              ),
            ),
            const Icon(Icons.chevron_right, size: 24, color: Colors.black),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------
  // OCPS CONTACT CARD: email, phone and address
  // ---------------------------------------------------
  Widget buildContactCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'OCPS Contact Details',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 16),
          // TODO: make these tappable (email, call, map) with url_launcher
          buildContactRow(Icons.mail_outline, ocpsEmail),
          const SizedBox(height: 16),
          buildContactRow(Icons.phone_outlined, ocpsPhone),
          const SizedBox(height: 16),
          buildContactRow(Icons.location_on_outlined, ocpsAddress),
        ],
      ),
    );
  }

  // One contact line: icon and text
  Widget buildContactRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 24, color: Colors.black87),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              height: 1.4,
              color: Colors.black87,
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------
  // LOG OUT ROW
  // ---------------------------------------------------
  Widget buildLogoutRow(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () {
          confirmLogout(context);
        },
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              Icon(Icons.logout, size: 24, color: kCoral),
              SizedBox(width: 18),
              Text('Log out', style: TextStyle(fontSize: 15, color: kCoral)),
            ],
          ),
        ),
      ),
    );
  }

  // Asks "are you sure?" first, so Log out is not pressed by accident
  Future<void> confirmLogout(BuildContext context) async {
    final bool? sure = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: const Text('Log out?'),
          content: const Text('You will need to log in again to use Hug.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.black54),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Log out', style: TextStyle(color: kCoral)),
            ),
          ],
        );
      },
    );

    // The screen may be closed while the dialog was open
    if (sure != true || !context.mounted) return;

    // Clear the Supabase session (even if it fails, still go to Log in)
    try {
      await AuthService().signOut();
    } catch (_) {}
    if (!context.mounted) return;

    // pushAndRemoveUntil clears the old screens,
    // so back does not return to the app after logging out.
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }
}
