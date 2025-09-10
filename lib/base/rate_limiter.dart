// lib/base/rate_limiter.dart

import 'dart:async';

/// 一个简单的速率限制器，用于控制请求频率。
class RateLimiter {
  final Duration _interval;
  DateTime _lastRequestTime = DateTime(0);

  /// 根据每分钟请求数(RPM)或每秒查询数(QPS)创建速率限制器。
  /// [rpm] 和 [qps] 只有一个应该被设置。如果都设置了，[qps] 优先。
  RateLimiter({int? rpm, int? qps}) : _interval = _calculateInterval(rpm: rpm, qps: qps);

  static Duration _calculateInterval({int? rpm, int? qps}) {
    if (qps != null && qps > 0) {
      // QPS 优先
      return Duration(microseconds: (1000000 / qps).round());
    }
    if (rpm != null && rpm > 0) {
      return Duration(milliseconds: (60 * 1000 / rpm).round());
    }
    // 如果没有设置速率限制，则间隔为零
    return Duration.zero;
  }

  /// 获取一个“令牌”。
  /// 如果距离上次请求的时间小于设定的间隔，则会等待相应的时间。
  /// 返回一个 Future, 在可以发送下一个请求时完成。
  Future<void> acquire() async {
    if (_interval == Duration.zero) {
      // 没有限制，立即返回
      return;
    }

    final now = DateTime.now();
    final timeSinceLast = now.difference(_lastRequestTime);

    if (timeSinceLast < _interval) {
      final delay = _interval - timeSinceLast;
      await Future.delayed(delay);
    }
    
    _lastRequestTime = DateTime.now();
  }
}