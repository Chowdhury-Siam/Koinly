import 'package:flutter/material.dart';

class KoinlyAppIcon extends StatelessWidget {
  const KoinlyAppIcon({super.key, this.size = 88});

  final double size;

  @override
  Widget build(BuildContext context) {
    // The onboarding mark uses the transparent Koinly artwork so the logo
    // visually belongs to the page instead of sitting on a black app-icon tile.
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Image.asset(
          'assets/icons/koinly_mark.png',
          width: size * .82,
          height: size * .92,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          errorBuilder: (context, error, stackTrace) => Icon(
            Icons.account_balance_wallet_rounded,
            size: size * .58,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }
}
