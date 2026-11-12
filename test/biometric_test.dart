import 'package:fintrack/security/biometric_key_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cancelar ou "Usar PIN" não invalida a chave biométrica', () {
    const cancel = DeviceBiometricKeyStore.isCancellation;
    expect(cancel('Exception: Biometric authentication error [10]: Cancelado'), isTrue);
    expect(cancel('Exception: Biometric authentication error [13]: Usar PIN'), isTrue);
    expect(cancel('PlatformException(-128, User canceled)'), isTrue);
    expect(cancel('KeyPermanentlyInvalidatedException: Key permanently invalidated'), isFalse);
  });
}
