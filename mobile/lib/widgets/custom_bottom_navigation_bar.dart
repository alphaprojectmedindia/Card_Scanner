import 'package:flutter/material.dart';

/// Redesigned 5-position bottom navigation bar matching the Digital Share visual specifications:
/// 1. Home
/// 2. Saved Contacts
/// 3. Scan (Central prominent circular purple button with white QR icon)
/// 4. Meetings
/// 5. My Profile
///
/// Features:
/// - Dark background styling (Color(0xFF111827))
/// - Active selected item highlighted in pure white (Colors.white)
/// - Inactive items displayed in neutral grey (Color(0xFF9CA3AF))
/// - Center Scan button prominently raised with vibrant purple circular container (Color(0xFF7C3AED))
/// - Consistent icon placement above labels
/// - Responsive across varying Android screen sizes with safe area padding
class CustomBottomNavigationBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const CustomBottomNavigationBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final backgroundColor = isDark ? const Color(0xFF111827) : Colors.white;
    final activeColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final inactiveColor = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF64748B);
    const purpleScanColor = Color(0xFF7C3AED); // Vibrant purple for center scan button
    final scanLabelColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final topBorderColor = isDark ? Colors.transparent : const Color(0xFFE2E8F0);
    final shadowColor = isDark
        ? Colors.black.withValues(alpha: 0.25)
        : Colors.black.withValues(alpha: 0.08);

    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border(
          top: BorderSide(
            color: topBorderColor,
            width: isDark ? 0 : 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Container(
          height: 68,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              // 1. Home
              _buildNavItem(
                index: 0,
                icon: Icons.home_outlined,
                activeIcon: Icons.home_rounded,
                label: 'Home',
                isActive: currentIndex == 0,
                activeColor: activeColor,
                inactiveColor: inactiveColor,
                onTap: () => onTap(0),
              ),

              // 2. Saved Contacts
              _buildNavItem(
                index: 1,
                icon: Icons.contacts_outlined,
                activeIcon: Icons.contacts_rounded,
                label: 'Contacts',
                isActive: currentIndex == 1,
                activeColor: activeColor,
                inactiveColor: inactiveColor,
                onTap: () => onTap(1),
              ),

              // 3. Central Prominent Circular Scan Button
              Expanded(
                child: GestureDetector(
                  key: const Key('bottom_nav_scan_button'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onTap(2),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: purpleScanColor,
                          boxShadow: [
                            BoxShadow(
                              color: purpleScanColor.withValues(alpha: 0.45),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.qr_code_scanner_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Scan',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: scanLabelColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 4. Meetings
              _buildNavItem(
                index: 3,
                icon: Icons.calendar_month_outlined,
                activeIcon: Icons.calendar_month_rounded,
                label: 'Meetings',
                isActive: currentIndex == 3,
                activeColor: activeColor,
                inactiveColor: inactiveColor,
                onTap: () => onTap(3),
              ),

              // 5. My Profile
              _buildNavItem(
                index: 4,
                icon: Icons.person_outline_rounded,
                activeIcon: Icons.person_rounded,
                label: 'Profile',
                isActive: currentIndex == 4,
                activeColor: activeColor,
                inactiveColor: inactiveColor,
                onTap: () => onTap(4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required bool isActive,
    required Color activeColor,
    required Color inactiveColor,
    required VoidCallback onTap,
  }) {
    final color = isActive ? activeColor : inactiveColor;

    return Expanded(
      child: InkWell(
        key: Key('bottom_nav_item_$index'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: Colors.white10,
        highlightColor: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isActive ? activeIcon : icon,
                color: color,
                size: 24,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                  color: color,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

