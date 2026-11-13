import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../cloud/cloud_config.dart';

/// Um turno da conversa com o Copilot.
class CopilotTurn {
  const CopilotTurn({required this.fromUser, required this.text, this.unverified = const []});

  final bool fromUser;
  final String text;

  /// Números da resposta que não existem no resumo enviado (regra de ouro).
  final List<String> unverified;

  Map<String, String> toJson() => {'role': fromUser ? 'user' : 'assistant', 'text': text};
}

class CopilotException implements Exception {
  const CopilotException(this.message, {this.code});
  final String message;
  final String? code;

  @override
  String toString() => message;
}

abstract interface class CopilotApi {
  /// Envia a pergunta com o resumo dos números. Devolve o texto da resposta.
  Future<String> ask({
    required String accessToken,
    required String question,
    required Map<String, Object?> context,
    required List<CopilotTurn> history,
  });
}

/// Função `copilot` no Supabase: guarda a chave da IA e o limite diário.
class HttpCopilotApi implements CopilotApi {
  HttpCopilotApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<String> ask({
    required String accessToken,
    required String question,
    required Map<String, Object?> context,
    required List<CopilotTurn> history,
  }) async {
    final http.Response r;
    try {
      r = await _client
          .post(
            Uri.parse('${CloudConfig.url}/functions/v1/copilot'),
            headers: {
              'apikey': CloudConfig.publishableKey,
              'Authorization': 'Bearer $accessToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'question': question,
              'context': context,
              'history': [for (final t in history) t.toJson()],
            }),
          )
          .timeout(const Duration(seconds: 60));
    } on TimeoutException {
      throw const CopilotException('O Copilot demorou demasiado. Tente de novo.', code: 'timeout');
    } on SocketException {
      throw const CopilotException('Sem ligação à Internet.', code: 'offline');
    } on http.ClientException {
      throw const CopilotException('Sem ligação ao servidor.', code: 'offline');
    }
    Map<String, Object?> body;
    try {
      body = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, Object?>;
    } catch (_) {
      body = const {};
    }
    if (r.statusCode == 200 && body['answer'] is String) return body['answer']! as String;
    final message = body['message'] is String ? body['message']! as String : null;
    final code = body['error'] is String ? body['error']! as String : null;
    if (r.statusCode == 404) {
      throw const CopilotException('O Copilot ainda não está ativo.', code: 'not_configured');
    }
    throw CopilotException(message ?? 'O Copilot não respondeu (${r.statusCode}).', code: code);
  }
}

/// Para testes: responde com um texto fixo e guarda o último pedido.
@visibleForTesting
class MemoryCopilotApi implements CopilotApi {
  String reply = 'Este mês gastou o que está no resumo.';
  Map<String, Object?>? lastContext;
  String? lastQuestion;
  CopilotException? failWith;

  @override
  Future<String> ask({
    required String accessToken,
    required String question,
    required Map<String, Object?> context,
    required List<CopilotTurn> history,
  }) async {
    if (failWith != null) throw failWith!;
    lastContext = context;
    lastQuestion = question;
    return reply;
  }
}

final copilotApiProvider = Provider<CopilotApi>((ref) => HttpCopilotApi());
