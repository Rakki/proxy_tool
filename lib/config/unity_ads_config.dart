class UnityAdsConfig {
  const UnityAdsConfig._();

  static const bool testMode = false;

  // Fill these before expecting real ads to render.
  static const String androidGameId = '';
  static const String androidBannerPlacementId = '';

  static bool get isConfigured =>
      androidGameId.isNotEmpty && androidBannerPlacementId.isNotEmpty;
}
