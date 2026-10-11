import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../../core/network/api_exception.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../shared/widgets/primary_button.dart';
import '../../../../../shared/widgets/state_views.dart';
import '../../../../gallery/data/models/gallery_item.dart';
import '../../../services/presentation/providers/owner_service_providers.dart';
import '../providers/owner_gallery_providers.dart';

class GalleryItemFormScreen extends ConsumerWidget {
  const GalleryItemFormScreen({super.key, this.itemId});

  final String? itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (itemId == null) {
      return Scaffold(appBar: AppBar(title: const Text('Add to gallery')), body: const _GalleryItemForm());
    }
    final itemAsync = ref.watch(ownerGalleryItemProvider(itemId!));
    return Scaffold(
      appBar: AppBar(title: const Text('Edit gallery item')),
      body: itemAsync.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(message: error is ApiException ? error.message : 'Could not load this item.'),
        data: (item) => _GalleryItemForm(itemId: itemId, existing: item),
      ),
    );
  }
}

enum _AddMode { photo, upload, instagram }

class _GalleryItemForm extends ConsumerStatefulWidget {
  const _GalleryItemForm({this.itemId, this.existing});

  final String? itemId;
  final GalleryItem? existing;

  @override
  ConsumerState<_GalleryItemForm> createState() => _GalleryItemFormState();
}

class _GalleryItemFormState extends ConsumerState<_GalleryItemForm> {
  late final _captionController = TextEditingController(text: widget.existing?.caption);
  late final _instagramController = TextEditingController(text: widget.existing?.instagramUrl);
  _AddMode _mode = _AddMode.photo;
  String? _category;
  String? _serviceId;
  bool _isActive = true;
  String? _videoPath;
  String? _photoPath;
  String? _thumbnailPath;
  bool _removeVideo = false;
  bool _removeThumbnail = false;
  bool _isSubmitting = false;
  String? _errorMessage;
  Map<String, List<String>>? _fieldErrors;

  bool get _isEdit => widget.itemId != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _category = existing.category;
      _serviceId = existing.service?.id;
      _isActive = existing.isActive;
    }
  }

  @override
  void dispose() {
    _captionController.dispose();
    _instagramController.dispose();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    final picked = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _videoPath = picked.path;
        _removeVideo = false;
      });
    }
  }

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2048);
    if (picked != null) setState(() => _photoPath = picked.path);
  }

  Future<void> _pickThumbnail() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1080);
    if (picked != null) {
      setState(() {
        _thumbnailPath = picked.path;
        _removeThumbnail = false;
      });
    }
  }

  Future<void> _submit() async {
    final instagramUrl = _instagramController.text.trim();
    final needsInstagram = !_isEdit && _mode == _AddMode.instagram;
    if (!_isEdit && _mode == _AddMode.photo && _photoPath == null) {
      setState(() => _errorMessage = 'Choose a photo to upload.');
      return;
    }
    if (!_isEdit && _mode == _AddMode.upload && _videoPath == null) {
      setState(() => _errorMessage = 'Choose a video to upload.');
      return;
    }
    if (needsInstagram && instagramUrl.isEmpty) {
      setState(() => _errorMessage = 'Paste an Instagram reel or post link.');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
      _fieldErrors = null;
    });
    try {
      final repository = ref.read(ownerGalleryRepositoryProvider);
      if (_isEdit) {
        await repository.update(
          widget.itemId!,
          caption: _captionController.text.trim(),
          category: _category,
          clearCategory: _category == null && widget.existing?.category != null,
          serviceId: _serviceId,
          clearService: _serviceId == null && widget.existing?.service != null,
          instagramUrl: instagramUrl.isEmpty || instagramUrl == widget.existing?.instagramUrl ? null : instagramUrl,
          isActive: _isActive,
          videoPath: _videoPath,
          thumbnailPath: _thumbnailPath,
          removeVideo: _removeVideo,
          removeThumbnail: _removeThumbnail,
        );
      } else {
        await repository.create(
          videoPath: _mode == _AddMode.upload ? _videoPath : null,
          imagePath: _mode == _AddMode.photo ? _photoPath : null,
          thumbnailPath: _thumbnailPath,
          instagramUrl: _mode == _AddMode.instagram ? instagramUrl : (instagramUrl.isEmpty ? null : instagramUrl),
          caption: _captionController.text.trim(),
          category: _category,
          serviceId: _serviceId,
          isActive: _isActive,
        );
      }
      if (mounted) context.pop();
    } on ApiException catch (e) {
      setState(() {
        _errorMessage = e.message;
        _fieldErrors = e.fieldErrors;
      });
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String? _fieldError(String field) => _fieldErrors?[field]?.first;

  @override
  Widget build(BuildContext context) {
    final servicesAsync = ref.watch(allServicesProvider);
    final existing = widget.existing;
    final hasHostedVideo = (existing?.hasNativeVideo ?? false) && !_removeVideo;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        if (!_isEdit) ...[
          SegmentedButton<_AddMode>(
            segments: const [
              ButtonSegment(value: _AddMode.photo, icon: Icon(Icons.photo_outlined), label: Text('Photo')),
              ButtonSegment(value: _AddMode.upload, icon: Icon(Icons.upload_file), label: Text('Video')),
              ButtonSegment(value: _AddMode.instagram, icon: Icon(Icons.link), label: Text('Instagram link')),
            ],
            selected: {_mode},
            onSelectionChanged: (value) => setState(() => _mode = value.first),
          ),
          const SizedBox(height: AppSpacing.md),
        ] else ...[
          Text(
            (existing?.isPhoto ?? false) ? 'This is a photo. Customers can view it full-screen and book the linked service.' : hasHostedVideo ? 'This item has a hosted video and plays inside the app.' : 'Instagram only: customers see the thumbnail and a "View on Instagram" link. Upload the original video to play it in the app.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (!_isEdit && _mode == _AddMode.photo) ...[
          OutlinedButton.icon(
            key: const Key('gallery-pick-photo'),
            onPressed: _isSubmitting ? null : _pickPhoto,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: Text(_photoPath != null ? 'Photo selected: ${_photoPath!.split(Platform.pathSeparator).last}' : 'Choose photo (JPG, PNG or WebP)'),
          ),
          if (_fieldError('image') != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_fieldError('image')!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          const SizedBox(height: AppSpacing.md),
        ],
        if ((_isEdit && !(existing?.isPhoto ?? false)) || (!_isEdit && _mode == _AddMode.upload)) ...[
          OutlinedButton.icon(
            key: const Key('gallery-pick-video'),
            onPressed: _isSubmitting ? null : _pickVideo,
            icon: const Icon(Icons.video_file_outlined),
            label: Text(_videoPath != null ? 'Video selected: ${_videoPath!.split(Platform.pathSeparator).last}' : (hasHostedVideo ? 'Replace video (MP4 or MOV)' : 'Choose video (MP4 or MOV)')),
          ),
          if (_fieldError('video') != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_fieldError('video')!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          if (_isEdit && hasHostedVideo && _videoPath == null && (existing?.instagramUrl != null))
            TextButton(onPressed: () => setState(() => _removeVideo = true), child: const Text('Remove hosted video (keep Instagram link)')),
          const SizedBox(height: AppSpacing.md),
        ],
        if (_isEdit || _mode == _AddMode.instagram) ...[
          TextField(
            controller: _instagramController,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(labelText: 'Instagram reel or post link', hintText: 'https://www.instagram.com/reel/…', errorText: _fieldError('instagram_url')),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (!(existing?.isPhoto ?? false) && !(!_isEdit && _mode == _AddMode.photo)) OutlinedButton.icon(
          onPressed: _isSubmitting ? null : _pickThumbnail,
          icon: const Icon(Icons.image_outlined),
          label: Text(_thumbnailPath != null ? 'Thumbnail selected' : 'Choose thumbnail (optional)'),
        ),
        if (_fieldError('thumbnail') != null && !(existing?.isPhoto ?? false)) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_fieldError('thumbnail')!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _captionController,
          maxLines: 3,
          maxLength: 2200,
          decoration: InputDecoration(labelText: 'Caption', errorText: _fieldError('caption')),
        ),
        DropdownButtonFormField<String?>(
          initialValue: _category,
          decoration: const InputDecoration(labelText: 'Category'),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('No category')),
            for (final c in galleryCategories) DropdownMenuItem<String?>(value: c.value, child: Text(c.label)),
          ],
          onChanged: (value) => setState(() => _category = value),
        ),
        const SizedBox(height: AppSpacing.md),
        servicesAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => const Text('Could not load services for "Book This Style".'),
          data: (services) => DropdownButtonFormField<String?>(
            initialValue: services.any((s) => s.id == _serviceId) ? _serviceId : null,
            isExpanded: true,
            decoration: InputDecoration(labelText: 'Linked service ("Book This Style")', errorText: _fieldError('service_id')),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('None')),
              for (final s in services) DropdownMenuItem<String?>(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (value) => setState(() => _serviceId = value),
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Visible to customers'),
          value: _isActive,
          onChanged: (value) => setState(() => _isActive = value),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(_errorMessage!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: AppSpacing.md),
        if (_isSubmitting && (_videoPath != null || _photoPath != null)) const Padding(padding: EdgeInsets.only(bottom: AppSpacing.sm), child: Text('Uploading… keep the app open.')),
        PrimaryButton(label: _isEdit ? 'Save changes' : 'Add to gallery', isLoading: _isSubmitting, onPressed: _submit),
      ],
    );
  }
}
