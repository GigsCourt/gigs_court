import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import '../../config/theme.dart';

class ServicesScreen extends StatefulWidget {
  const ServicesScreen({super.key});

  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedServiceIds = {};
  final Set<String> _selectedServiceNames = {};

  List<Map<String, dynamic>> _allServices = [];
  List<Map<String, dynamic>> _filteredServices = [];
  List<Map<String, dynamic>> _searchResults = [];
  List<String> _categories = [];
  String? _selectedCategory;
  bool _isLoading = true;
  bool _isSearching = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadServices();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadServices() async {
    try {
      final response = await _supabase
          .from('services')
          .select()
          .eq('status', 'approved')
          .order('name');

      final services = List<Map<String, dynamic>>.from(response);
      final categories = services
          .map((s) => s['category'] as String)
          .toSet()
          .toList()
        ..sort();

      if (mounted) {
        setState(() {
          _allServices = services;
          _filteredServices = services;
          _categories = categories;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _onSearchChanged(String query) {
    if (query.trim().isEmpty) {
      setState(() {
        _isSearching = false;
        _searchResults = [];
      });
      return;
    }

    setState(() => _isSearching = true);

    final lowerQuery = query.trim().toLowerCase();
    final results = _allServices.where((service) {
      final name = (service['name'] as String).toLowerCase();
      return name.contains(lowerQuery);
    }).toList();

    setState(() {
      _searchResults = results;
    });
  }

  void _onCategorySelected(String category) {
    setState(() {
      _selectedCategory = category;
      _filteredServices = _allServices
          .where((s) => s['category'] == category)
          .toList();
      _isSearching = false;
      _searchController.clear();
      _searchResults = [];
    });
  }

  void _toggleService(String id, String name) {
    setState(() {
      if (_selectedServiceIds.contains(id)) {
        _selectedServiceIds.remove(id);
        _selectedServiceNames.remove(name);
      } else {
        _selectedServiceIds.add(id);
        _selectedServiceNames.add(name);
      }
    });
  }

  bool _isSelected(String id) => _selectedServiceIds.contains(id);

  Future<void> _submitCustomService(String serviceName) async {
    try {
      await _supabase.from('services').insert({
        'name': serviceName,
        'category': _selectedCategory ?? 'Uncategorized',
        'status': 'pending',
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"$serviceName" submitted for approval.'),
          backgroundColor: AppColors.success,
        ),
      );
      _searchController.clear();
      setState(() {
        _isSearching = false;
        _searchResults = [];
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to submit. Please try again.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _handleContinue() async {
    setState(() => _isSaving = true);
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    setState(() => _isSaving = false);
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, size: 20.sp),
          onPressed: () => context.pop(),
        ),
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 24.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: 16.h),
                    Text('What services do you offer?', style: AppTextStyles.headline2),
                    SizedBox(height: 8.h),
                    Text(
                      'Select the services you offer. If you skip, you won\'t appear as a provider yet. You can add or submit custom services anytime from your profile to be discoverable to clients who needs your service.',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.primary.withValues(alpha: 0.6),
                      ),
                    ),
                    SizedBox(height: 16.h),
                    TextField(
                      controller: _searchController,
                      onChanged: _onSearchChanged,
                      style: AppTextStyles.bodyMedium,
                      decoration: InputDecoration(
                        hintText: 'Search services...',
                        hintStyle: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.primary.withValues(alpha: 0.3),
                        ),
                        prefixIcon: Icon(
                          Icons.search,
                          size: 20.sp,
                          color: AppColors.primary.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              if (_selectedServiceNames.isNotEmpty)
                Container(
                  height: 44.h,
                  margin: EdgeInsets.only(top: 8.h),
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.symmetric(horizontal: 24.w),
                    itemCount: _selectedServiceNames.length,
                    separatorBuilder: (_, _) => SizedBox(width: 8.w),
                    itemBuilder: (context, index) {
                      final name = _selectedServiceNames.elementAt(index);
                      return Chip(
                        label: Text(
                          name,
                          style: AppTextStyles.bodySmall.copyWith(color: AppColors.white),
                        ),
                        backgroundColor: AppColors.primary,
                        deleteIcon: Icon(Icons.close, size: 16.sp, color: AppColors.white),
                        onDeleted: () {
                          final id = _selectedServiceIds.elementAt(index);
                          _toggleService(id, name);
                        },
                      );
                    },
                  ),
                ),

              SizedBox(height: 8.h),

              if (!_isSearching)
                SizedBox(
                  height: 36.h,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.symmetric(horizontal: 24.w),
                    itemCount: _categories.length,
                    separatorBuilder: (_, _) => SizedBox(width: 8.w),
                    itemBuilder: (context, index) {
                      final category = _categories[index];
                      final isSelected = category == _selectedCategory;
                      return GestureDetector(
                        onTap: () => _onCategorySelected(category),
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 6.h),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(20.r),
                          ),
                          child: Text(
                            category,
                            style: AppTextStyles.bodySmall.copyWith(
                              color: isSelected ? AppColors.white : AppColors.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

              SizedBox(height: 8.h),

              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _isSearching
                        ? _buildSearchResults()
                        : _buildCategoryServices(),
              ),

              Padding(
                padding: EdgeInsets.fromLTRB(24.w, 12.h, 24.w, 32.h),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 48.h,
                      child: ElevatedButton(
                        onPressed: (_selectedServiceIds.isNotEmpty && !_isSaving)
                            ? _handleContinue
                            : null,
                        child: _isSaving
                            ? SizedBox(
                                height: 20.h,
                                width: 20.w,
                                child: const CircularProgressIndicator(
                                  color: AppColors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text('Continue', style: AppTextStyles.button),
                      ),
                    ),
                    SizedBox(height: 6.h),
                    GestureDetector(
                      onTap: () => context.go('/home'),
                      child: Text(
                        'Skip for now',
                        style: AppTextStyles.bodySmall.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    final query = _searchController.text.trim();

    return ListView(
      padding: EdgeInsets.symmetric(horizontal: 24.w),
      children: [
        ..._searchResults.map((service) {
          final id = service['id'] as String;
          final name = service['name'] as String;
          final category = service['category'] as String;
          final selected = _isSelected(id);

          return ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: Checkbox(
              value: selected,
              activeColor: AppColors.primary,
              onChanged: (_) => _toggleService(id, name),
            ),
            title: Text(name, style: AppTextStyles.bodyMedium),
            subtitle: Text(category, style: AppTextStyles.caption),
            onTap: () => _toggleService(id, name),
          );
        }),
        if (query.isNotEmpty &&
            !_searchResults.any((s) =>
                (s['name'] as String).toLowerCase() == query.toLowerCase()))
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.add_circle_outline,
              color: AppColors.primary.withValues(alpha: 0.6),
              size: 22.sp,
            ),
            title: Text(
              'Can\'t find it? Submit "$query" for approval',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.primary.withValues(alpha: 0.7),
              ),
            ),
            onTap: () => _submitCustomService(query),
          ),
      ],
    );
  }

  Widget _buildCategoryServices() {
    if (_filteredServices.isEmpty) {
      return Center(
        child: Text(
          'Select a category to see services',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.primary.withValues(alpha: 0.4),
          ),
        ),
      );
    }

    return ListView(
      padding: EdgeInsets.symmetric(horizontal: 24.w),
      children: _filteredServices.map((service) {
        final id = service['id'] as String;
        final name = service['name'] as String;
        final selected = _isSelected(id);

        return ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: Checkbox(
            value: selected,
            activeColor: AppColors.primary,
            onChanged: (_) => _toggleService(id, name),
          ),
          title: Text(name, style: AppTextStyles.bodyMedium),
          onTap: () => _toggleService(id, name),
        );
      }).toList(),
    );
  }
}