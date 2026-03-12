import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:unity_ads_plugin/unity_ads_plugin.dart';

import '../config/unity_ads_config.dart';
import 'glass_panel.dart';

class UnityBannerSlot extends StatelessWidget {
  const UnityBannerSlot({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid || !UnityAdsConfig.isConfigured) {
      return const SizedBox.shrink();
    }

    return GlassPanel(
      borderRadius: BorderRadius.circular(28),
      padding: const EdgeInsets.all(14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: SizedBox(
          width: double.infinity,
          height: 84,
          child: UnityBannerAd(
            placementId: UnityAdsConfig.androidBannerPlacementId,
            size: BannerSize.standard,
            onLoad: (String placementId) {},
            onClick: (String placementId) {},
            onFailed: (String placementId, dynamic error, String message) {},
          ),
        ),
      ),
    );
  }
}
