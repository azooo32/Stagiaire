import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/providers/app_provider.dart';
import '../../../../core/models/subject.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/widgets/app_loader.dart';

class SubscriptionsManagementScreen extends StatefulWidget {
  const SubscriptionsManagementScreen({super.key});

  @override
  State<SubscriptionsManagementScreen> createState() =>
      _SubscriptionsManagementScreenState();
}

class _SubscriptionsManagementScreenState
    extends State<SubscriptionsManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  Map<String, dynamic>? _selectedUser;
  List<Map<String, dynamic>> _userSubscriptions = [];
  bool _isLoadingUserSubs = false;

  List<Map<String, dynamic>> _universityRules = [];
  bool _isLoadingUnivRules = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1) {
        _loadUniversityRules();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
      _selectedUser = null;
    });

    final provider = Provider.of<AppProvider>(context, listen: false);
    final results = await provider.searchUsers(query);

    setState(() {
      _searchResults = results;
      _isSearching = false;
    });
  }

  Future<void> _selectUser(Map<String, dynamic> user) async {
    setState(() {
      _selectedUser = user;
      _isLoadingUserSubs = true;
      _userSubscriptions = [];
    });

    final provider = Provider.of<AppProvider>(context, listen: false);
    final subs = await provider.getUserSubscriptions(user['id']);

    setState(() {
      _userSubscriptions = subs;
      _isLoadingUserSubs = false;
    });
  }

  Future<void> _loadUniversityRules() async {
    setState(() {
      _isLoadingUnivRules = true;
    });

    final provider = Provider.of<AppProvider>(context, listen: false);
    final rules = await provider.getUniversityAccessList();

    setState(() {
      _universityRules = rules;
      _isLoadingUnivRules = false;
    });
  }

  Future<void> _deleteSubscription(String id) async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    final success = await provider.deleteUserSubscription(id);
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حذف الاشتراك بنجاح', style: TextStyle(fontFamily: 'Cairo'))),
      );
      if (_selectedUser != null) {
        _selectUser(_selectedUser!);
      }
      provider.fetchUnlockedSubjects();
    }
  }

  Future<void> _deleteUniversityRule(String id) async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    final success = await provider.deleteUniversityAccess(id);
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حذف صلاحية الجامعة بنجاح', style: TextStyle(fontFamily: 'Cairo'))),
      );
      _loadUniversityRules();
      provider.fetchUnlockedSubjects();
    }
  }

  void _showAddSubscriptionDialog() {
    if (_selectedUser == null) return;
    
    final provider = Provider.of<AppProvider>(context, listen: false);
    String selectedType = 'scientific'; // or 'clinical'
    int? selectedSubjectId;
    DateTime? selectedExpiry;

    final scientificSubjects = provider.subjects;
    final clinicalSubjects = provider.clinicalSubjects;

    if (scientificSubjects.isNotEmpty) {
      selectedSubjectId = scientificSubjects.first.id;
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final activeSubjects = selectedType == 'scientific' ? scientificSubjects : clinicalSubjects;
            
            // Adjust selection if switched type
            if (activeSubjects.isNotEmpty &&
                !activeSubjects.any((s) => s.id == selectedSubjectId)) {
              selectedSubjectId = activeSubjects.first.id;
            }

            return AlertDialog(
              backgroundColor: provider.isDarkTheme ? AppColors.surface : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text(
                'إضافة اشتراك جديد',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'الاضافة لـ: ${_selectedUser!['name']}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  
                  // Subject Type Toggle
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(child: Text('علمي', style: TextStyle(fontFamily: 'Cairo'))),
                          selected: selectedType == 'scientific',
                          onSelected: (val) {
                            if (val) {
                              setDialogState(() {
                                selectedType = 'scientific';
                                if (scientificSubjects.isNotEmpty) {
                                  selectedSubjectId = scientificSubjects.first.id;
                                }
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(child: Text('عملي', style: TextStyle(fontFamily: 'Cairo'))),
                          selected: selectedType == 'clinical',
                          onSelected: (val) {
                            if (val) {
                              setDialogState(() {
                                selectedType = 'clinical';
                                if (clinicalSubjects.isNotEmpty) {
                                  selectedSubjectId = clinicalSubjects.first.id;
                                }
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Subject Selector Dropdown
                  DropdownButtonFormField<int>(
                    value: selectedSubjectId,
                    decoration: InputDecoration(
                      labelText: 'اختر المادة',
                      labelStyle: const TextStyle(fontFamily: 'Cairo'),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    items: activeSubjects.map((sub) {
                      return DropdownMenuItem<int>(
                        value: sub.id,
                        child: Text(sub.name, style: const TextStyle(fontFamily: 'Cairo', fontSize: 13)),
                      );
                    }).toList(),
                    onChanged: (val) {
                      setDialogState(() {
                        selectedSubjectId = val;
                      });
                    },
                  ),
                  const SizedBox(height: 16),

                  // Expiry Date Picker Option
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now().add(const Duration(days: 30)),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 3650)),
                      );
                      if (picked != null) {
                        setDialogState(() {
                          selectedExpiry = picked;
                        });
                      }
                    },
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: Text(
                      selectedExpiry == null
                          ? 'تحديد تاريخ الانتهاء (اختياري)'
                          : 'ينتهي في: ${selectedExpiry!.year}-${selectedExpiry!.month}-${selectedExpiry!.day}',
                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                    ),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo', color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (selectedSubjectId == null) return;
                    Navigator.pop(context);
                    
                    final success = await provider.addUserSubscription(
                      userId: _selectedUser!['id'],
                      subjectId: selectedType == 'scientific' ? selectedSubjectId : null,
                      clinicalSubjectId: selectedType == 'clinical' ? selectedSubjectId : null,
                      status: 'active',
                      expiresAt: selectedExpiry,
                    );

                    if (success) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('تم تفعيل الاشتراك بنجاح', style: TextStyle(fontFamily: 'Cairo'))),
                      );
                      _selectUser(_selectedUser!);
                      provider.fetchUnlockedSubjects();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6B4EFF),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('إضافة', style: TextStyle(fontFamily: 'Cairo', color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showAddUniversityRuleDialog() {
    final provider = Provider.of<AppProvider>(context, listen: false);
    final TextEditingController univNameController = TextEditingController();
    bool allScientific = false;
    bool allPractical = false;
    int? selectedSubId;
    int? selectedClinicalSubId;
    DateTime? selectedExpiry;

    final scientificSubjects = provider.subjects;
    final clinicalSubjects = provider.clinicalSubjects;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: provider.isDarkTheme ? AppColors.surface : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text(
                'إضافة صلاحية جامعة',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: univNameController,
                      decoration: InputDecoration(
                        labelText: 'اسم الجامعة',
                        labelStyle: const TextStyle(fontFamily: 'Cairo'),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                    ),
                    const SizedBox(height: 16),

                    // Switches
                    SwitchListTile(
                      title: const Text('فتح كل المواد العلمية', style: TextStyle(fontFamily: 'Cairo', fontSize: 13)),
                      value: allScientific,
                      onChanged: (val) {
                        setDialogState(() {
                          allScientific = val;
                          if (val) selectedSubId = null;
                        });
                      },
                    ),
                    SwitchListTile(
                      title: const Text('فتح كل المواد العملية', style: TextStyle(fontFamily: 'Cairo', fontSize: 13)),
                      value: allPractical,
                      onChanged: (val) {
                        setDialogState(() {
                          allPractical = val;
                          if (val) selectedClinicalSubId = null;
                        });
                      },
                    ),
                    const SizedBox(height: 8),

                    // Specific Scientific Dropdown
                    if (!allScientific && scientificSubjects.isNotEmpty) ...[
                      DropdownButtonFormField<int>(
                        value: selectedSubId,
                        decoration: InputDecoration(
                          labelText: 'مادة علمية محددة',
                          labelStyle: const TextStyle(fontFamily: 'Cairo'),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        items: scientificSubjects.map((sub) {
                          return DropdownMenuItem<int>(
                            value: sub.id,
                            child: Text(sub.name, style: const TextStyle(fontFamily: 'Cairo', fontSize: 13)),
                          );
                        }).toList(),
                        onChanged: (val) {
                          setDialogState(() {
                            selectedSubId = val;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Specific Clinical Dropdown
                    if (!allPractical && clinicalSubjects.isNotEmpty) ...[
                      DropdownButtonFormField<int>(
                        value: selectedClinicalSubId,
                        decoration: InputDecoration(
                          labelText: 'مادة عملية محددة',
                          labelStyle: const TextStyle(fontFamily: 'Cairo'),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        items: clinicalSubjects.map((sub) {
                          return DropdownMenuItem<int>(
                            value: sub.id,
                            child: Text(sub.name, style: const TextStyle(fontFamily: 'Cairo', fontSize: 13)),
                          );
                        }).toList(),
                        onChanged: (val) {
                          setDialogState(() {
                            selectedClinicalSubId = val;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Expiry Date Picker Option
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now().add(const Duration(days: 30)),
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 3650)),
                        );
                        if (picked != null) {
                          setDialogState(() {
                            selectedExpiry = picked;
                          });
                        }
                      },
                      icon: const Icon(Icons.calendar_month_outlined),
                      label: Text(
                        selectedExpiry == null
                            ? 'تحديد تاريخ الانتهاء (اختياري)'
                            : 'ينتهي في: ${selectedExpiry!.year}-${selectedExpiry!.month}-${selectedExpiry!.day}',
                        style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                      ),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo', color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final name = univNameController.text.trim();
                    if (name.isEmpty) return;
                    Navigator.pop(context);

                    final success = await provider.addUniversityAccess(
                      university: name,
                      subjectId: selectedSubId,
                      clinicalSubjectId: selectedClinicalSubId,
                      allScientific: allScientific ? true : null,
                      allPractical: allPractical ? true : null,
                      status: 'active',
                      expiresAt: selectedExpiry,
                    );

                    if (success) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('تم تفعيل صلاحية الجامعة بنجاح', style: TextStyle(fontFamily: 'Cairo'))),
                      );
                      _loadUniversityRules();
                      provider.fetchUnlockedSubjects();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6B4EFF),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('إضافة', style: TextStyle(fontFamily: 'Cairo', color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);
    final isDark = provider.isDarkTheme;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: isDark ? AppColors.bg : const Color(0xFFF8F9FE),
        appBar: AppBar(
          toolbarHeight: 70,
          title: const Text(
            'لوحة إدارة الاشتراكات',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 17, color: Colors.white),
          ),
          centerTitle: true,
          iconTheme: const IconThemeData(color: Colors.white),
          flexibleSpace: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? const [Color(0xFF6047D6), Color(0xFF4930B6)]
                    : const [Color(0xFF7B5EFF), Color(0xFF5B3EEF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Colors.white,
            labelStyle: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13),
            unselectedLabelStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
            tabs: const [
              Tab(text: 'اشتراكات الطلاب'),
              Tab(text: 'صلاحيات الجامعات'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildStudentsTab(isDark, provider),
            _buildUniversitiesTab(isDark, provider),
          ],
        ),
      ),
    );
  }

  Widget _buildStudentsTab(bool isDark, AppProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Search Section
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'ابحث بالاسم أو الإيميل...',
                    hintStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                    prefixIcon: const Icon(Icons.search, size: 20),
                    filled: true,
                    fillColor: isDark ? AppColors.surface : Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                  onSubmitted: (_) => _performSearch(),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _performSearch,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6B4EFF),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                child: const Text('بحث', style: TextStyle(fontFamily: 'Cairo', color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),

        // Split view or List views
        Expanded(
          child: _selectedUser != null
              ? _buildUserSubscriptionsDetails(isDark, provider)
              : _buildSearchResultsList(isDark),
        ),
      ],
    );
  }

  Widget _buildSearchResultsList(bool isDark) {
    if (_isSearching) {
      return const Center(child: LogoSpinner());
    }
    if (_searchResults.isEmpty) {
      return Center(
        child: Text(
          _searchController.text.isEmpty ? 'ابحث عن طالب للبدء' : 'لم يتم العثور على نتائج',
          style: TextStyle(fontFamily: 'Cairo', color: isDark ? AppColors.textMuted : Colors.grey, fontSize: 14),
        ),
      );
    }

    return ListView.builder(
      itemCount: _searchResults.length,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemBuilder: (context, index) {
        final user = _searchResults[index];
        return Card(
          color: isDark ? AppColors.surface : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            title: Text(user['name'] ?? 'بدون اسم', style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14)),
            subtitle: Text('${user['email'] ?? ''} • ${user['university'] ?? ''}', style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, color: Colors.grey)),
            trailing: const Icon(Icons.arrow_forward_ios, size: 14),
            onTap: () => _selectUser(user),
          ),
        );
      },
    );
  }

  Widget _buildUserSubscriptionsDetails(bool isDark, AppProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // User Title Header
        Container(
          padding: const EdgeInsets.all(16),
          color: isDark ? AppColors.surface2 : const Color(0xFFF1F5F9),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() {
                    _selectedUser = null;
                  });
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_selectedUser!['name'] ?? '', style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 15)),
                    Text(_selectedUser!['email'] ?? '', style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: _showAddSubscriptionDialog,
                icon: const Icon(Icons.add, size: 16, color: Colors.white),
                label: const Text('تفعيل مادة', style: TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6B4EFF),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),

        // Subscriptions List
        Expanded(
          child: _isLoadingUserSubs
              ? const Center(child: LogoSpinner())
              : _userSubscriptions.isEmpty
                  ? Center(
                      child: Text('لا يوجد اشتراكات نشطة لهذا الطالب', style: TextStyle(fontFamily: 'Cairo', color: isDark ? AppColors.textMuted : Colors.grey, fontSize: 13)),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _userSubscriptions.length,
                      itemBuilder: (context, index) {
                        final sub = _userSubscriptions[index];
                        String subjectName = 'مادة غير معروفة';
                        
                        if (sub['subject_id'] != null) {
                          final matching = provider.subjects.firstWhere(
                            (s) => s.id == sub['subject_id'],
                            orElse: () => Subject(id: -1, name: 'علمي (ID: ${sub['subject_id']})', description: '', totalQuestions: 0),
                          );
                          subjectName = matching.name;
                        } else if (sub['clinical_subject_id'] != null) {
                          final matching = provider.clinicalSubjects.firstWhere(
                            (s) => s.id == sub['clinical_subject_id'],
                            orElse: () => Subject(id: -1, name: 'عملي (ID: ${sub['clinical_subject_id']})', description: '', totalQuestions: 0),
                          );
                          subjectName = matching.name;
                        }

                        final String typeLabel = sub['subject_id'] != null ? 'علمي' : 'عملي';
                        final expiry = sub['expires_at'] != null 
                            ? DateTime.parse(sub['expires_at']) 
                            : null;
                        final expiryText = expiry != null 
                            ? 'ينتهي في: ${expiry.year}-${expiry.month}-${expiry.day}'
                            : 'اشتراك دائم';

                        return Card(
                          color: isDark ? AppColors.surface : Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: (sub['subject_id'] != null ? Colors.blue : Colors.green).withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    sub['subject_id'] != null ? Icons.book : Icons.local_hospital,
                                    color: sub['subject_id'] != null ? Colors.blue : Colors.green,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(subjectName, style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13)),
                                      Text('$typeLabel • $expiryText', style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, color: Colors.grey)),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                                  onPressed: () {
                                    showDialog(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        backgroundColor: isDark ? AppColors.surface : Colors.white,
                                        title: const Text('تأكيد الحذف', style: TextStyle(fontFamily: 'Cairo')),
                                        content: const Text('هل أنت متأكد من رغبتك في حذف هذا الاشتراك؟', style: TextStyle(fontFamily: 'Cairo')),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(context),
                                            child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo', color: Colors.grey)),
                                          ),
                                          ElevatedButton(
                                            onPressed: () {
                                              Navigator.pop(context);
                                              _deleteSubscription(sub['id']);
                                            },
                                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                            child: const Text('حذف', style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildUniversitiesTab(bool isDark, AppProvider provider) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddUniversityRuleDialog,
        backgroundColor: const Color(0xFF6B4EFF),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _isLoadingUnivRules
          ? const Center(child: LogoSpinner())
          : _universityRules.isEmpty
              ? Center(
                  child: Text('لا توجد صلاحيات جامعات نشطة حاليًا', style: TextStyle(fontFamily: 'Cairo', color: isDark ? AppColors.textMuted : Colors.grey, fontSize: 13)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _universityRules.length,
                  itemBuilder: (context, index) {
                    final rule = _universityRules[index];
                    String accessDetail = '';
                    if (rule['all_scientific'] == true) {
                      accessDetail = 'جميع المواد العلمية';
                    } else if (rule['all_practical'] == true) {
                      accessDetail = 'جميع المواد العملية';
                    } else if (rule['subject_id'] != null) {
                      final matching = provider.subjects.firstWhere(
                        (s) => s.id == rule['subject_id'],
                        orElse: () => Subject(id: -1, name: 'مادة علمية (ID: ${rule['subject_id']})', description: '', totalQuestions: 0),
                      );
                      accessDetail = 'مادة علمية: ${matching.name}';
                    } else if (rule['clinical_subject_id'] != null) {
                      final matching = provider.clinicalSubjects.firstWhere(
                        (s) => s.id == rule['clinical_subject_id'],
                        orElse: () => Subject(id: -1, name: 'مادة عملية (ID: ${rule['clinical_subject_id']})', description: '', totalQuestions: 0),
                      );
                      accessDetail = 'مادة عملية: ${matching.name}';
                    }

                    final expiry = rule['expires_at'] != null 
                        ? DateTime.parse(rule['expires_at']) 
                        : null;
                    final expiryText = expiry != null 
                        ? 'ينتهي في: ${expiry.year}-${expiry.month}-${expiry.day}'
                        : 'صلاحية دائمة';

                    return Card(
                      color: isDark ? AppColors.surface : Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.purple.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.account_balance,
                                color: Colors.purple,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(rule['university'] ?? '', style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13)),
                                  Text('$accessDetail • $expiryText', style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, color: Colors.grey)),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    backgroundColor: isDark ? AppColors.surface : Colors.white,
                                    title: const Text('تأكيد الحذف', style: TextStyle(fontFamily: 'Cairo')),
                                    content: const Text('هل أنت متأكد من رغبتك في حذف صلاحية هذه الجامعة؟', style: TextStyle(fontFamily: 'Cairo')),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo', color: Colors.grey)),
                                      ),
                                      ElevatedButton(
                                        onPressed: () {
                                          Navigator.pop(context);
                                          _deleteUniversityRule(rule['id']);
                                        },
                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                        child: const Text('حذف', style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
