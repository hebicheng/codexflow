import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/app_models.dart';

class ApiError implements Exception {
  ApiError(this.message);

  final String message;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({
    required String baseUrlString,
    http.Client? client,
  })  : _baseUri = Uri.parse(baseUrlString),
        _client = client ?? http.Client();

  final Uri _baseUri;
  final http.Client _client;

  Future<DashboardResponse> dashboard() async {
    final json = await _decodeMap('/api/v1/dashboard');
    return DashboardResponse.fromJson(json);
  }

  Future<SessionDetail> sessionDetail(String id) async {
    final json = await _decodeMap('/api/v1/sessions/$id');
    return SessionDetail.fromJson(json);
  }

  Future<void> refreshSessions() async {
    await _sendJson(
      '/api/v1/sessions',
      method: 'POST',
      body: <String, dynamic>{'action': 'refresh'},
    );
  }

  Future<SessionSummary> startSession({
    required String cwd,
    required String prompt,
    required String agentId,
  }) async {
    final json = await _decodeMap(
      '/api/v1/sessions',
      method: 'POST',
      body: <String, dynamic>{
        'action': 'start',
        'cwd': cwd,
        'prompt': prompt,
        'agent': agentId,
      },
      timeout: const Duration(seconds: 45),
    );
    return SessionSummary.fromJson(json);
  }

  Future<SessionSummary> resumeSession(String id) async {
    final json = await _decodeMap(
      '/api/v1/sessions/$id/resume',
      method: 'POST',
      body: const <String, dynamic>{},
    );
    return SessionSummary.fromJson(json);
  }

  Future<void> endSession(String id) async {
    await _sendJson(
      '/api/v1/sessions/$id/end',
      method: 'POST',
      body: const <String, dynamic>{},
    );
  }

  Future<void> archiveSession(String id) async {
    await _sendJson(
      '/api/v1/sessions/$id/archive',
      method: 'POST',
      body: const <String, dynamic>{},
    );
  }

  Future<TurnDetail> startTurn({
    required String sessionId,
    required String prompt,
    List<String> imageUploadIds = const <String>[],
  }) async {
    final json = await _decodeMap(
      '/api/v1/sessions/$sessionId/turns/start',
      method: 'POST',
      body: <String, dynamic>{
        'prompt': prompt,
        'inputs': _buildInputs(prompt: prompt, imageUploadIds: imageUploadIds),
      },
    );
    return TurnDetail.fromJson(json);
  }

  Future<void> steerTurn({
    required String sessionId,
    required String turnId,
    required String prompt,
    List<String> imageUploadIds = const <String>[],
  }) async {
    await _sendJson(
      '/api/v1/sessions/$sessionId/turns/steer',
      method: 'POST',
      body: <String, dynamic>{
        'turnId': turnId,
        'prompt': prompt,
        'inputs': _buildInputs(prompt: prompt, imageUploadIds: imageUploadIds),
      },
    );
  }

  Future<void> interruptTurn({
    required String sessionId,
    required String turnId,
  }) async {
    await _sendJson(
      '/api/v1/sessions/$sessionId/turns/interrupt',
      method: 'POST',
      body: <String, dynamic>{'turnId': turnId},
    );
  }

  Future<void> resolveApproval({
    required String id,
    required Object? result,
  }) async {
    await _sendJson(
      '/api/v1/approvals/$id/resolve',
      method: 'POST',
      body: <String, dynamic>{'result': result},
    );
  }

  Future<UploadedImageRef> uploadImage({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final uri = _baseUri.resolve('/api/v1/uploads/image');
    final request = http.MultipartRequest('POST', uri)
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: fileName,
        ),
      );

    late http.StreamedResponse streamed;
    try {
      streamed = await _client.send(request).timeout(const Duration(seconds: 45));
    } on TimeoutException {
      throw ApiError('The image upload request timed out.');
    } catch (error) {
      throw ApiError(error.toString());
    }

    final response = await http.Response.fromStream(streamed);
    dynamic payload;
    if (response.body.isNotEmpty) {
      try {
        payload = jsonDecode(response.body);
      } catch (_) {
        payload = response.body;
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (payload is Map<String, dynamic> && payload['error'] != null) {
        throw ApiError(asString(payload['error']));
      }
      throw ApiError('Request failed with status ${response.statusCode}');
    }

    if (payload is Map<String, dynamic>) {
      return UploadedImageRef.fromJson(payload);
    }
    if (payload is Map) {
      final map = payload
          .map((key, dynamic value) => MapEntry(key.toString(), value));
      return UploadedImageRef.fromJson(map);
    }
    throw ApiError('The agent returned an invalid upload response.');
  }

  Future<Map<String, dynamic>> _decodeMap(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final result = await _sendJson(
      path,
      method: method,
      body: body,
      timeout: timeout,
    );
    if (result is Map<String, dynamic>) {
      return result;
    }
    if (result is Map) {
      return result
          .map((key, dynamic value) => MapEntry(key.toString(), value));
    }
    throw ApiError('The agent returned an invalid response.');
  }

  Future<dynamic> _sendJson(
    String path, {
    required String method,
    Map<String, dynamic>? body,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final uri = _baseUri.resolve(path);
    final request = http.Request(method, uri)
      ..headers['Content-Type'] = 'application/json';

    if (method != 'GET' || body != null) {
      request.body = jsonEncode(body ?? const <String, dynamic>{});
    }

    late http.StreamedResponse streamed;
    try {
      streamed = await _client.send(request).timeout(timeout);
    } on TimeoutException {
      throw ApiError('The agent request timed out.');
    } on FormatException {
      throw ApiError('The agent base URL is invalid.');
    } catch (error) {
      throw ApiError(error.toString());
    }

    final response = await http.Response.fromStream(streamed);
    dynamic payload;
    if (response.body.isNotEmpty) {
      try {
        payload = jsonDecode(response.body);
      } catch (_) {
        payload = response.body;
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (payload is Map<String, dynamic> && payload['error'] != null) {
        throw ApiError(asString(payload['error']));
      }
      throw ApiError('Request failed with status ${response.statusCode}');
    }

    return payload;
  }

  List<Map<String, dynamic>> _buildInputs({
    required String prompt,
    required List<String> imageUploadIds,
  }) {
    final inputs = <Map<String, dynamic>>[];
    final trimmed = prompt.trim();
    if (trimmed.isNotEmpty) {
      inputs.add(<String, dynamic>{
        'type': 'text',
        'text': trimmed,
      });
    }
    for (final id in imageUploadIds) {
      final trimmedId = id.trim();
      if (trimmedId.isEmpty) {
        continue;
      }
      inputs.add(<String, dynamic>{
        'type': 'image',
        'uploadId': trimmedId,
      });
    }
    return inputs;
  }
}
