import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/haptics.dart';
import '../../core/links.dart';
import '../../core/look.dart';
import '../../core/models.dart';
import '../../core/motion.dart';
import '../../core/native.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/smart_image.dart';

/// Passport's own page polls every 4 seconds; faster only adds requests to a rate-limited host.
const _pollEvery = Duration(seconds: 4);

/// The QR login: a code another phone's Weibo app can scan, and a button that hands the same
/// code to the Weibo app on this phone, where 允许登录 confirms it. [onConfirmed] gets the first
/// hop of the SSO chain, which the WebView must follow to receive the cookies.
class QrLoginPanel extends StatefulWidget {
  const QrLoginPanel({super.key, required this.active, required this.onConfirmed});

  /// Off while the WebView is in front, so the code is not polled behind it.
  final bool active;
  final ValueChanged<String> onConfirmed;

  @override
  State<QrLoginPanel> createState() => _QrLoginPanelState();
}

class _QrLoginPanelState extends State<QrLoginPanel> with WidgetsBindingObserver {
  QrLogin? _qr;
  QrLoginStatus? _status;
  String? _error;
  bool _loading = false;
  bool _polling = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didUpdateWidget(QrLoginPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active == oldWidget.active) return;
    if (!widget.active) {
      _timer?.cancel();
    } else if (_status?.state == QrLoginState.failed || _status?.state == QrLoginState.confirmed) {
      _load();
    } else {
      _schedule();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  /// Back from the Weibo app after 允许登录: check at once rather than at the next tick.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.active) _poll();
  }

  Future<void> _load() async {
    _timer?.cancel();
    setState(() {
      _loading = true;
      _error = null;
      _status = null;
    });
    try {
      final qr = await WeiboApi.instance.qrLogin();
      if (!mounted) return;
      setState(() => _qr = qr);
      _schedule();
    } catch (error) {
      if (mounted) setState(() => _error = error is ApiException ? error.message : '二维码获取失败');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _schedule() {
    _timer?.cancel();
    if (_qr == null || !widget.active) return;
    _timer = Timer.periodic(_pollEvery, (_) => _poll());
  }

  Future<void> _poll() async {
    final qr = _qr;
    if (qr == null || _polling || !mounted) return;
    _polling = true;
    try {
      final status = await WeiboApi.instance.qrLoginStatus(qr.qrid);
      if (!mounted || qr != _qr) return;
      final scannedNow = status.state == QrLoginState.scanned && _status?.state != QrLoginState.scanned;
      setState(() => _status = status);
      if (scannedNow) Haptic.selection.play();
      switch (status.state) {
        case QrLoginState.confirmed:
          _timer?.cancel();
          final url = status.url;
          if (url != null && url.startsWith('https://')) {
            widget.onConfirmed(url);
          } else {
            setState(() => _error = '登录确认了，但没有拿到跳转地址，请刷新二维码重试');
          }
        case QrLoginState.failed:
          _timer?.cancel();
        case QrLoginState.waiting:
        case QrLoginState.scanned:
          break;
      }
    } catch (_) {
      // A missed poll is tried again on the next tick.
    } finally {
      _polling = false;
    }
  }

  Future<void> _openWeiboApp() async {
    final qr = _qr;
    if (qr == null) return;
    final opened = await Native.openUrl(weiboAppBrowserUrl(qr.scanUrl), package: 'com.sina.weibo');
    if (!opened && mounted) {
      Haptic.error.play();
      showMessage(context, '没有找到微博客户端，可以用另一台手机的微博扫码，或换下面的方式登录');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final state = _status?.state;
    final expired = state == QrLoginState.failed;
    final caption = switch (state) {
      QrLoginState.scanned => '已扫描，请在微博 App 中点「允许登录」',
      QrLoginState.failed => _status?.message ?? '二维码已失效',
      QrLoginState.confirmed => '正在完成登录…',
      _ => '用微博 App 扫一扫，或直接在本机微博 App 中确认',
    };
    return Material(
      color: InfChrome.of(context).fill(scheme, scheme.surfaceContainerLow, 1),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          children: [
            Text('扫码登录', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              '已登录的微博 App 确认即可，不需要验证码',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            SizedBox.square(
              dimension: 180,
              child: DecoratedBox(
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                child: _code(scheme, expired: expired, scanned: state == QrLoginState.scanned),
              ),
            ),
            const SizedBox(height: 12),
            AnimatedSwitcher(
              duration: InfMotion.content,
              child: Text(
                _error ?? caption,
                key: ValueKey(_error ?? caption),
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(color: _error != null || expired ? scheme.error : scheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: expired || _error != null
                  ? FilledButton.tonalIcon(
                      onPressed: _loading ? null : _load,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('刷新二维码'),
                    )
                  : FilledButton.icon(
                      onPressed: _qr == null || state == QrLoginState.confirmed ? null : _openWeiboApp,
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: const Text('在本机微博 App 中确认'),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _code(ColorScheme scheme, {required bool expired, required bool scanned}) {
    final qr = _qr;
    if (qr == null) {
      return Center(
        child: _loading
            ? const CircularProgressIndicator()
            : Icon(Icons.qr_code_2_rounded, size: 64, color: Colors.grey.shade400),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: SmartImage(url: qr.imageUrl, fit: BoxFit.contain, placeholderColor: Colors.white),
        ),
        if (expired || scanned)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ColoredBox(
              color: Colors.white.withValues(alpha: 0.9),
              child: Icon(
                expired ? Icons.refresh_rounded : Icons.check_circle_rounded,
                size: 56,
                color: expired ? Colors.grey.shade600 : scheme.primary,
              ),
            ),
          ),
      ],
    );
  }
}
