import 'package:flutter/material.dart';
import 'package:nav_bar/nav_bar.dart';

import 'bottom/bottom_home.dart';
import 'bottom/bottom_feed.dart';
import 'bottom/bottom_shop.dart';
import 'bottom/bottom_auction.dart';
import 'bottom/bottom_chat.dart';
import 'bottom/bottom_profile.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const BottomHome(),
    const BottomFeed(),
    const BottomShop(),
    const BottomAuction(),
    const BottomChat(),
    const BottomProfile(),
  ];
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: _screens[_selectedIndex],
      bottomNavigationBar: FuturisticNavBar(
        selectedIndex: _selectedIndex,
        onItemSelected: (index) {
          setState(() => _selectedIndex = index);
        },
        items: [
          NavBarItem(icon: Icons.home),
          NavBarItem(icon: Icons.rss_feed),
          NavBarItem(icon: Icons.shopping_bag),
          NavBarItem(icon: Icons.gavel),
          NavBarItem(icon: Icons.chat),
          NavBarItem(icon: Icons.person),
        ],
        style: NavBarStyle.prism,
        theme: FuturisticTheme.cyberpunk(),
        iconAnimationType: IconAnimationType.fade,
        showGlow: true,
        showLiquid: true,
        iconLabelSpacing: 0.0, // ← основное изменение
      ),
    );
  }
}
