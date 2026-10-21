/// Build-time configuration, read from `.env` with `--dart-define-from-file=.env`
/// (see `.env.example`). There are no runtime settings.
library;

const String _envApiBaseUrl = String.fromEnvironment('API_BASE_URL');

/// The McpAi server. Falls back to the local dev server when `.env` does not set it.
const String apiBaseUrl = _envApiBaseUrl == '' ? 'http://127.0.0.1:3000' : _envApiBaseUrl;

/// Optional `Authorization: Bearer` token, for when the server adds authentication.
const String apiToken = String.fromEnvironment('API_TOKEN');
