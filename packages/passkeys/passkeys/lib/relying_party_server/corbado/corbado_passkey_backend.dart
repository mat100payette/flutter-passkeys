import 'dart:convert';

import 'package:corbado_frontend_api_client/frontendapi/lib/api.dart';
import 'package:flutter/foundation.dart';
import 'package:http/browser_client.dart';
import 'package:passkeys/relying_party_server/corbado/types/authentication.dart';
import 'package:passkeys/relying_party_server/corbado/types/exceptions.dart';
import 'package:passkeys/relying_party_server/corbado/types/registration.dart';
import 'package:passkeys/relying_party_server/corbado/types/shared.dart';
import 'package:passkeys/relying_party_server/relying_party_server.dart';
import 'package:passkeys/relying_party_server/types/authentication.dart';
import 'package:passkeys/relying_party_server/types/registration.dart';
import 'package:ua_client_hints/ua_client_hints.dart';

/// Implementation of [RelyingPartyServer] that allows to use Corbado as a
/// relying party.
class CorbadoPasskeyBackend
    extends RelyingPartyServer<AuthRequest, AuthResponse> {
  /// Sets up the client for the Corbado API.
  CorbadoPasskeyBackend(this._projectID)
      : _frontendAPI = 'https://login.flutter-corbadoauth-example.korbado.com';

  /// Initializes the client by setting all required headers
  Future<void> init() async {
    _client = await buildClient();
  }

  late final ApiClient _client;
  final String _projectID;
  final String _frontendAPI;

  @override
  Future<RegistrationInitResponse> initRegister(AuthRequest request) async {
    try {
      final result = await UsersApi(_client).passKeyRegisterStart(
        PassKeyRegisterStartReq(
          username: request.email,
          fullName: request.username ?? request.email,
        ),
      );

      if (result == null) {
        throw UnexpectedBackendException(
          'passKeyRegisterStart',
          'result was null',
        );
      }

      final json = jsonDecode(result.data.challenge) as Map<String, dynamic>;
      final typed = CorbadoRegisterChallenge.fromJson(json);
      return typed.toRegisterInitResponse();
    } on ApiException catch (e) {
      throw ExceptionFactory.fromBackendMessage(
        'passKeyRegisterStart',
        e.message ?? '',
      );
    }
  }

  @override
  Future<AuthResponse> completeRegister(
    RegistrationCompleteRequest request,
  ) async {
    try {
      final signedChallenge = jsonEncode(
        CorbadoRegisterSignedChallengeRequest.fromRegisterCompleteRequest(
          request,
        ).toJson(),
      );

      final result = await UsersApi(_client).passKeyRegisterFinishWithHttpInfo(
        PassKeyFinishReq(signedChallenge: signedChallenge),
      );

      return AuthResponse.fromHttpResponse(result);
    } on ApiException catch (e) {
      throw ExceptionFactory.fromBackendMessage(
        'passKeyRegisterFinish',
        e.message ?? '',
      );
    }
  }

  @override
  Future<AuthenticationInitResponse> initAuthenticate(
    AuthRequest request,
  ) async {
    try {
      String challenge;
      if (request.email.isEmpty) {
        final result = await UsersApi(_client).passKeyMediationStart(
          PassKeyMediationStartReq(username: request.email),
        );

        if (result == null) {
          throw Exception(
            'An unknown error occurred during the Corbado API call',
          );
        }

        challenge = result.data.challenge;
      } else {
        final result = await UsersApi(_client).passKeyLoginStart(
          PassKeyLoginStartReq(username: request.email),
        );

        if (result == null) {
          throw Exception(
            'An unknown error occurred during the Corbado API call',
          );
        }

        challenge = result.data.challenge;
      }

      if (challenge.isEmpty) {
        throw NoPasskeyForDeviceException();
      }

      final json = jsonDecode(challenge) as Map<String, dynamic>;
      final typed = CorbadoAuthenticationInitResponse.fromJson(json);
      return typed.toAuthenticationInitResponse();
    } on ApiException catch (e) {
      throw ExceptionFactory.fromBackendMessage(
        'passKeyAuthenticateStart',
        e.message ?? '',
      );
    }
  }

  @override
  Future<AuthResponse> completeAuthenticate(
    AuthenticationCompleteRequest request,
  ) async {
    try {
      final signedChallenge = jsonEncode(
        CorbadoAuthenticationCompleteRequest.fromAuthenticationCompleteRequest(
          request,
        ).toJson(),
      );

      final response = await UsersApi(_client).passKeyLoginFinishWithHttpInfo(
        PassKeyFinishReq(signedChallenge: signedChallenge),
      );

      final res = await AuthResponse.fromHttpResponse(response);
      return res;
    } on ApiException catch (e) {
      throw ExceptionFactory.fromBackendMessage(
        'passKeyAuthenticateFinish',
        e.message ?? '',
      );
    }
  }

  /// Builds an API client to interact with the Corbado frontend API.
  /// Depending on the platform different headers will be set.
  Future<ApiClient> buildClient() async {
    final apiClient = ApiClient(basePath: _frontendAPI)
      ..addDefaultHeader('X-Corbado-ProjectID', _projectID);

    if (kIsWeb) {
      final httpClient = BrowserClient()..withCredentials = true;
      apiClient.client = httpClient;
    } else {
      final ua = await userAgent();
      apiClient.addDefaultHeader('User-Agent', ua);
    }

    return apiClient;
  }
}
