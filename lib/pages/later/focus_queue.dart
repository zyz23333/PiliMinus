import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/user.dart';
import 'package:PiliPlus/models_new/later/data.dart';
import 'package:PiliPlus/models_new/later/list.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:flutter/foundation.dart';

abstract class LaterQueueSource {
  Future<LoadingState<LaterData>> read({
    required Account account,
    required int page,
    required bool asc,
    required int viewed,
  });

  Future<LoadingState<void>> remove({
    required Account account,
    required int aid,
  });
}

class BiliLaterQueueSource implements LaterQueueSource {
  const BiliLaterQueueSource();

  @override
  Future<LoadingState<LaterData>> read({
    required Account account,
    required int page,
    required bool asc,
    required int viewed,
  }) => UserHttp.seeYouLater(
    account: account,
    page: page,
    asc: asc,
    viewed: viewed,
  );

  @override
  Future<LoadingState<void>> remove({
    required Account account,
    required int aid,
  }) => UserHttp.toViewDel(
    account: account,
    aids: aid.toString(),
    showToast: false,
  );
}

enum LaterQueueStatus { signedOut, loading, ready, empty, error }

/// Owns only the queue head. Player episode changes never change its identity.
class LaterFocusController extends ChangeNotifier {
  LaterFocusController({required this.source, required this.activeAccount});

  final LaterQueueSource source;
  final Account Function() activeAccount;
  Account? _account;
  int _generation = 0;
  bool _disposed = false;

  LaterQueueStatus status = LaterQueueStatus.signedOut;
  LaterItemModel? current;
  bool completing = false;
  String? error;
  String? completionError;

  bool _isCurrent(Account account, int generation) =>
      !_disposed &&
      generation == _generation &&
      identical(account, _account) &&
      identical(account, activeAccount());

  void clearSession() {
    ++_generation;
    _account = null;
    current = null;
    completing = false;
    error = completionError = null;
    status = LaterQueueStatus.signedOut;
    notifyListeners();
  }

  Future<void> synchronizeAccount() async {
    if (!identical(activeAccount(), _account)) await refresh();
  }

  Future<void> refresh() async {
    if (_disposed) return;
    final account = activeAccount();
    if (identical(account, _account) && completing) return;
    _account = account;
    final generation = ++_generation;
    current = null;
    completing = false;
    error = completionError = null;
    status = account.isLogin
        ? LaterQueueStatus.loading
        : LaterQueueStatus.signedOut;
    notifyListeners();
    if (!account.isLogin) return;
    await _read(account, generation);
  }

  Future<void> _read(Account account, int generation) async {
    try {
      // Re-read page one after every removal: deleting shifts all subsequent pages.
      final result = await source.read(
        account: account,
        page: 1,
        asc: true,
        viewed: 0,
      );
      if (!_isCurrent(account, generation)) return;
      if (result case Success(:final response)) {
        current = response.list?.firstOrNull;
        status = current == null
            ? LaterQueueStatus.empty
            : LaterQueueStatus.ready;
      } else {
        error = result.toString();
        status = LaterQueueStatus.error;
      }
    } catch (e) {
      if (!_isCurrent(account, generation)) return;
      error = e.toString();
      status = LaterQueueStatus.error;
    }
    if (_isCurrent(account, generation)) {
      completing = false;
      notifyListeners();
    }
  }

  Future<void> complete() async {
    final account = _account;
    final item = current;
    final generation = _generation;
    if (account == null ||
        item?.aid == null ||
        completing ||
        status != LaterQueueStatus.ready ||
        !_isCurrent(account, generation)) {
      return;
    }
    completing = true;
    completionError = null;
    notifyListeners();
    try {
      final result = await source.remove(account: account, aid: item!.aid!);
      if (!_isCurrent(account, generation)) return;
      if (result.isSuccess) {
        // The deleted head is no longer actionable, even if the following read fails.
        current = null;
        status = LaterQueueStatus.loading;
        notifyListeners();
        await _read(account, generation);
        return;
      }
      completionError = result.toString();
    } catch (e) {
      if (!_isCurrent(account, generation)) return;
      completionError = e.toString();
    }
    if (_isCurrent(account, generation)) {
      completing = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    super.dispose();
  }
}
