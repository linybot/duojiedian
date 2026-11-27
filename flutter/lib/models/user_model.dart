import 'dart:async';
import 'dart:convert';

import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/hbbs/hbbs.dart';
import 'package:flutter_hbb/models/ab_model.dart';
import 'package:get/get.dart';

import '../common.dart';
import '../utils/http_service.dart' as http;
import 'model.dart';
import 'platform_model.dart';

bool refreshingUser = false;

class UserModel {
  final RxString userName = ''.obs;
  final RxString displayName = ''.obs;
  final RxString avatar = ''.obs;
  final RxBool isAdmin = false.obs;
  final RxString networkError = ''.obs;
  // True when networkError carries a server-reported error rather than a
  // connectivity failure; netWorkErrorWidget hides the network tip then.
  final RxBool networkErrorFromServer = false.obs;
  bool get isLogin => userName.isNotEmpty;
  String get displayNameOrUserName =>
      displayName.value.trim().isEmpty ? userName.value : displayName.value;
  String get accountLabelWithHandle {
    final username = userName.value.trim();
    if (username.isEmpty) {
      return '';
    }
    final preferred = displayName.value.trim();
    if (preferred.isEmpty || preferred == username) {
      return username;
    }
    return '$preferred (@$username)';
  }

  WeakReference<FFI> parent;

  UserModel(this.parent) {
    userName.listen((p0) {
      // When user name becomes empty, show login button
      // When user name becomes non-empty:
      //  For _updateLocalUserInfo, network error will be set later
      //  For login success, should clear network error
      networkError.value = '';
    });
  }

  void refreshCurrentUser() async {
    if (bind.isDisableAccount()) return;
    networkError.value = '';
    networkErrorFromServer.value = false;
    final token = bind.mainGetLocalOption(key: 'access_token');
    if (token == '') {
      await updateOtherModels();
      return;
    }
    _updateLocalUserInfo();
    final url = await bind.mainGetApiServer();
    final body = {
      'id': await bind.mainGetMyId(),
      'uuid': await bind.mainGetUuid()
    };
    if (refreshingUser) return;
    try {
      refreshingUser = true;
      final http.Response response;
      try {
        response = await http.post(Uri.parse('$url/api/currentUser'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token'
            },
            body: json.encode(body));
      } catch (e) {
        networkError.value = e.toString();
        rethrow;
      }
      refreshingUser = false;
      final status = response.statusCode;
      if (status == 401 || status == 400) {
        reset(resetOther: status == 401);
        return;
      }
      final data = json.decode(decode_http_response(response));
      final error = data['error'];
      if (error != null) {
        // The only failure known to come from the server itself, so the
        // check-your-network tip does not apply. Flag before the message is
        // set in the catch below so rebuilds read a consistent pair.
        networkErrorFromServer.value = true;
        throw error;
      }

      final user = UserPayload.fromJson(data);
      _parseAndUpdateUser(user);
    } catch (e) {
      debugPrint('Failed to refreshCurrentUser: $e');
      // Surface failures in the address book / group tabs, which offer a
      // retry. Anything not flagged above -- transport errors, non-JSON or
      // unexpected-schema bodies (e.g. a filter's block page) -- keeps the
      // check-your-network tip.
      if (networkError.value.isEmpty) {
        networkError.value = e.toString();
      }
    } finally {
      refreshingUser = false;
      await updateOtherModels();
    }
  }

  static Map<String, dynamic>? getLocalUserInfo() {
    final userInfo = bind.mainGetLocalOption(key: 'user_info');
    if (userInfo == '') {
      return null;
    }
    try {
      return json.decode(userInfo);
    } catch (e) {
      debugPrint('Failed to get local user info "$userInfo": $e');
    }
    return null;
  }

  _updateLocalUserInfo() {
    final userInfo = getLocalUserInfo();
    if (userInfo != null) {
      userName.value = (userInfo['name'] ?? '').toString();
      displayName.value = (userInfo['display_name'] ?? '').toString();
      avatar.value = (userInfo['avatar'] ?? '').toString();
    }
  }

  Future<void> reset({bool resetOther = false}) async {
    await bind.mainSetLocalOption(key: 'access_token', value: '');
    await bind.mainSetLocalOption(key: 'user_info', value: '');
    if (resetOther) {
      await gFFI.abModel.reset();
      await gFFI.groupModel.reset();
    }
    userName.value = '';
    displayName.value = '';
    avatar.value = '';
  }

  _parseAndUpdateUser(UserPayload user) {
    userName.value = user.name;
    displayName.value = user.displayName;
    avatar.value = user.avatar;
    isAdmin.value = user.isAdmin;
    bind.mainSetLocalOption(key: 'user_info', value: jsonEncode(user));
    if (isWeb) {
      // ugly here, tmp solution
      bind.mainSetLocalOption(key: 'verifier', value: user.verifier ?? '');
    }
  }

  // update ab and group status
  static Future<void> updateOtherModels() async {
    await Future.wait([
      gFFI.abModel.pullAb(force: ForcePullAb.listAndCurrent, quiet: false),
      gFFI.groupModel.pull()
    ]);
  }

  Future<void> logOut({String? apiServer}) async {
    final tag = gFFI.dialogManager.showLoading(translate('Waiting'));
    try {
      final url = apiServer ?? await bind.mainGetApiServer();
      final authHeaders = getHttpHeaders();
      authHeaders['Content-Type'] = "application/json";
      await http
          .post(Uri.parse('$url/api/logout'),
              body: jsonEncode({
                'id': await bind.mainGetMyId(),
                'uuid': await bind.mainGetUuid(),
              }),
              headers: authHeaders)
          .timeout(Duration(seconds: 2));
    } catch (e) {
      debugPrint("request /api/logout failed: err=$e");
    } finally {
      await reset(resetOther: true);
      // [duojiedian] No account any more: stop pinning the node it lived on.
      await bind.mainSetOption(key: 'account-node-pin', value: '');
      gFFI.dialogManager.dismissByTag(tag);
    }
  }

  /// [duojiedian] Deployment nodes, kept in sync with the node picker. Every
  /// hbbs keeps its own account database, so a login may only exist on one of
  /// them; the login request rolls through them until one accepts the account.
  static const List<String> _deployNodes = ['linybot.top', 'rust.linybot.top'];

  /// Host part of an "http://host:port" style server string.
  static String _hostOf(String server) {
    var s = server.trim();
    final scheme = s.indexOf('://');
    if (scheme >= 0) {
      s = s.substring(scheme + 3);
    }
    final cut = s.indexOf(RegExp(r'[:/]'));
    return (cut >= 0 ? s.substring(0, cut) : s).toLowerCase();
  }

  /// [duojiedian] Nodes that answered "wrong credentials" while the account is
  /// actually registered on another hbbs. Every hbbs has its own account
  /// database and answers "username or password incorrect" for an account it
  /// does not know, so such an answer cannot end the search: it only means
  /// "not this node".
  static final Set<String> _nodesWithoutAccount = <String>{};

  /// Whether [cause] looks like a credential rejection. It is only used to pick
  /// which error is shown when every node refuses, and to remember the node as
  /// "does not hold this account" so the next login starts elsewhere.
  static bool _isCredentialError(String cause) {
    final c = cause.toLowerCase();
    return c.contains('password') ||
        c.contains('passwd') ||
        c.contains('密码') ||
        c.contains('验证码') ||
        c.contains('2fa') ||
        c.contains('locked') ||
        c.contains('禁用');
  }

  /// throw [RequestException]
  Future<LoginResponse> login(LoginRequest loginRequest) async {
    final primary = await bind.mainGetApiServer();
    final candidates = <String>[];
    for (final url in [
      primary,
      for (final node in _deployNodes) 'http://$node:21114'
    ]) {
      final u = url.trim();
      if (u.isEmpty || candidates.contains(u)) {
        continue;
      }
      candidates.add(u);
    }
    // Nodes that already refused this account go last, so the node that really
    // holds it is reached in the first round instead of after a wrong answer.
    final unknown = _nodesWithoutAccount;
    candidates.sort((a, b) {
      final na = unknown.contains(_hostOf(a));
      final nb = unknown.contains(_hostOf(b));
      if (na == nb) return 0;
      return na ? 1 : -1;
    });
    RequestException? lastError;
    RequestException? credentialError;
    for (final url in candidates) {
      try {
        final result = await _loginOn(url, loginRequest);
        // The account lives here: forget every wrong-node guess.
        unknown.remove(_hostOf(url));
        return result;
      } on RequestException catch (e) {
        // A node without the account answers exactly like a wrong password, so
        // it never ends the search; it only marks that node as "not here".
        if (_isCredentialError(e.cause)) {
          unknown.add(_hostOf(url));
          credentialError ??= e;
        } else {
          lastError = e;
        }
      } catch (e) {
        lastError ??= RequestException(0, e.toString());
      }
    }
    throw credentialError ?? lastError ?? RequestException(0, 'login failed');
  }

  Future<LoginResponse> _loginOn(String url, LoginRequest loginRequest) async {
    // A dead node must not park the login forever: each node gets one bounded
    // attempt so the loop can move on to the node that actually answers.
    final resp = await http
        .post(Uri.parse('$url/api/login'),
            body: jsonEncode(loginRequest.toJson()))
        .timeout(const Duration(seconds: 8));

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(decode_http_response(resp));
    } catch (e) {
      debugPrint("login: jsonDecode resp body failed: ${e.toString()}");
      if (resp.statusCode != 200) {
        BotToast.showText(
            contentColor: Colors.red, text: 'HTTP ${resp.statusCode}');
      }
      rethrow;
    }
    if (resp.statusCode != 200) {
      throw RequestException(resp.statusCode, body['error'] ?? '');
    }
    if (body['error'] != null) {
      throw RequestException(0, body['error']);
    }

    final result = getLoginResponseFromAuthBody(body);
    final token = result.access_token;
    if (result.type == HttpType.kAuthResTypeToken && token != null) {
      // [duojiedian] Keep the node that owns this account: it is dialled first
      // from now on instead of searching the nodes again on every start.
      final host = Uri.parse(url).host;
      if (host.isNotEmpty) {
        await bind.mainSetOption(key: 'account-node-pin', value: host);
        // A stale manual pick on another node would win over the pin and cut
        // the account off, so it is dropped as soon as the real node is known.
        final custom = await bind.mainGetOption(key: 'custom-rendezvous-server');
        if (custom.isNotEmpty && _hostOf(custom) != host) {
          await bind.mainSetOption(key: 'custom-rendezvous-server', value: '');
          await bind.mainSetOption(key: 'relay-server', value: '');
        }
      }
    }
    return result;
  }

  LoginResponse getLoginResponseFromAuthBody(Map<String, dynamic> body) {
    final LoginResponse loginResponse;
    try {
      loginResponse = LoginResponse.fromJson(body);
    } catch (e) {
      debugPrint("login: jsonDecode LoginResponse failed: ${e.toString()}");
      rethrow;
    }

    final isLogInDone = loginResponse.type == HttpType.kAuthResTypeToken &&
        loginResponse.access_token != null;
    if (isLogInDone && loginResponse.user != null) {
      _parseAndUpdateUser(loginResponse.user!);
    }

    return loginResponse;
  }

  /// Throws on network failures, non-success responses, and invalid response
  /// data. Returns an empty list when no API server is configured or a
  /// successful response contains no third-party login options.
  static Future<List<dynamic>> queryOidcLoginOptions() async {
    final url = await bind.mainGetApiServer();
    if (url.trim().isEmpty) return [];
    final resp = await http.get(Uri.parse('$url/api/login-options'));
    const successStatusCodeStart = 200;
    const successStatusCodeEnd = 300;
    if (resp.statusCode < successStatusCodeStart ||
        resp.statusCode >= successStatusCodeEnd) {
      throw RequestException(
          resp.statusCode, resp.reasonPhrase ?? 'Request failed');
    }
    final List<String> ops = [];
    for (final item in jsonDecode(resp.body)) {
      ops.add(item as String);
    }
    for (final item in ops) {
      if (item.startsWith('common-oidc/')) {
        return jsonDecode(item.substring('common-oidc/'.length));
      }
    }
    return ops
        .where((item) => item.startsWith('oidc/'))
        .map((item) => {'name': item.substring('oidc/'.length)})
        .toList();
  }
}
