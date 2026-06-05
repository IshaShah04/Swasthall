import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ActivePatientNotifier extends ValueNotifier<String?> {
  ActivePatientNotifier() : super(null);

  void setChild(String? childId) {
    value = childId;
  }

  String get currentId {
    if (value != null) return value!;
    final user = Supabase.instance.client.auth.currentUser;
    return user?.id ?? '';
  }
}

final activePatientNotifier = ActivePatientNotifier();
