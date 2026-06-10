import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme_colors.dart';

class MainShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const MainShell({
    super.key,
    required this.navigationShell,
  });

  void _onTap(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        final router = GoRouter.of(context);
        if (router.canPop()) {
          router.pop();
        }
      },
      child: Scaffold(
        body: navigationShell,
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: BottomNavigationBar(
              currentIndex: navigationShell.currentIndex,
              onTap: _onTap,
              type: BottomNavigationBarType.fixed,
              backgroundColor: AppColors.cardBg(context),
              selectedItemColor: AppColors.primaryIndigo,
              unselectedItemColor: AppColors.textMuted(context),
              selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.home_outlined),
                  activeIcon: Icon(Icons.home_rounded),
                  label: 'Home',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.video_camera_front_outlined),
                  activeIcon: Icon(Icons.video_camera_front_rounded),
                  label: 'Consult',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.folder_outlined),
                  activeIcon: Icon(Icons.folder_rounded),
                  label: 'Records',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.school_outlined),
                  activeIcon: Icon(Icons.school_rounded),
                  label: 'Study Hub',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.science_outlined),
                  activeIcon: Icon(Icons.science_rounded),
                  label: 'Labs',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
