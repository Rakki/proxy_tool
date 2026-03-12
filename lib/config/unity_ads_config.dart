class UnityAdsConfig {
  const UnityAdsConfig._();

  static const bool testMode = false;

  // Fill these before expecting real ads to render.
  static const String androidGameId = '6064298';
  static const String androidBannerPlacementId = 'Banner_Android';

  static bool get isConfigured =>
      androidGameId.isNotEmpty && androidBannerPlacementId.isNotEmpty;
}
