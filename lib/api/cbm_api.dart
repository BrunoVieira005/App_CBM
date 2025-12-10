import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'cbm_models.dart';

// ===============================================================
// SERVIÇO DE CONEXÃO COM O BACKEND DJANGO (Djoser + DRF)
// ===============================================================
class CbmApi {
  // Para Web usamos 127.0.0.1; para Android emulator usamos 10.0.2.2
  static const String _host =
      'https://cbm-back-f3erdef8czfvhzgu.centralus-01.azurewebsites.net/';
  static String get _api => '$_host/api';

  String? _token; // auth_token do Djoser
  String? get token => _token;

  Map<String, String> _headers({bool auth = false, String? token}) {
    final h = <String, String>{
      'Content-Type': 'application/json; charset=UTF-8',
    };
    final t = token ?? _token;
    if (auth && t != null && t.isNotEmpty) h['Authorization'] = 'Token $t';
    return h;
  }

  // ------------------- Auth (Djoser) -------------------
  Future<void> login({required String email, required String password}) async {
    final url = Uri.parse('$_api/auth/token/login/');
    final res = await http.post(
      url,
      headers: _headers(),
      body: jsonEncode({'email': email, 'password': password}),
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      _token = data['auth_token'] as String?;
      if (_token == null || _token!.isEmpty) {
        throw Exception('Resposta sem auth_token.');
      }
    } else {
      throw Exception('Falha no login (${res.statusCode}).');
    }
  }

  Future<void> logout() async {
    if (_token == null) return;
    final url = Uri.parse('$_api/auth/token/logout/');
    await http.post(url, headers: _headers(auth: true));
    _token = null;
  }

  bool get isLoggedIn => _token != null;

  // ------------------- User/me -------------------
  Future<Map<String, dynamic>> getMe({required String token}) async {
    final uri = Uri.parse('$_api/auth/users/me/');
    final res = await http.get(
      uri,
      headers: _headers(auth: true, token: token),
    );
    if (res.statusCode == 200) {
      return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    }
    throw Exception('Erro ${res.statusCode} ao buscar /me: ${res.body}');
  }

  // ------------------- Recursos -------------------
  Future<List<CustomUser>> getUsers({String? token}) async {
    final uri = Uri.parse('$_api/custom-user/');
    final res = await http.get(
      uri,
      headers: _headers(auth: true, token: token),
    );
    if (res.statusCode == 200) {
      final list = jsonDecode(utf8.decode(res.bodyBytes)) as List;
      return list.map((e) => CustomUser.fromJson(e)).toList();
    }
    throw Exception(
      'Erro ${res.statusCode}: não foi possível buscar usuários.',
    );
  }

  Future<List<Equipment>> getEquipments({String? token}) async {
    final uri = Uri.parse('$_api/equipment/');
    final res = await http.get(
      uri,
      headers: _headers(auth: true, token: token),
    );
    if (res.statusCode == 200) {
      final list = jsonDecode(utf8.decode(res.bodyBytes)) as List;
      return list.map((e) => Equipment.fromJson(e)).toList();
    }
    throw Exception(
      'Erro ${res.statusCode}: não foi possível buscar equipamentos.',
    );
  }

  // ------------------- Recurso (detalhe) -------------------
  Future<Equipment?> getEquipmentById({
    required int id,
    required String token,
  }) async {
    final uri = Uri.parse('$_api/equipment/$id/');
    final res = await http.get(
      uri,
      headers: _headers(auth: true, token: token),
    );
    if (res.statusCode == 200) {
      final map =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      return Equipment.fromJson(map);
    }
    if (res.statusCode == 404) return null;
    throw Exception(
      'Erro ${res.statusCode} ao buscar equipamento $id: ${res.body}',
    );
  }

  Future<Equipment?> getEquipmentByCode({
    required String code,
    required String token,
  }) async {
    final id = _extractIdFromQr(code);
    if (id != null) {
      final byId = await getEquipmentById(id: id, token: token);
      if (byId != null) return byId;
    }

    var uri = Uri.parse('$_api/equipment/?search=$code');
    var res = await http.get(uri, headers: _headers(auth: true, token: token));
    if (res.statusCode == 200) {
      final list = jsonDecode(utf8.decode(res.bodyBytes));
      if (list is List && list.isNotEmpty) {
        return Equipment.fromJson(list.first);
      }
    }

    uri = Uri.parse('$_api/equipment/?code=$code');
    res = await http.get(uri, headers: _headers(auth: true, token: token));
    if (res.statusCode == 200) {
      final list = jsonDecode(utf8.decode(res.bodyBytes));
      if (list is List && list.isNotEmpty) {
        return Equipment.fromJson(list.first);
      }
    }
    return null;
  }

  // 1. Cria a TAREFA e retorna o ID
  Future<int?> createTaskSimple(
    Map<String, dynamic> taskData,
    String token,
  ) async {
    final url = Uri.parse('$_api/task/');
    final response = await http.post(
      url,
      headers: _headers(auth: true, token: token),
      body: jsonEncode(taskData),
    );

    if (response.statusCode == 201) {
      final data = jsonDecode(response.body);
      return data['id']; // Retorna o ID da tarefa criada
    }
    throw Exception('Falha ao criar tarefa: ${response.body}');
  }

  // 2. Cria o STATUS e retorna o ID
  Future<int?> createTaskStatus(
    Map<String, dynamic> statusData,
    String token,
  ) async {
    final url = Uri.parse('$_api/task-status/');
    final response = await http.post(
      url,
      headers: _headers(auth: true, token: token),
      body: jsonEncode(statusData),
    );

    if (response.statusCode == 201) {
      final data = jsonDecode(response.body);
      return data['id']; // Retorna o ID do status criado
    }
    throw Exception('Falha ao criar status: ${response.body}');
  }

  // 3. Envia a IMAGEM associada ao Status
  Future<void> uploadTaskStatusImage({
    required File imageFile,
    required int statusId,
    required String token,
  }) async {
    final url = Uri.parse('$_api/task-status-image/');

    // Cria requisição Multipart
    var request = http.MultipartRequest('POST', url);

    // Headers (Authorization é fundamental)
    request.headers['Authorization'] = 'Token $token';

    // Campos de Texto
    request.fields['task_status_FK'] = statusId.toString();

    // Arquivo
    request.files.add(
      await http.MultipartFile.fromPath(
        'image', // Nome do campo no seu model Django
        imageFile.path,
      ),
    );

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 201) {
      throw Exception('Falha no upload da imagem: ${response.body}');
    }
  }

  // ------------------- GET OPEN TASKS -------------------
  Future<List<Map<String, dynamic>>> getOpenTasks({
    required String token,
    required int userId,
  }) async {
    final uri = Uri.parse('$_api/task/?creator_FK=$userId');
    final res = await http.get(
      uri,
      headers: _headers(auth: true, token: token),
    );

    if (res.statusCode == 200) {
      final list = jsonDecode(utf8.decode(res.bodyBytes));
      if (list is List) {
        return list
            .where((task) {
              // Verifica se foi criado pelo usuário logado
              final creator = task['creator_FK'];
              if (creator == null || creator['id'] != userId) return false;

              // Pega o último status, se existir
              final history = task['status_history'] as List?;
              if (history == null || history.isEmpty) {
                // Se não tiver histórico, ainda está aberto
                return true;
              }

              final lastStatus =
                  history.last['status']?.toString().toUpperCase() ?? '';
              // Filtra apenas os que NÃO estão fechados
              return lastStatus != 'CLOSED' &&
                  lastStatus != 'FINALIZED' &&
                  lastStatus != 'DONE' &&
                  lastStatus != 'CONCLUDED';
            })
            .cast<Map<String, dynamic>>()
            .toList();
      }
    }
    throw Exception('Erro ao buscar chamados abertos (${res.statusCode})');
  }

  // ------------------- Helpers -------------------
  int? _extractIdFromQr(String raw) {
    final s = raw.trim();
    if (RegExp(r'^\d+$').hasMatch(s)) return int.tryParse(s);

    final urlId = RegExp(r'/equipment/(\d+)/?$').firstMatch(s);
    if (urlId != null) return int.tryParse(urlId.group(1)!);

    try {
      final dynamic parsed = jsonDecode(s);
      if (parsed is Map && parsed['id'] != null) {
        return int.tryParse(parsed['id'].toString());
      }
    } catch (_) {}
    return null;
  }
}
