import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// A thin binding to ONNX Runtime's C API, the copy sherpa-onnx already ships
/// in the APK (`libonnxruntime.so`, 1.28.2), so running another model costs no
/// extra library. Only what a text model needs: load a session, make int64,
/// float and bool tensors, run, read a float output.
///
/// The C API is one struct of function pointers. Indexes below were read from
/// `onnxruntime_c_api.h` at v1.28.2 (`struct OrtApi`, members in order); the
/// struct only ever grows at the end, so they hold for any newer runtime.
class Ort {
  Ort._(this._lib) {
    final base = _lib.lookupFunction<Pointer<_ApiBase> Function(), Pointer<_ApiBase> Function()>('OrtGetApiBase')();
    final getApi = base.ref.getApi.asFunction<Pointer<Pointer<Void>> Function(int)>();
    _api = getApi(_apiVersion);
    if (_api == nullptr) throw StateError('ONNX Runtime does not offer API version $_apiVersion');
    final env = calloc<Pointer<Void>>();
    try {
      _check(_p<_CreateEnvN>(3).asFunction<_CreateEnvD>()(_warningLevel, 'translatorai'.toNativeUtf8(allocator: calloc), env));
      _env = env.value;
      final info = calloc<Pointer<Void>>();
      _check(_p<_CreateCpuMemoryInfoN>(69).asFunction<_CreateCpuMemoryInfoD>()(1, 0, info)); // arena allocator, default memory
      _cpu = info.value;
      calloc.free(info);
    } finally {
      calloc.free(env);
    }
  }

  static const _apiVersion = 17; // any version the runtime offers at least; 17 has all we call
  static const _warningLevel = 2;

  static Ort? _instance;

  /// The runtime, loaded once per isolate.
  static Ort get instance => _instance ??= Ort._(_open());

  static DynamicLibrary _open() {
    if (Platform.isAndroid) return DynamicLibrary.open('libonnxruntime.so');
    if (Platform.isLinux) return DynamicLibrary.open('libonnxruntime.so'); // found through LD_LIBRARY_PATH in tests
    if (Platform.isMacOS) return DynamicLibrary.open('libonnxruntime.dylib');
    if (Platform.isWindows) return DynamicLibrary.open('onnxruntime.dll');
    return DynamicLibrary.process();
  }

  final DynamicLibrary _lib;
  late final Pointer<Pointer<Void>> _api;
  late final Pointer<Void> _env;
  late final Pointer<Void> _cpu;

  Pointer<NativeFunction<N>> _p<N extends Function>(int index) => Pointer.fromAddress(_api[index].address);

  void _check(Pointer<Void> status) {
    if (status == nullptr) return;
    final msg = _p<_GetErrorMessageN>(2).asFunction<_GetErrorMessageD>()(status).toDartString();
    _p<_ReleaseN>(93).asFunction<_ReleaseD>()(status);
    throw OrtException(msg);
  }

  /// Loads a model file. [threads] is the intra-op thread count.
  OrtSession load(String path, {int threads = 4}) {
    final opts = calloc<Pointer<Void>>();
    final out = calloc<Pointer<Void>>();
    final p = path.toNativeUtf8(allocator: calloc);
    try {
      _check(_p<_CreateSessionOptionsN>(10).asFunction<_CreateSessionOptionsD>()(opts));
      _check(_p<_SetIntN>(24).asFunction<_SetIntD>()(opts.value, threads)); // SetIntraOpNumThreads
      _check(_p<_SetIntN>(23).asFunction<_SetIntD>()(opts.value, 99)); // SetSessionGraphOptimizationLevel: all
      _check(_p<_CreateSessionN>(7).asFunction<_CreateSessionD>()(_env, p, opts.value, out));
      return OrtSession._(this, out.value);
    } finally {
      if (opts.value != nullptr) _p<_ReleaseN>(100).asFunction<_ReleaseD>()(opts.value);
      calloc
        ..free(opts)
        ..free(out)
        ..free(p);
    }
  }

  /// A tensor over native memory this object owns (freed with [OrtValue.release]).
  OrtValue _tensor(Pointer<Void> data, int bytes, List<int> shape, int type) {
    final dims = calloc<Int64>(shape.isEmpty ? 1 : shape.length);
    final out = calloc<Pointer<Void>>();
    try {
      for (var i = 0; i < shape.length; i++) {
        dims[i] = shape[i];
      }
      _check(_p<_CreateTensorN>(49).asFunction<_CreateTensorD>()(_cpu, data, bytes, dims, shape.length, type, out));
      return OrtValue._(this, out.value, data);
    } finally {
      calloc
        ..free(dims)
        ..free(out);
    }
  }

  OrtValue int64(List<int> values, List<int> shape) {
    final data = calloc<Int64>(values.isEmpty ? 1 : values.length);
    for (var i = 0; i < values.length; i++) {
      data[i] = values[i];
    }
    return _tensor(data.cast(), values.length * 8, shape, 7);
  }

  OrtValue float32(Float32List values, List<int> shape) {
    final data = calloc<Float>(values.isEmpty ? 1 : values.length);
    data.asTypedList(values.length).setAll(0, values);
    return _tensor(data.cast(), values.length * 4, shape, 1);
  }

  OrtValue boolean(bool value) {
    final data = calloc<Uint8>(1)..value = value ? 1 : 0;
    return _tensor(data.cast(), 1, const [1], 9);
  }
}

class OrtException implements Exception {
  OrtException(this.message);
  final String message;
  @override
  String toString() => 'ONNX Runtime: $message';
}

class OrtSession {
  OrtSession._(this._ort, this._handle);
  final Ort _ort;
  Pointer<Void> _handle;

  /// Runs the model. Outputs come back in the order of [outputs]; the caller
  /// releases them (and its own inputs).
  List<OrtValue> run(Map<String, OrtValue> inputs, List<String> outputs) {
    final arena = Arena();
    try {
      final names = arena<Pointer<Utf8>>(inputs.length);
      final values = arena<Pointer<Void>>(inputs.length);
      var i = 0;
      for (final e in inputs.entries) {
        names[i] = e.key.toNativeUtf8(allocator: arena);
        values[i] = e.value._handle;
        i++;
      }
      final outNames = arena<Pointer<Utf8>>(outputs.length);
      for (var k = 0; k < outputs.length; k++) {
        outNames[k] = outputs[k].toNativeUtf8(allocator: arena);
      }
      final out = arena<Pointer<Void>>(outputs.length);
      for (var k = 0; k < outputs.length; k++) {
        out[k] = nullptr;
      }
      _ort._check(_ort._p<_RunN>(9).asFunction<_RunD>()(_handle, nullptr, names, values, inputs.length, outNames, outputs.length, out));
      return [for (var k = 0; k < outputs.length; k++) OrtValue._(_ort, out[k], null)];
    } finally {
      arena.releaseAll();
    }
  }

  void release() {
    if (_handle == nullptr) return;
    _ort._p<_ReleaseN>(95).asFunction<_ReleaseD>()(_handle);
    _handle = nullptr;
  }
}

class OrtValue {
  OrtValue._(this._ort, this._handle, this._owned);
  final Ort _ort;
  Pointer<Void> _handle;
  final Pointer<Void>? _owned; // our buffer behind a tensor we made

  List<int> get shape {
    final info = calloc<Pointer<Void>>();
    final count = calloc<Size>();
    try {
      _ort._check(_ort._p<_GetTypeShapeN>(65).asFunction<_GetTypeShapeD>()(_handle, info));
      _ort._check(_ort._p<_GetDimCountN>(61).asFunction<_GetDimCountD>()(info.value, count));
      final dims = calloc<Int64>(count.value == 0 ? 1 : count.value);
      try {
        _ort._check(_ort._p<_GetDimsN>(62).asFunction<_GetDimsD>()(info.value, dims, count.value));
        return [for (var i = 0; i < count.value; i++) dims[i]];
      } finally {
        calloc.free(dims);
      }
    } finally {
      if (info.value != nullptr) _ort._p<_ReleaseN>(99).asFunction<_ReleaseD>()(info.value);
      calloc
        ..free(info)
        ..free(count);
    }
  }

  /// A view of a float tensor's data (valid until [release]).
  Float32List floats() {
    final p = calloc<Pointer<Void>>();
    try {
      _ort._check(_ort._p<_GetDataN>(51).asFunction<_GetDataD>()(_handle, p));
      final n = shape.fold(1, (a, b) => a * b);
      return p.value.cast<Float>().asTypedList(n);
    } finally {
      calloc.free(p);
    }
  }

  void release() {
    if (_handle == nullptr) return;
    _ort._p<_ReleaseN>(96).asFunction<_ReleaseD>()(_handle);
    _handle = nullptr;
    if (_owned != null) calloc.free(_owned);
  }
}

final class _ApiBase extends Struct {
  external Pointer<NativeFunction<Pointer<Pointer<Void>> Function(Uint32)>> getApi;
  external Pointer<NativeFunction<Pointer<Utf8> Function()>> getVersionString;
}

typedef _CreateEnvN = Pointer<Void> Function(Int32, Pointer<Utf8>, Pointer<Pointer<Void>>);
typedef _CreateEnvD = Pointer<Void> Function(int, Pointer<Utf8>, Pointer<Pointer<Void>>);
typedef _GetErrorMessageN = Pointer<Utf8> Function(Pointer<Void>);
typedef _GetErrorMessageD = Pointer<Utf8> Function(Pointer<Void>);
typedef _ReleaseN = Void Function(Pointer<Void>);
typedef _ReleaseD = void Function(Pointer<Void>);
typedef _CreateSessionOptionsN = Pointer<Void> Function(Pointer<Pointer<Void>>);
typedef _CreateSessionOptionsD = Pointer<Void> Function(Pointer<Pointer<Void>>);
typedef _SetIntN = Pointer<Void> Function(Pointer<Void>, Int32);
typedef _SetIntD = Pointer<Void> Function(Pointer<Void>, int);
typedef _CreateSessionN = Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Void>, Pointer<Pointer<Void>>);
typedef _CreateSessionD = Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Void>, Pointer<Pointer<Void>>);
typedef _CreateCpuMemoryInfoN = Pointer<Void> Function(Int32, Int32, Pointer<Pointer<Void>>);
typedef _CreateCpuMemoryInfoD = Pointer<Void> Function(int, int, Pointer<Pointer<Void>>);
typedef _CreateTensorN = Pointer<Void> Function(
    Pointer<Void>, Pointer<Void>, Size, Pointer<Int64>, Size, Int32, Pointer<Pointer<Void>>);
typedef _CreateTensorD = Pointer<Void> Function(
    Pointer<Void>, Pointer<Void>, int, Pointer<Int64>, int, int, Pointer<Pointer<Void>>);
typedef _RunN = Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Pointer<Pointer<Utf8>>, Pointer<Pointer<Void>>, Size,
    Pointer<Pointer<Utf8>>, Size, Pointer<Pointer<Void>>);
typedef _RunD = Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Pointer<Pointer<Utf8>>, Pointer<Pointer<Void>>, int,
    Pointer<Pointer<Utf8>>, int, Pointer<Pointer<Void>>);
typedef _GetDataN = Pointer<Void> Function(Pointer<Void>, Pointer<Pointer<Void>>);
typedef _GetDataD = Pointer<Void> Function(Pointer<Void>, Pointer<Pointer<Void>>);
typedef _GetTypeShapeN = Pointer<Void> Function(Pointer<Void>, Pointer<Pointer<Void>>);
typedef _GetTypeShapeD = Pointer<Void> Function(Pointer<Void>, Pointer<Pointer<Void>>);
typedef _GetDimCountN = Pointer<Void> Function(Pointer<Void>, Pointer<Size>);
typedef _GetDimCountD = Pointer<Void> Function(Pointer<Void>, Pointer<Size>);
typedef _GetDimsN = Pointer<Void> Function(Pointer<Void>, Pointer<Int64>, Size);
typedef _GetDimsD = Pointer<Void> Function(Pointer<Void>, Pointer<Int64>, int);
