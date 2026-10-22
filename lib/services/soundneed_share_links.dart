/// Public hosts supported by SoundNeed share links.
///
/// New links use the branded Pages host. The Worker host stays supported so
/// links that have already been sent continue to open in the app.
class SoundNeedShareLinks {
  SoundNeedShareLinks._();

  static const String baseUrl = 'https://soundneed-links.pages.dev';
  static const String host = 'soundneed-links.pages.dev';
  static const String legacyHost =
      'soundneed-shares.breinermuleth64.workers.dev';

  static bool supportsHost(String value) =>
      value == host || value == legacyHost;
}
