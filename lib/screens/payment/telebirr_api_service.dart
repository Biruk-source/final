import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:basic_utils/basic_utils.dart';
import 'config.dart';

class _MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}

class TelebirrApiService {
  String? _token;
  String? _accessToken;

  TelebirrApiService({bool trustBadCertificate = false}) {
    if (trustBadCertificate) {
      print("WARNING: Enabling permissive HttpClientCertificate validation.");
      print("         ONLY use this for local testing with trusted IPs.");
      HttpOverrides.global = _MyHttpOverrides();
    }
  }

  Map<String, String> _getHeaders(bool useToken, {bool useAppToken = false}) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'X-APP-Key': AppConfig.appid,
    };
    if (useToken && _token != null) {
      headers['Authorization'] = _token!;
    }
    if (useAppToken && _accessToken != null) {
      headers['X-Access-Token'] = _accessToken!;
    }
    return headers;
  }

  String _generateNonceStr() {
    return 'nonce${DateTime.now().millisecondsSinceEpoch}${Platform.operatingSystem.hashCode % 1000}';
  }

  String _getTimestamp() {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }

  String _signRequest(Map<String, dynamic> payload) {
    print("Attempting to sign payload using basic_utils...");
    try {
      final Map<String, String> paramsToSign = {};
      paramsToSign['appid'] = AppConfig.appid;

      // Add top-level fields (excluding sign)
      payload.forEach((key, value) {
        if (key != 'sign' &&
            key != 'biz_content' &&
            value != null &&
            value.toString().isNotEmpty) {
          paramsToSign[key] = value.toString();
        }
      });

      // Add biz_content fields with prefix
      if (payload.containsKey('biz_content') && payload['biz_content'] is Map) {
        final bizContent = payload['biz_content'] as Map<String, dynamic>;
        bizContent.forEach((key, value) {
          if (value != null && value.toString().isNotEmpty) {
            paramsToSign['biz_content_$key'] = value.toString();
          }
        });
      }

      // Sort keys and create String-to-Sign with URL-encoded values
      final sortedKeys = paramsToSign.keys.toList()..sort();
      final stringToSign = sortedKeys
          .map((key) => '$key=${Uri.encodeComponent(paramsToSign[key]!)}')
          .join('&');

      print("--------------------------------------------------");
      print("String-to-Sign: $stringToSign");
      print("--------------------------------------------------");

      if (stringToSign.isEmpty) {
        throw Exception("Cannot sign an empty string. Check payload.");
      }

      final privateKey = CryptoUtils.rsaPrivateKeyFromPem(AppConfig.privateKey);
      final data = Uint8List.fromList(utf8.encode(stringToSign));
      final signature = CryptoUtils.rsaSign(privateKey, data);
      final base64Signature = base64Encode(signature);
      print("Generated Signature (Base64): $base64Signature");
      return base64Signature;
    } catch (e, stackTrace) {
      print("!!! ERROR DURING SIGNING: $e");
      print("!!! StackTrace: $stackTrace");
      throw Exception("Failed to sign request: $e");
    }
  }

  String _encryptPin(String pin) {
    print("WARNING: PIN Encryption is NOT implemented. Returning placeholder.");
    return AppConfig.consumerPin;
  }

  Future<Map<String, dynamic>> _postRequest(
    String endpoint,
    Map<String, dynamic> body, {
    bool requiresToken = false,
  }) async {
    final url = Uri.parse('${AppConfig.basicURL}$endpoint');
    final headers = _getHeaders(requiresToken);
    final requestBodyJson = jsonEncode(body);

    print('--- API Request --- ');
    print('URL: ${url.toString()}');
    print('Method: POST');
    print('Headers: $headers');
    print('Body: $requestBodyJson');
    print('-------------------');

    http.Response response;
    try {
      response = await http
          .post(url, headers: headers, body: requestBodyJson)
          .timeout(const Duration(seconds: 60));

      print('--- API Response --- ');
      print('Status Code: ${response.statusCode}');
      print('Headers: ${response.headers}');
      print('Body: ${response.body}');
      print('--------------------');

      Map<String, dynamic> responseBodyMap = {};
      if (response.body.isNotEmpty) {
        try {
          responseBodyMap = jsonDecode(response.body);
        } catch (e) {
          print("Warning: Could not decode response body as JSON: $e");
        }
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final responseCode = responseBodyMap['code']?.toString();
        final errorCode = responseBodyMap['errorCode']?.toString();
        if (responseCode != null &&
            responseCode != '200' &&
            responseCode != '20000') {
          final errorMessage = responseBodyMap['errorMsg'] ??
              responseBodyMap['msg'] ??
              jsonEncode(responseBodyMap);
          throw Exception(
            'API Logic Error ($endpoint): HTTP ${response.statusCode}, Code: $responseCode, Msg: $errorMessage',
          );
        }
        if (errorCode != null &&
            errorCode != '0' &&
            errorCode != '200' &&
            errorCode != '20000') {
          final errorMessage = responseBodyMap['errorMsg'] ??
              responseBodyMap['msg'] ??
              jsonEncode(responseBodyMap);
          throw Exception(
            'API Logic Error ($endpoint): HTTP ${response.statusCode}, ErrorCode: $errorCode, Msg: $errorMessage',
          );
        }
        return responseBodyMap;
      } else {
        final errorMessage = responseBodyMap.isNotEmpty
            ? (responseBodyMap['errorMsg'] ??
                responseBodyMap['msg'] ??
                responseBodyMap['message'] ??
                jsonEncode(responseBodyMap))
            : response.body;
        final errorCode =
            responseBodyMap['errorCode'] ?? responseBodyMap['code'] ?? 'N/A';
        throw Exception(
          'API HTTP Error ($endpoint): ${response.statusCode} - (Code: $errorCode) $errorMessage',
        );
      }
    } on SocketException catch (e) {
      print('Network Error: $e');
      throw Exception(
        'Network error connecting to $url. Check connection/URL/IP. Details: $e',
      );
    } on http.ClientException catch (e) {
      print('HTTP Client Error: $e');
      throw Exception('HTTP client error during request to $url. Details: $e');
    } on TimeoutException catch (e) {
      print('Request Timeout: $e');
      throw Exception(
        'Request to $url timed out. Check network or server responsiveness.',
      );
    } catch (e) {
      print('Error during API call processing for $endpoint: $e');
      rethrow;
    }
  }

  Future<String?> generateAppToken() async {
    const endpoint = '/payment/v1/token';
    final body = {'appSecret': AppConfig.appSecret};
    print("Attempting to generate app token with appid: ${AppConfig.appid}...");
    try {
      final response = await _postRequest(endpoint, body, requiresToken: false);
      final responseToken = response['token'];
      print("Generate Token Response Token: $responseToken");
      if (responseToken != null &&
          responseToken is String &&
          responseToken.isNotEmpty) {
        _token = responseToken;
        print('Successfully obtained app token.');
        return _token;
      } else {
        throw Exception(
          'Failed to generate app token: Server response did not contain a valid token. Response: ${jsonEncode(response)}',
        );
      }
    } catch (e) {
      print('Error in generateAppToken function: $e');
      _token = null;
      rethrow;
    }
  }

  Future<String?> createOrder({
    required String totalAmount,
    required String merchOrderId,
    required String title,
    required String payeeIdentifier,
    String transCurrency = 'ETB',
    String timeoutExpress = '120m',
    String tradeType = 'InApp',
    required String notifyUrl,
    String businessType = 'P2PTransfer',
    String payeeIdentifierType = '01',
    String payeeType = '1000',
  }) async {
    if (_token == null) {
      throw Exception('App token not available...');
    }

    // Validate merchOrderId
    if (!RegExp(r'^[A-Za-z0-9]+$').hasMatch(merchOrderId)) {
      throw Exception(
          'Invalid merch_order_id: Must contain only alphanumeric characters (A-Z, a-z, 0-9).');
    }

    // Simplify to numeric-only, limit to 16 characters
    final validatedMerchOrderId =
        DateTime.now().millisecondsSinceEpoch.toString().substring(0, 16);
    print('Original merch_order_id: $merchOrderId');
    print('Validated merch_order_id: $validatedMerchOrderId');

    const endpoint = '/payment/v1/merchant/preOrder';
    final timestamp = _getTimestamp();
    final nonceStr = _generateNonceStr();
    final bizContent = {
      'trans_currency': transCurrency,
      'total_amount': totalAmount,
      'merch_order_id': validatedMerchOrderId,
      'appid': AppConfig.merchantId,
      'merch_code': AppConfig.merchantCode,
      'timeout_express': timeoutExpress,
      'trade_type': tradeType,
      'notify_url': notifyUrl,
      'title': title,
      'business_type': businessType,
      'payee_identifier': payeeIdentifier,
      'payee_identifier_type': payeeIdentifierType,
      'payee_type': payeeType,
    };
    print('biz_content: $bizContent');
    print('merch_order_id: $validatedMerchOrderId');
    final payloadToSign = {
      'nonce_str': nonceStr,
      'method': 'payment.preorder',
      'timestamp': timestamp,
      'version': '1.0',
      'biz_content': bizContent,
      'sign_type': 'SHA256WithRSA',
    };
    final payloadToSend = Map<String, dynamic>.from(payloadToSign);
    payloadToSend['sign'] = _signRequest(payloadToSign);

    try {
      final response = await _postRequest(
        endpoint,
        payloadToSend,
        requiresToken: true,
      );
      final responseBizContent = response['biz_content'];
      final prepayId = (responseBizContent is Map)
          ? responseBizContent['prepay_id'] as String?
          : null;
      if (prepayId != null && prepayId.isNotEmpty) {
        print('Order created successfully. Prepay ID: $prepayId');
        return prepayId;
      } else {
        final responseCode = response['code']?.toString() ??
            response['errorCode']?.toString() ??
            'N/A';
        final responseMsg = response['msg'] ??
            response['errorMsg'] ??
            response['message'] ??
            jsonEncode(response);
        throw Exception(
          'Failed to create order: Prepay ID missing. Code: $responseCode, Details: $responseMsg',
        );
      }
    } catch (e) {
      print('Error creating order: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> payOrder({
    required String prepayId,
    required String payerIdentifier,
    required String consumerPin,
    String payerIdentifierType = '01',
    String payerType = '1000',
    String lang = 'en_US',
  }) async {
    if (_token == null) {
      throw Exception('App token not available...');
    }
    const endpoint = '/payment/v1/app/payOrder';
    final timestamp = _getTimestamp();
    final nonceStr = _generateNonceStr();
    final encryptedPin = _encryptPin(consumerPin);
    final bizContent = {
      'prepay_id': prepayId,
      'payer_identifier_type': payerIdentifierType,
      'payer_identifier': payerIdentifier,
      'payer_type': payerType,
      'security_credential': encryptedPin,
    };
    print('biz_content: $bizContent');
    final payloadToSign = {
      'timestamp': timestamp,
      'nonce_str': nonceStr,
      'method': 'payment.payorder',
      'sign_type': 'SHA256WithRSA',
      'lang': lang,
      'version': '1.0',
      'app_code': AppConfig.merchantId,
      'biz_content': bizContent,
    };
    final payloadToSend = Map<String, dynamic>.from(payloadToSign);
    payloadToSend['sign'] = _signRequest(payloadToSign);

    try {
      final response = await _postRequest(
        endpoint,
        payloadToSend,
        requiresToken: true,
      );
      final responseCode =
          response['code']?.toString() ?? response['errorCode']?.toString();
      final responseMsg =
          response['msg'] ?? response['errorMsg'] ?? response['message'];
      if (responseCode == '200' || responseCode == '20000') {
        print('PayOrder successful: ${jsonEncode(response['biz_content'])}');
        return response;
      } else {
        throw Exception(
          'PayOrder failed. Code: ${responseCode ?? 'N/A'}, Details: ${responseMsg ?? jsonEncode(response)}',
        );
      }
    } catch (e) {
      print('Error during payOrder: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> queryOrder({
    required String merchOrderId,
  }) async {
    if (_token == null) {
      throw Exception(
          'App token not available. Call generateAppToken() first.');
    }

    // Validate merchOrderId
    if (!RegExp(r'^[A-Za-z0-9]+$').hasMatch(merchOrderId)) {
      throw Exception(
          'Invalid merch_order_id: Must contain only alphanumeric characters (A-Z, a-z, 0-9).');
    }

    // Simplify to numeric-only, limit to 16 characters
    final validatedMerchOrderId =
        DateTime.now().millisecondsSinceEpoch.toString().substring(0, 16);
    print('Original merch_order_id for query: $merchOrderId');
    print('Validated merch_order_id for query: $validatedMerchOrderId');

    const endpoint = '/payment/v1/merchant/queryOrder';
    final timestamp = _getTimestamp();
    final nonceStr = _generateNonceStr();

    final bizContent = {
      'appid': AppConfig.merchantId,
      'merch_code': AppConfig.merchantCode,
      'merch_order_id': validatedMerchOrderId,
    };
    print('biz_content: $bizContent');
    final payloadToSign = {
      'timestamp': timestamp,
      'nonce_str': nonceStr,
      'method': 'payment.queryorder',
      'sign_type': 'SHA256WithRSA',
      'version': '1.0',
      'biz_content': bizContent,
    };

    final payloadToSend = Map<String, dynamic>.from(payloadToSign);
    payloadToSend['sign'] = _signRequest(payloadToSign);

    try {
      final response = await _postRequest(
        endpoint,
        payloadToSend,
        requiresToken: true,
      );
      final responseCode =
          response['code']?.toString() ?? response['errorCode']?.toString();
      final responseMsg =
          response['msg'] ?? response['errorMsg'] ?? response['message'];

      if (responseCode == '200' || responseCode == '20000') {
        print('QueryOrder successful: ${jsonEncode(response['biz_content'])}');
        return response;
      } else {
        throw Exception(
          'QueryOrder failed. Code: ${responseCode ?? 'N/A'}, Details: ${responseMsg ?? jsonEncode(response)}',
        );
      }
    } catch (e) {
      print('Error during queryOrder: $e');
      rethrow;
    }
  }
}
