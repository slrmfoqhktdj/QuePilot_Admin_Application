import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import '../db/hive_service.dart';
import '../db/model/hive_key_model.dart';
import '../services/discovery_service.dart';
import '../services/socket_service.dart';
import '../utils/navigation.dart';
import 'central_control_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _idController = TextEditingController();
  final _passwordController = TextEditingController();
  final socketService = SocketService();
  final hiveService = HiveService();

  bool _isPasswordVisible = false;
  bool _isLoading = false;
  bool _isAdminTab = true;
  bool _serverFound = false;
  bool _autoLogin = false;
  bool _autoLoginHovered = false;
  String _serverLabel = '서버 탐색 중...';
  String _statusText = '';

  @override
  void initState() {
    super.initState();

    _autoLogin = (hiveService.sessionRead(HiveKeyModel().autoLoginKey, null) ?? 'false') == 'true';

    final lastUrl = hiveService.sessionRead(HiveKeyModel().lastURL, null);
    if (lastUrl != null && lastUrl.isNotEmpty) {
      socketService.serverUrl = lastUrl;
      socketService.socketIoPath = '/api';
      _serverFound = true;
      _serverLabel = lastUrl;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // ★ 저장된 URL이 있으면 즉시 자동 로그인 시도 (탐색 결과와 무관하게)
      if (lastUrl != null && lastUrl.isNotEmpty) {
        _attemptAutoLogin();
      }
      _startDiscovery();
    });
  }

  @override
  void dispose() {
    _idController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // 내부망에서 서버 자동 탐색 (로그인 전 URL 확보용)
  Future<void> _startDiscovery() async {
    while (mounted) {
      final result = await DiscoveryService.discoverServer(
        timeout: const Duration(seconds: 5),
      );
      if (!mounted) return;

      if (result != null) {
        socketService.serverUrl = result.url;
        socketService.socketIoPath = result.socketPath;
        hiveService.sessionSave(HiveKeyModel().lastURL, result.url);
        setState(() {
          _serverFound = true;
          _serverLabel = result.url;
        });
        // ★ 서버 확보 후 자동 로그인 시도
        _attemptAutoLogin();
        return;
      }

      if (mounted) {
        setState(() {
          _serverFound = false;
          _serverLabel = '서버 탐색 중...';
        });
      }
      await Future.delayed(const Duration(seconds: 5));
    }
  }

  // ★ 자동 로그인: 저장된 세션 쿠키로 소켓 연결 → 서버가 인정하면 바로 메인 화면으로
  Future<void> _attemptAutoLogin() async {
    if (_isLoading) return;

    final cookie = hiveService.sessionRead(HiveKeyModel().sessionCookieKey, null);
    if (!_autoLogin || cookie == null || cookie.isEmpty) return;
    if (socketService.serverUrl.isEmpty) return;

    final lastType = hiveService.sessionRead(HiveKeyModel().autoLoginTypeKey, 'admin') ?? 'admin';
    socketService.type = lastType;
    socketService.resetAutoLoginState();

    setState(() {
      _isLoading = true;
      _statusText = '자동 로그인 중...';
    });

    socketService.connectToMainServer();

    // 최대 10초: 인증 거부 없이 연결 유지되면 성공
    for (int i = 0; i < 20; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      if (socketService.autoLoginExpired) break;
      if (socketService.isMainConnected) {
        // 인증 거부가 늦게 도착할 수 있으므로 1.5초 추가 확인
        await Future.delayed(const Duration(milliseconds: 1500));
        if (!mounted) return;
        if (socketService.autoLoginExpired) break;
        // 자동 로그인은 세션 쿠키만으로 연결하므로 내 userId/이름을 서버에서 복원
        await socketService.restoreSessionInfo();
        if (!mounted) return;
        _goToMain();
        return;
      }
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
        _statusText = '자동 로그인에 실패했습니다 — 다시 로그인해주세요';
      });
    }
  }

  void _goToMain() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      fadeRoute(const CentralControlScreen()),
      (route) => false,
    );
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    if (socketService.serverUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('서버 주소를 찾지 못했습니다'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isLoading = true);

    final loginId = _idController.text.trim();
    final password = _passwordController.text.trim();

    final result = await socketService.login(loginId, password, isAdmin: _isAdminTab);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result['success'] == true) {
      // ★ 마지막 로그인 타입 저장 (자동 로그인용)
      hiveService.sessionSave(
        HiveKeyModel().autoLoginTypeKey,
        _isAdminTab ? 'admin' : 'client',
      );
      _goToMain();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message']?.toString() ?? '로그인 실패'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900],
      body: Column(
        children: [
          _buildTitleBar(),
          Container(height: 1, color: Colors.grey[800]),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: _buildLoginCard(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  // 커스텀 타이틀바
  // ═══════════════════════════════════════════

  Widget _buildTitleBar() {
    return Container(
      height: 40,
      color: Colors.grey[850],
      child: Row(
        children: [
          Expanded(
            child: DragToMoveArea(
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Icon(Icons.admin_panel_settings, size: 18, color: Colors.blue[400]),
                  const SizedBox(width: 6),
                  const Text(
                    'QuePilot',
                    style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
          _buildWindowButton(Icons.minimize, () => windowManager.minimize(), tooltip: '최소화'),
          _buildWindowButton(Icons.crop_square, () async {
            final isMaximized = await windowManager.isMaximized();
            if (isMaximized) {
              windowManager.unmaximize();
            } else {
              windowManager.maximize();
            }
          }, tooltip: '최대화'),
          _buildWindowButton(Icons.close, () => windowManager.close(), tooltip: '닫기', isClose: true),
        ],
      ),
    );
  }

  Widget _buildWindowButton(IconData icon, VoidCallback onTap, {String? tooltip, bool isClose = false}) {
    return StatefulBuilder(
      builder: (context, setHoverState) {
        bool isHovered = false;
        return Tooltip(
          message: tooltip ?? '',
          preferBelow: false,
          waitDuration: const Duration(milliseconds: 400),
          child: MouseRegion(
            onEnter: (_) => setHoverState(() => isHovered = true),
            onExit: (_) => setHoverState(() => isHovered = false),
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: onTap,
              child: Container(
                width: 46,
                height: 40,
                alignment: Alignment.center,
                color: isHovered
                    ? (isClose ? Colors.red.withValues(alpha: 0.3) : Colors.grey[700]!.withValues(alpha: 0.5))
                    : Colors.transparent,
                child: Icon(icon, size: 16, color: Colors.grey[400]),
              ),
            ),
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════
  // 로그인 카드
  // ═══════════════════════════════════════════

  Widget _buildLoginCard() {
    return Column(
      children: [
        // 로고/헤더
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: _serverFound ? Colors.blue : Colors.deepOrange,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: (_serverFound ? Colors.blue : Colors.deepOrange).withValues(alpha: 0.3),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: const Icon(Icons.control_camera, size: 48, color: Colors.white),
        ),
        const SizedBox(height: 16),
        const Text(
          'QuePilot',
          style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 1.5),
        ),
        const SizedBox(height: 8),
        Text(
          _serverFound ? '서버 연결됨: $_serverLabel' : _serverLabel,
          style: TextStyle(color: _serverFound ? Colors.grey[400] : Colors.deepOrange , fontSize: 13),
        ),
        if (_statusText.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            _statusText,
            style: TextStyle(color: Colors.deepOrange[300], fontSize: 12),
          ),
        ],
        const SizedBox(height: 24),

        // 로그인 타입 선택
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('관리자'), icon: Icon(Icons.admin_panel_settings)),
            ButtonSegment(value: false, label: Text('일반 사용자'), icon: Icon(Icons.person)),
          ],
          selected: {_isAdminTab},
          onSelectionChanged: (selection) {
            setState(() => _isAdminTab = selection.first);
          },
          style: SegmentedButton.styleFrom(
            backgroundColor: Colors.grey[850],
            selectedBackgroundColor: Colors.blue.withValues(alpha: 0.25),
            selectedForegroundColor: Colors.white,
            foregroundColor: Colors.grey[400],
            side: BorderSide(color: Colors.grey[800]!),
          ),
        ),
        const SizedBox(height: 16),

        Text(
          _isAdminTab ? '라이선스 계정으로 로그인' : '일반 사용자로 로그인',
          style: TextStyle(color: Colors.grey[500], fontSize: 12),
        ),
        const SizedBox(height: 16),

        // 폼
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildIdField(),
              const SizedBox(height: 16),
              _buildPasswordField(),
              const SizedBox(height: 8),
              _buildAutoLoginRow(),
              const SizedBox(height: 16),
              _buildLoginButton(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildIdField() {
    return TextFormField(
      controller: _idController,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: _isAdminTab ? '라이선스 계정 (이메일)' : '아이디',
        labelStyle: TextStyle(color: Colors.grey[400]),
        hintText: _isAdminTab ? '라이선스 계정 이메일을 입력하세요' : '아이디를 입력하세요',
        hintStyle: TextStyle(color: Colors.grey[600]),
        prefixIcon: Icon(_isAdminTab ? Icons.admin_panel_settings : Icons.person_outline, color: Colors.blue),
        filled: true,
        fillColor: Colors.grey[850],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[800]!, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.blue, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 2),
        ),
      ),
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.next,
      inputFormatters: [
        FilteringTextInputFormatter.deny(RegExp(r'\s')),
      ],
      validator: (value) {
        if (value == null || value.isEmpty) {
          return '아이디를 입력하세요';
        }
        return null;
      },
    );
  }

  Widget _buildPasswordField() {
    return TextFormField(
      controller: _passwordController,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: '비밀번호',
        labelStyle: TextStyle(color: Colors.grey[400]),
        hintText: '비밀번호를 입력하세요',
        hintStyle: TextStyle(color: Colors.grey[600]),
        prefixIcon: const Icon(Icons.lock_outline, color: Colors.blue),
        suffixIcon: IconButton(
          icon: Icon(
            _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
            color: Colors.grey[400],
          ),
          onPressed: () {
            setState(() {
              _isPasswordVisible = !_isPasswordVisible;
            });
          },
        ),
        filled: true,
        fillColor: Colors.grey[850],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[800]!, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.blue, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 2),
        ),
      ),
      obscureText: !_isPasswordVisible,
      keyboardType: TextInputType.visiblePassword,
      textInputAction: TextInputAction.done,
      onFieldSubmitted: (_) => _login(),
      inputFormatters: [
        FilteringTextInputFormatter.deny(RegExp(r'\s')),
      ],
      validator: (value) {
        if (value == null || value.isEmpty) {
          return '비밀번호를 입력하세요';
        }
        return null;
      },
    );
  }

  // ★ 자동 로그인 체크 상태 변경 + 즉시 저장
  void _setAutoLogin(bool value) {
    setState(() => _autoLogin = value);
    hiveService.sessionSave(HiveKeyModel().autoLoginKey, value.toString());
  }

  // ★ 자동 로그인 체크박스
  Widget _buildAutoLoginRow() {
    return Align(
      alignment: Alignment.centerLeft,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _autoLoginHovered = true),
        onExit: (_) => setState(() => _autoLoginHovered = false),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 40,
              height: 40,
              child: Checkbox(
                value: _autoLogin,
                onChanged: (value) => _setAutoLogin(value ?? false),
                activeColor: Colors.blue,
                checkColor: Colors.white,
                side: BorderSide(
                  color: _autoLoginHovered ? Colors.white : Colors.grey[500]!,
                  width: 2,
                ),
              ),
            ),
            GestureDetector(
              onTap: () => _setAutoLogin(!_autoLogin),
              child: Text(
                '자동 로그인',
                style: TextStyle(color: Colors.grey[300], fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoginButton() {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _login,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
          disabledBackgroundColor: Colors.grey[700],
        ),
        child: _isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Text(
                '로그인',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
      ),
    );
  }
}
