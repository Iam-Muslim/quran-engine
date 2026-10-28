// dart:ffi implementation of QvpBackend.
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Path, PathFillType, Rect;

import 'package:ffi/ffi.dart' as pffi;
import 'package:flutter/foundation.dart';

import '../bindings.dart';
import '../types.dart';
import 'qvp_backend.dart';

/// Creates the default native backend over dart:ffi.
QvpBackend createDefaultBackend({String? path, dynamic library}) =>
    QvpNativeBackend(library: library is ffi.DynamicLibrary ? library : null, path: path);

/// Throws UnsupportedError on native platforms.
Future<QvpBackend> initWebBackend({List<int>? wasmBytes, String? wasmAssetPath, String? wasmUrl}) async =>
    throw UnsupportedError('initWebBackend is only supported on Web platforms.');

/// Native page handle wrapping a C pointer.
final class NativePageHandle implements PageHandle {
  NativePageHandle(this.pointer);
  ffi.Pointer<QvpPageC> pointer;
}

/// Native atlas handle wrapping a C pointer.
final class NativeAtlasHandle implements AtlasHandle {
  NativeAtlasHandle(this.pointer);
  ffi.Pointer<QvpAtlasC> pointer;
}

/// Native passage handle wrapping a C pointer.
final class NativePassageHandle implements PassageHandle {
  NativePassageHandle(this.pointer);
  ffi.Pointer<QvpPassageC> pointer;
}

/// Native ornaments handle wrapping a C pointer.
final class NativeOrnamentsHandle implements OrnamentsHandle {
  NativeOrnamentsHandle(this.pointer);
  ffi.Pointer<QvpOrnamentsC> pointer;
}

/// Native backend implementation of [QvpBackend] over `dart:ffi`.
class QvpNativeBackend implements QvpBackend {
  QvpNativeBackend({ffi.DynamicLibrary? library, String? path})
      : b = QvpBindings(library ?? resolveLibrary(path: path)) {
    _scratch = pffi.calloc<ffi.Uint8>(scratchBytes);
    _str = pffi.calloc<QvpStrC>();
    _target = pffi.calloc<QvpTargetC>();
    _sel = pffi.calloc<QvpSelectorC>();
    _hl = pffi.calloc<QvpHighlightStyleC>();
    _theme = pffi.calloc<QvpThemeC>();
    _spec = pffi.calloc<QvpLayoutSpecC>();
    _layout = pffi.calloc<QvpLayoutC>();
    _hitOpt = pffi.calloc<QvpHitOptionsC>();
    _hit = pffi.calloc<QvpHitC>();
    _crop = pffi.calloc<QvpCropBoundsC>();
  }

  static ffi.DynamicLibrary resolveLibrary({String? path}) {
    if (kIsWeb) {
      throw UnsupportedError('QvpNativeBackend runs on native platforms.');
    }
    if (path != null) return ffi.DynamicLibrary.open(path);
    if (Platform.isAndroid) return ffi.DynamicLibrary.open('libqvp_ffi.so');
    if (Platform.isIOS || Platform.isMacOS) {
      final lib = ffi.DynamicLibrary.process();
      try {
        lib.lookup<ffi.NativeFunction<ffi.IntPtr Function()>>('qvp_flutter_dummy_symbol_to_enforce_linking');
      } catch (_) {}
      return lib;
    }
    final env = Platform.environment['QVP_LIB'];
    if (env != null && env.isNotEmpty) return ffi.DynamicLibrary.open(env);
    if (Platform.isWindows) {
      final local = File('qvp_ffi.dll');
      if (local.existsSync()) return ffi.DynamicLibrary.open(local.absolute.path);
      final exeDir = File(Platform.resolvedExecutable).parent;
      final inExe = File('${exeDir.path}${Platform.pathSeparator}qvp_ffi.dll');
      if (inExe.existsSync()) return ffi.DynamicLibrary.open(inExe.path);
      return ffi.DynamicLibrary.open('qvp_ffi.dll');
    }
    if (Platform.isLinux) {
      final local = File('libqvp_ffi.so');
      if (local.existsSync()) return ffi.DynamicLibrary.open(local.absolute.path);
      final exeDir = File(Platform.resolvedExecutable).parent;
      final inLib = File('${exeDir.path}/lib/libqvp_ffi.so');
      if (inLib.existsSync()) return ffi.DynamicLibrary.open(inLib.path);
      return ffi.DynamicLibrary.open('libqvp_ffi.so');
    }
    return ffi.DynamicLibrary.open('libqvp_ffi.so');
  }

  static const int scratchBytes = 1 << 18;

  final QvpBindings b;
  late final ffi.Pointer<ffi.Uint8> _scratch;
  late final ffi.Pointer<QvpStrC> _str;
  late final ffi.Pointer<QvpTargetC> _target;
  late final ffi.Pointer<QvpSelectorC> _sel;
  late final ffi.Pointer<QvpHighlightStyleC> _hl;
  late final ffi.Pointer<QvpThemeC> _theme;
  late final ffi.Pointer<QvpLayoutSpecC> _spec;
  late final ffi.Pointer<QvpLayoutC> _layout;
  late final ffi.Pointer<QvpHitOptionsC> _hitOpt;
  late final ffi.Pointer<QvpHitC> _hit;
  late final ffi.Pointer<QvpCropBoundsC> _crop;
  bool _disposed = false;

  ffi.Pointer<QvpPageC> _page(PageHandle h) => (h as NativePageHandle).pointer;
  ffi.Pointer<QvpAtlasC> _atlas(AtlasHandle h) => (h as NativeAtlasHandle).pointer;
  ffi.Pointer<QvpPassageC> _passage(PassageHandle h) => (h as NativePassageHandle).pointer;
  ffi.Pointer<QvpOrnamentsC> _ornaments(OrnamentsHandle h) => (h as NativeOrnamentsHandle).pointer;

  ffi.Pointer<N> _out<N extends ffi.NativeType>() => _scratch.cast<N>();
  int _cap(int elemSize) => scratchBytes ~/ elemSize;

  static String str(QvpStrC s) => s.len == 0 || s.ptr == ffi.nullptr ? '' : utf8.decode(s.ptr.asTypedList(s.len));
  String _s() => str(_str.ref);

  R withBytes<R>(List<int> bytes, R Function(ffi.Pointer<ffi.Uint8> p, int len) f) {
    final n = bytes.length;
    final p = pffi.malloc<ffi.Uint8>(n == 0 ? 1 : n);
    try {
      if (n > 0) p.asTypedList(n).setAll(0, bytes);
      return f(p, n);
    } finally {
      pffi.malloc.free(p);
    }
  }

  R withString<R>(String s, R Function(ffi.Pointer<ffi.Uint8> p, int len) f) => withBytes(utf8.encode(s), f);

  R withU32<R>(List<int> v, R Function(ffi.Pointer<ffi.Uint32> p, int n) f) {
    final p = pffi.malloc<ffi.Uint32>(v.isEmpty ? 1 : v.length);
    try {
      p.asTypedList(v.length).setAll(0, v);
      return f(p, v.length);
    } finally {
      pffi.malloc.free(p);
    }
  }

  List<int> _u32(int n) => List<int>.from(_out<ffi.Uint32>().asTypedList(n.clamp(0, _cap(ffi.sizeOf<ffi.Uint32>()))), growable: false);

  String _name(void Function(int, ffi.Pointer<QvpStrC>) fn, int v) {
    fn(v, _str);
    return _s();
  }

  @override
  String get version {
    b.version(_str);
    return _s();
  }

  @override
  int get formatVersion => b.formatVersion();

  @override
  String get engineName => b.engineName().cast<pffi.Utf8>().toDartString();

  @override
  int nameCount(int table) => b.nameCount(table);

  @override
  String name(int table, int id) => _name((v, out) => b.name(table, v, out), id);

  @override
  int nameId(int table, String s) => withString(s, (p, n) => b.nameId(table, p, n));

  @override
  String markName(int m) => _name(b.markName, m);

  @override
  String familyName(int f) => _name(b.familyName, f);

  @override
  String kindName(int k) => _name(b.kindName, k);

  @override
  String categoryName(int c) => _name(b.categoryName, c);

  @override
  int markCategory(int m) => b.markCategory(m);

  @override
  int markFromName(String s) => withString(s, (p, n) => b.markFromName(p, n));

  @override
  String arabic(int op, String s) => withString(s, (p, n) {
        b.arabic(op, p, n, _str);
        return _s();
      });

  @override
  QvpView viewZoomAbout(QvpView view, double focalX, double focalY, double factor, {double min = 0, double max = 0}) {
    final v = pffi.calloc<QvpViewC>(), out = pffi.calloc<QvpViewC>();
    try {
      v.ref.scale = view.scale;
      v.ref.offsetX = view.offsetX;
      v.ref.offsetY = view.offsetY;
      b.viewZoomAbout(v, focalX, focalY, factor, min, max, out);
      return QvpView(scale: out.ref.scale, offsetX: out.ref.offsetX, offsetY: out.ref.offsetY);
    } finally {
      pffi.calloc.free(v);
      pffi.calloc.free(out);
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final p in <ffi.Pointer>[_scratch, _str, _target, _sel, _hl, _theme, _spec, _layout, _hitOpt, _hit, _crop]) {
      pffi.calloc.free(p);
    }
  }

  // ── Page lifecycle ──

  @override
  (PageHandle, QvpPageData) pageLoad(Uint8List bytes) {
    final h = withBytes(bytes, (p, n) => b.pageLoad(p, n));
    if (h == ffi.nullptr) throw const FormatException('qvp_page_load failed');

    final info = pffi.calloc<QvpPageInfoC>();
    final geom = pffi.calloc<QvpGeometryC>();
    try {
      b.pageInfo(h, info);
      final i = info.ref;
      b.geometry(h, geom);
      final g = geom.ref;

      final data = QvpPageData(
        width: i.width,
        height: i.height,
        lineSpacing: b.pageLineSpacing(h),
        page: i.page,
        nLines: i.nLines,
        nAyahs: i.nAyahs,
        nWords: i.nWords,
        nPaths: i.nPaths,
        nDecorations: i.nDecorations,
        ops: Uint8List.fromList(g.ops.asTypedList(g.opsLen)),
        pts: Float32List.fromList(g.pts.asTypedList(g.ptsLen)),
        table: Uint32List.fromList(g.table.asTypedList(g.nPaths * 8)),
        words: List.generate(i.nWords, (w) => _readWord(h, w), growable: false),
        ayahs: List.generate(i.nAyahs, (a) => _readAyah(h, a), growable: false),
        lines: List.generate(i.nLines, (l) => _readLine(h, l), growable: false),
        decorations: List.generate(i.nDecorations, (d) => _readDeco(h, d), growable: false),
      );
      return (NativePageHandle(h), data);
    } finally {
      pffi.calloc.free(info);
      pffi.calloc.free(geom);
    }
  }

  @override
  void pageFree(PageHandle handle) {
    final p = _page(handle);
    if (p != ffi.nullptr) {
      b.pageFree(p);
      (handle as NativePageHandle).pointer = ffi.nullptr;
    }
  }

  QvpWordInfo _readWord(ffi.Pointer<QvpPageC> h, int i) {
    final o = pffi.calloc<QvpWordInfoC>();
    try {
      if (b.wordInfo(h, i, o) == 0) throw StateError('qvp_word_info($i) failed');
      final w = o.ref;
      return QvpWordInfo(
        index: i,
        surah: w.surah,
        ayah: w.ayah,
        word: w.word,
        line: w.lineNumber,
        ayahIndex: w.ayahIndex,
        lineIndex: w.lineIndex,
        x0: w.x0,
        y0: w.y0,
        x1: w.x1,
        y1: w.y1,
        text: str(w.text),
        firstPath: w.firstPath,
        nPaths: w.nPaths,
      );
    } finally {
      pffi.calloc.free(o);
    }
  }

  QvpAyahInfo _readAyah(ffi.Pointer<QvpPageC> h, int i) {
    final o = pffi.calloc<QvpAyahInfoC>();
    try {
      if (b.ayahInfo(h, i, o) == 0) throw StateError('qvp_ayah_info($i) failed');
      final a = o.ref;
      return QvpAyahInfo(
        index: i,
        surah: a.surah,
        ayah: a.ayah,
        fragment: a.fragment,
        fragments: a.fragments,
        flags: a.flags,
        rubuAlHizb: a.rubuAlHizb,
        firstWord: a.firstWord,
        nWords: a.nWords,
        ayahMarkDecoration: a.ayahMarkDecoration,
        x0: a.x0,
        y0: a.y0,
        x1: a.x1,
        y1: a.y1,
      );
    } finally {
      pffi.calloc.free(o);
    }
  }

  QvpLineInfo _readLine(ffi.Pointer<QvpPageC> h, int i) {
    final o = pffi.calloc<QvpLineInfoC>();
    try {
      if (b.lineInfo(h, i, o) == 0) throw StateError('qvp_line_info($i) failed');
      final l = o.ref;
      return QvpLineInfo(
        index: i,
        lineNumber: l.lineNumber,
        isHeader: l.isHeader != 0,
        firstWord: l.firstWord,
        nWords: l.nWords,
        x0: l.x0,
        y0: l.y0,
        x1: l.x1,
        y1: l.y1,
        bandY0: l.bandY0,
        bandY1: l.bandY1,
        centre: l.centre,
      );
    } finally {
      pffi.calloc.free(o);
    }
  }

  QvpDecorationInfo _readDeco(ffi.Pointer<QvpPageC> h, int i) {
    final o = pffi.calloc<QvpDecorationInfoC>();
    try {
      if (b.decorationInfo(h, i, o) == 0) throw StateError('qvp_decoration_info($i) failed');
      final d = o.ref;
      return QvpDecorationInfo(
        index: i,
        decoration: d.decoration,
        surah: d.surah,
        ayah: d.ayah,
        line: d.line,
        x0: d.x0,
        y0: d.y0,
        x1: d.x1,
        y1: d.y1,
        text: str(d.text),
        firstPath: d.firstPath,
        nPaths: d.nPaths,
      );
    } finally {
      pffi.calloc.free(o);
    }
  }

  // ── Target marshalling ──
  R _t<R>(PageHandle handle, QvpTarget target, R Function(ffi.Pointer<QvpTargetC> t) f) {
    var t = target;
    if (t.wordKey != null) {
      final i = findWord(handle, t.wordKey![0], t.wordKey![1], t.wordKey![2]);
      t = i >= 0 ? T.word(i) : T.words(const []);
    }
    final r = _target.ref;
    r.target = t.target;
    r.a = t.a;
    r.b = t.b;
    r.c = t.c;
    r.nWords = 0;
    r.words = ffi.nullptr;
    if (t.words != null) {
      return withU32(t.words!, (p, n) {
        r.words = p;
        r.nWords = n;
        return f(_target);
      });
    }
    return f(_target);
  }

  ffi.Pointer<QvpSelectorC> _writeSel(QvpSelector s) {
    final r = _sel.ref;
    r.selector = s.selector;
    r.a = s.a;
    r.b = s.b;
    r.c = s.c;
    return _sel;
  }

  ffi.Pointer<QvpHighlightStyleC> _writeHl(QvpHighlightStyle st) {
    final r = _hl.ref;
    r.mode = const {'ink': 0, 'band': 1, 'both': 2}[st.mode] ?? 1;
    r.height = st.height == 'ink' ? 1 : 0;
    r.ink = rgba(st.ink);
    r.band = rgba(st.band);
    r.padX = st.padX;
    r.padY = st.padY;
    r.radius = st.radius;
    r.seam = st.seam;
    r.transitionMs = st.ms;
    r.layer = st.layer;
    return _hl;
  }

  void _writeSpec(QvpLayoutSpec spec) {
    final s = _spec.ref;
    s.viewportW = spec.viewportW;
    s.viewportH = spec.viewportH;
    s.padTop = spec.padTop;
    s.padBottom = spec.padBottom;
    s.padLeft = spec.padLeft;
    s.padRight = spec.padRight;
    s.lineSpacing = spec.lineSpacing;
    s.fillHeight = spec.fillHeight ? 1 : 0;
    s.gridLines = spec.gridLines;
    s.cropLeft = spec.cropLeft;
    s.cropRight = spec.cropRight;
    s.maxAspectSlack = spec.maxAspectSlack;
    final r = spec.reflow;
    s.reflowZoom = r == null ? 0 : r.zoom;
    s.reflowFill = r == null ? 255 : (const {'ragged': 0, 'justified': 1, 'centred': 2, 'centered': 2}[r.fill] ?? 255);
    s.reflowBreaks = r == null ? 255 : (const {'greedy': 0, 'even': 1, 'fitted': 2, 'printed': 3}[r.breaks] ?? 255);
    s.reflowGaps = r == null ? 1 : (r.gaps == 'printed' ? 0 : 1);
    s.reflowWordGap = r == null ? 0 : r.wordGap;
    s.reflowMaxStretch = r == null ? 0 : r.maxStretch;
    s.reflowRelax = r == null ? -1 : r.relax;
    s.bannerZoom = spec.bannerZoom;
    s.surahFrames = spec.surahFrames ? 1 : 0;
  }

  void _writeZoom(ffi.Pointer<QvpZoomC> z, QvpZoom v) {
    z.ref.mode = v.mode.index;
    z.ref.step = v.step;
    z.ref.zoom = v.zoom;
  }

  void _writeView(ffi.Pointer<QvpViewC> p, QvpView v) {
    p.ref.scale = v.scale;
    p.ref.offsetX = v.offsetX;
    p.ref.offsetY = v.offsetY;
  }

  QvpZoom _readZoom(QvpZoomC z) =>
      QvpZoom(mode: QvpZoomMode.values[z.mode.clamp(0, QvpZoomMode.values.length - 1)], step: z.step, zoom: z.zoom);

  QvpView _readView(QvpViewC v) => QvpView(scale: v.scale, offsetX: v.offsetX, offsetY: v.offsetY);

  static int _idx(int v) => v == qvpNone ? -1 : v;

  QvpHit? _readHit(int ok) {
    if (ok == 0) return null;
    final h = _hit.ref;
    final w = _idx(h.word);
    return QvpHit(
      word: w,
      path: _idx(h.path),
      decoration: _idx(h.decoration),
      line: h.line,
      distance: h.distance,
      isExact: h.isExact != 0,
    );
  }

  ffi.Pointer<QvpHitOptionsC> _opt(QvpHitOptions o) {
    final r = _hitOpt.ref;
    r.maxDistance = o.maxDistance;
    r.gapBias = o.gapBias;
    r.preferExact = o.preferExact ? 1 : 0;
    return _hitOpt;
  }

  List<QvpBox> _boxes(int n) {
    final o = _out<QvpBoxC>();
    n = n.clamp(0, _cap(ffi.sizeOf<QvpBoxC>()));
    return List.generate(n, (i) {
      final b = (o + i).ref;
      return QvpBox(id: b.id, line: b.line, x0: b.x0, y0: b.y0, x1: b.x1, y1: b.y1, color: b.color, radius: b.radius);
    }, growable: false);
  }

  // ── Page text & queries ──

  @override
  String wordForm(PageHandle handle, int wordIndex, int form) {
    if (b.wordForm(_page(handle), wordIndex, form, _str) == 0) return '';
    return _s();
  }

  @override
  int findWord(PageHandle handle, int surah, int ayah, int word) {
    final i = b.findWord(_page(handle), surah, ayah, word);
    return i < 0 ? -1 : i;
  }

  @override
  List<int> targetWords(PageHandle handle, QvpTarget target) =>
      _t(handle, target, (t) => _u32(b.targetWords(_page(handle), t, _out<ffi.Uint32>(), _cap(ffi.sizeOf<ffi.Uint32>()))));

  @override
  List<QvpSurah> surahs(PageHandle handle) {
    final n = b.surahCount(_page(handle));
    final o = pffi.calloc<QvpSurahC>();
    try {
      return List.generate(n, (i) {
        b.surahAt(_page(handle), i, o);
        final s = o.ref;
        return QvpSurah(
          number: s.number,
          ayahCount: s.ayahCount,
          hasBanner: s.hasBanner != 0,
          hasBasmalah: s.hasBasmalah != 0,
          place: name(QvpNames.place, s.place),
          bannerDecoration: s.bannerDecoration,
          arabic: str(s.arabic),
          latin: str(s.latin),
          english: str(s.english),
        );
      }, growable: false);
    } finally {
      pffi.calloc.free(o);
    }
  }

  @override
  List<QvpDivision> divisions(PageHandle handle) {
    final o = _out<QvpDivisionC>(), cap = _cap(ffi.sizeOf<QvpDivisionC>());
    final n = b.divisions(_page(handle), o, cap).clamp(0, cap);
    return List.generate(n, (i) {
      final d = (o + i).ref;
      return QvpDivision(division: name(QvpNames.division, d.division), line: d.line, number: d.number, surah: d.surah, ayah: d.ayah, ayahIndex: d.ayahIndex);
    }, growable: false);
  }

  @override
  List<QvpSurahHeader> surahHeaders(PageHandle handle, {required bool view}) {
    final o = _out<QvpSurahHeaderC>(), cap = _cap(ffi.sizeOf<QvpSurahHeaderC>());
    final n = (view ? b.surahHeadersView(_page(handle), o, cap) : b.surahHeaders(_page(handle), o, cap)).clamp(0, cap);
    return List.generate(n, (i) {
      final h = (o + i).ref;
      return QvpSurahHeader(decoration: h.decoration, surah: h.surah, line: h.line, x0: h.x0, y0: h.y0, x1: h.x1, y1: h.y1, titleX0: h.titleX0, titleY0: h.titleY0, titleX1: h.titleX1, titleY1: h.titleY1);
    }, growable: false);
  }

  @override
  List<QvpAyahMark> ayahMarks(PageHandle handle) {
    final o = _out<QvpAyahMarkC>(), cap = _cap(ffi.sizeOf<QvpAyahMarkC>());
    final n = b.ayahMarks(_page(handle), o, cap).clamp(0, cap);
    return List.generate(n, (i) {
      final m = (o + i).ref;
      return QvpAyahMark(decoration: m.decoration, surah: m.surah, ayah: m.ayah, line: m.line, cx: m.cx, cy: m.cy, r: m.r, ornamentPath: m.ornamentPath, numeralPath: m.numeralPath);
    }, growable: false);
  }

  @override
  List<QvpRosette> rosettes(PageHandle handle) {
    final o = _out<QvpRosetteC>(), cap = _cap(ffi.sizeOf<QvpRosetteC>());
    final n = b.rosettes(_page(handle), o, cap).clamp(0, cap);
    return List.generate(n, (i) {
      final r = (o + i).ref;
      return QvpRosette(decoration: r.decoration, surah: r.surah, ayah: r.ayah, juz: r.juz, hizb: r.hizb, nisf: r.nisf, rubuAlHizb: r.rubuAlHizb, rubuAlHizbInHizb: r.rubuAlHizbInHizb);
    }, growable: false);
  }

  @override
  List<QvpSajdah> sajdahs(PageHandle handle) {
    final o = _out<QvpSajdahC>(), cap = _cap(ffi.sizeOf<QvpSajdahC>());
    final n = b.sajdahs(_page(handle), o, cap).clamp(0, cap);
    return List.generate(n, (i) {
      final s = (o + i).ref;
      return QvpSajdah(decoration: s.decoration, surah: s.surah, ayah: s.ayah, signPath: s.signPath);
    }, growable: false);
  }

  @override
  List<(int, int)> ayahKeys(PageHandle handle) =>
      _u32(b.ayahKeys(_page(handle), _out<ffi.Uint32>(), _cap(ffi.sizeOf<ffi.Uint32>()))).map((k) => (k >> 16, k & 0xffff)).toList(growable: false);

  @override
  ({int count, bool isComplete}) ayahWordCount(PageHandle handle, int surah, int ayah) {
    final o = _out<ffi.Uint8>();
    final n = b.ayahWordCount(_page(handle), surah, ayah, o);
    return (count: n, isComplete: o.value != 0);
  }

  @override
  List<int>? reciteMap(PageHandle handle, int surah, int ayah, int nSegments) {
    final n = b.reciteMap(_page(handle), surah, ayah, nSegments, _out<ffi.Uint32>(), _cap(ffi.sizeOf<ffi.Uint32>()));
    return n < 0 ? null : _u32(n);
  }

  @override
  String wordLabel(PageHandle handle, int wordIndex) {
    b.wordLabel(_page(handle), wordIndex, _str);
    return _s();
  }

  @override
  String ayahLabel(PageHandle handle, int ayahIndex) {
    b.ayahLabel(_page(handle), ayahIndex, _str);
    return _s();
  }

  @override
  String text(PageHandle handle, QvpTarget target, int form, String wordSep, String lineSep) =>
      withString(wordSep, (wp, wn) => withString(lineSep, (lp, ln) => _t(handle, target, (t) {
            b.text(_page(handle), t, form, wp, wn, lp, ln, _str);
            return _s();
          })));

  @override
  List<QvpMatch> search(PageHandle handle, String query, {int form = 4, String mode = 'includes', bool normalize = true, bool looseMatch = true, int limit = 0}) {
    final o = _out<QvpMatchC>(), cap = _cap(ffi.sizeOf<QvpMatchC>());
    final n = withString(query, (p, len) => b.search(_page(handle), p, len, form, const {'includes': 0, 'exact': 1, 'prefix': 2}[mode] ?? 0, normalize ? 1 : 0, looseMatch ? 1 : 0, limit, o, cap)).clamp(0, cap);
    return List.generate(n, (i) {
      final m = (o + i).ref;
      return QvpMatch(word: m.word, index: m.index, isLooseMatch: m.isLooseMatch != 0);
    }, growable: false);
  }

  @override
  String citation(PageHandle handle, List<int> words) => withU32(words, (p, n) {
        b.citation(_page(handle), p, n, _str);
        return _s();
      });

  @override
  int attachWords(PageHandle handle, List<int> bytes) => withBytes(bytes, (p, len) => b.attachWords(_page(handle), p, len));

  @override
  bool hasForm(PageHandle handle, int form) => b.hasForm(_page(handle), form) != 0;

  // ── Hit testing ──

  @override
  QvpHit? hitTestExact(PageHandle handle, double x, double y) => _readHit(b.hitTestExact(_page(handle), x, y, _hit));

  @override
  QvpHit? hitTestExactView(PageHandle handle, double viewX, double viewY) => _readHit(b.hitTestExactView(_page(handle), viewX, viewY, _hit));

  @override
  QvpHit? hitTest(PageHandle handle, double x, double y, QvpHitOptions options) => _readHit(b.hitTest(_page(handle), x, y, _opt(options), _hit));

  @override
  QvpHit? hitTestView(PageHandle handle, double viewX, double viewY, QvpHitOptions options) => _readHit(b.hitTestView(_page(handle), viewX, viewY, _opt(options), _hit));

  @override
  List<QvpLineBand> lineBands(PageHandle handle) {
    final o = _out<QvpLineBandC>(), cap = _cap(ffi.sizeOf<QvpLineBandC>());
    final n = b.lineBands(_page(handle), o, cap).clamp(0, cap);
    return List.generate(n, (i) {
      final l = (o + i).ref;
      return QvpLineBand(line: l.line, lineNumber: l.lineNumber, y0: l.y0, y1: l.y1, mid: l.mid, inkY0: l.inkY0, inkY1: l.inkY1);
    }, growable: false);
  }

  @override
  List<QvpHitArea> hitAreas(PageHandle handle, double gapBias) {
    final o = _out<QvpHitAreaC>(), cap = _cap(ffi.sizeOf<QvpHitAreaC>());
    final n = b.hitAreas(_page(handle), gapBias, o, cap).clamp(0, cap);
    return List.generate(n, (i) {
      final h = (o + i).ref;
      return QvpHitArea(word: h.word, line: h.line, x0: h.x0, y0: h.y0, x1: h.x1, y1: h.y1, inkX0: h.inkX0, inkY0: h.inkY0, inkX1: h.inkX1, inkY1: h.inkY1);
    }, growable: false);
  }

  // ── Layout & zoom ──

  @override
  QvpLayout layout(PageHandle handle, QvpLayoutSpec spec) {
    _writeSpec(spec);
    b.layout(_page(handle), _spec, _layout);
    final o = _layout.ref;
    final n = o.nLines;
    final f = o.lines == ffi.nullptr ? Float32List(0) : o.lines.asTypedList(n * 3);
    final lineDy = Float32List(n);
    final slots = List<(double, double)>.generate(n, (i) {
      lineDy[i] = f[i * 3];
      return (f[i * 3 + 1], f[i * 3 + 2]);
    }, growable: false);
    return QvpLayout(scale: o.scale, offsetX: o.offsetX, offsetY: o.offsetY, contentW: o.contentW, contentH: o.contentH, lineSpacing: o.lineSpacing, lineDy: lineDy, slots: slots, fitScale: o.fitScale, fitX: o.fitX, fitY: o.fitY, reflowed: o.reflowed != 0, rows: o.nRows);
  }

  @override
  QvpZoomChange zoomPinch(PageHandle handle, QvpLayoutSpec spec, QvpZoom zoom, QvpView view, double factor, double focalX, double focalY) {
    _writeSpec(spec);
    final z = pffi.calloc<QvpZoomC>(), v = pffi.calloc<QvpViewC>(), out = pffi.calloc<QvpZoomChangeC>();
    try {
      _writeZoom(z, zoom);
      _writeView(v, view);
      b.zoomPinch(_page(handle), _spec, z, v, factor, focalX, focalY, out);
      return QvpZoomChange(zoom: _readZoom(out.ref.zoom), view: _readView(out.ref.view), relaid: out.ref.relaid != 0);
    } finally {
      pffi.calloc.free(z);
      pffi.calloc.free(v);
      pffi.calloc.free(out);
    }
  }

  @override
  QvpZoomChange zoomToStep(PageHandle handle, QvpLayoutSpec spec, QvpZoom zoom, int step, QvpView view) {
    _writeSpec(spec);
    final z = pffi.calloc<QvpZoomC>(), v = pffi.calloc<QvpViewC>(), out = pffi.calloc<QvpZoomChangeC>();
    try {
      _writeZoom(z, zoom);
      _writeView(v, view);
      b.zoomToStep(_page(handle), _spec, z, step, v, out);
      return QvpZoomChange(zoom: _readZoom(out.ref.zoom), view: _readView(out.ref.view), relaid: out.ref.relaid != 0);
    } finally {
      pffi.calloc.free(z);
      pffi.calloc.free(v);
      pffi.calloc.free(out);
    }
  }

  @override
  QvpZoom zoomMode(PageHandle handle, QvpLayoutSpec spec, QvpZoom zoom, QvpZoomMode mode) {
    _writeSpec(spec);
    final z = pffi.calloc<QvpZoomC>(), out = pffi.calloc<QvpZoomC>();
    try {
      _writeZoom(z, zoom);
      b.zoomMode(_page(handle), _spec, z, mode.index, out);
      return _readZoom(out.ref);
    } finally {
      pffi.calloc.free(z);
      pffi.calloc.free(out);
    }
  }

  @override
  QvpLayoutSpec zoomSpec(PageHandle handle, QvpLayoutSpec spec, QvpZoom zoom) {
    _writeSpec(spec);
    final z = pffi.calloc<QvpZoomC>(), out = pffi.calloc<QvpLayoutSpecC>();
    try {
      _writeZoom(z, zoom);
      b.zoomSpec(_page(handle), _spec, z, out);
      final o = out.ref;
      final knobs = spec.reflow ?? const QvpReflowSpec();
      final zoomed = o.reflowZoom > 1.0001;
      return QvpLayoutSpec(
        viewportW: spec.viewportW,
        viewportH: spec.viewportH,
        padTop: spec.padTop,
        padBottom: spec.padBottom,
        padLeft: spec.padLeft,
        padRight: spec.padRight,
        lineSpacing: spec.lineSpacing,
        fillHeight: spec.fillHeight,
        gridLines: spec.gridLines,
        cropLeft: spec.cropLeft,
        cropRight: spec.cropRight,
        maxAspectSlack: spec.maxAspectSlack,
        bannerZoom: spec.bannerZoom,
        surahFrames: spec.surahFrames,
        reflow: zoomed || spec.reflow != null
            ? QvpReflowSpec(
                zoom: zoomed ? o.reflowZoom : 0,
                fill: knobs.fill,
                breaks: knobs.breaks,
                gaps: knobs.gaps,
                wordGap: knobs.wordGap,
                maxStretch: knobs.maxStretch,
                relax: knobs.relax,
              )
            : null,
      );
    } finally {
      pffi.calloc.free(z);
      pffi.calloc.free(out);
    }
  }

  @override
  QvpZoom zoomCarried(PageHandle handle, QvpLayoutSpec spec, QvpZoom zoom) {
    _writeSpec(spec);
    final z = pffi.calloc<QvpZoomC>(), out = pffi.calloc<QvpZoomC>();
    try {
      _writeZoom(z, zoom);
      b.zoomCarried(_page(handle), _spec, z, out);
      return _readZoom(out.ref);
    } finally {
      pffi.calloc.free(z);
      pffi.calloc.free(out);
    }
  }

  @override
  double zoomAtStep(PageHandle handle, QvpLayoutSpec spec, int step) {
    _writeSpec(spec);
    return b.zoomAtStep(_page(handle), _spec, step);
  }

  @override
  Float32List zoomSteps(PageHandle handle, QvpLayoutSpec spec) {
    _writeSpec(spec);
    final o = _out<ffi.Float>(), cap = _cap(4);
    final n = b.zoomSteps(_page(handle), _spec, o, cap).clamp(0, cap);
    return Float32List.fromList(o.asTypedList(n));
  }

  @override
  double reflowMaxZoom(PageHandle handle, QvpLayoutSpec spec) {
    _writeSpec(spec);
    return b.reflowMaxZoom(_page(handle), _spec);
  }

  @override
  bool isZoomed(QvpZoom zoom, QvpView view, double fitScale) {
    final z = pffi.calloc<QvpZoomC>(), v = pffi.calloc<QvpViewC>();
    try {
      _writeZoom(z, zoom);
      _writeView(v, view);
      return b.zoomIsZoomed(z, v, fitScale) != 0;
    } finally {
      pffi.calloc.free(z);
      pffi.calloc.free(v);
    }
  }

  @override
  QvpSideways sidewaysDrag(PageHandle handle, QvpZoom zoom, QvpView view, double fitScale) {
    final z = pffi.calloc<QvpZoomC>(), v = pffi.calloc<QvpViewC>();
    try {
      _writeZoom(z, zoom);
      _writeView(v, view);
      return b.sidewaysDrag(_page(handle), z, v, fitScale) == 1 ? QvpSideways.turnPage : QvpSideways.pan;
    } finally {
      pffi.calloc.free(z);
      pffi.calloc.free(v);
    }
  }

  @override
  List<QvpDraw> layoutDrawList(PageHandle handle, {double bandTop = 0, double bandBottom = 0}) {
    final o = _out<ffi.Uint32>(), cap = _cap(8);
    final n = b.layoutDrawList(_page(handle), bandTop, bandBottom, o, cap).clamp(0, cap);
    final f = o.asTypedList(n * 2);
    return List.generate(n, (i) => QvpDraw(f[i * 2], f[i * 2 + 1]), growable: false);
  }

  @override
  List<QvpPlacement> layoutPlacements(PageHandle handle) {
    final o = _out<ffi.Float>(), cap = _cap(16);
    final n = b.layoutPlacements(_page(handle), o, cap).clamp(0, cap);
    final f = o.asTypedList(n * 4);
    return List.generate(n, (i) => QvpPlacement(f[i * 4], f[i * 4 + 1], f[i * 4 + 2], f[i * 4 + 3]), growable: false);
  }

  @override
  QvpLayout? readLayout(PageHandle handle) {
    if (b.layoutCurrent(_page(handle), _layout) == 0) return null;
    final o = _layout.ref;
    final n = o.nLines;
    final f = o.lines == ffi.nullptr ? Float32List(0) : o.lines.asTypedList(n * 3);
    final lineDy = Float32List(n);
    final slots = List<(double, double)>.generate(n, (i) {
      lineDy[i] = f[i * 3];
      return (f[i * 3 + 1], f[i * 3 + 2]);
    }, growable: false);
    return QvpLayout(scale: o.scale, offsetX: o.offsetX, offsetY: o.offsetY, contentW: o.contentW, contentH: o.contentH, lineSpacing: o.lineSpacing, lineDy: lineDy, slots: slots, fitScale: o.fitScale, fitX: o.fitX, fitY: o.fitY, reflowed: o.reflowed != 0, rows: o.nRows);
  }

  @override
  int? layoutWordRow(PageHandle handle, int word) {
    final r = b.layoutWordRow(_page(handle), word);
    return r == 0xFFFFFFFF ? null : r;
  }

  @override
  Uint32List layoutRowWords(PageHandle handle, int row) {
    final o = _out<ffi.Uint32>(), cap = _cap(4);
    final n = b.layoutRowWords(_page(handle), row, o, cap).clamp(0, cap);
    return Uint32List.fromList(o.asTypedList(n));
  }

  @override
  ({int lines, double lineSpacing}) pageGrid(PageHandle handle) {
    final g = pffi.calloc<QvpGridC>();
    try {
      b.pageGrid(_page(handle), g);
      return (lines: g.ref.lines, lineSpacing: g.ref.lineSpacing);
    } finally {
      pffi.calloc.free(g);
    }
  }

  @override
  double layoutWastedFraction(PageHandle handle, QvpLayoutSpec spec) {
    _writeSpec(spec);
    return b.layoutWastedFraction(_page(handle), _spec);
  }

  @override
  double layoutPrintedHeight(PageHandle handle, QvpLayoutSpec spec) {
    _writeSpec(spec);
    return b.layoutPrintedHeight(_page(handle), _spec);
  }

  @override
  double layoutLineSpacingToFill(PageHandle handle, QvpLayoutSpec spec, double max) {
    _writeSpec(spec);
    return b.layoutLineSpacingToFill(_page(handle), _spec, max);
  }

  @override
  ({double x0, double y0, double x1, double y1}) wordBoundsView(PageHandle handle, int wordIndex) {
    final o = _out<ffi.Float>();
    b.wordBoundsView(_page(handle), wordIndex, o);
    final f = o.asTypedList(4);
    return (x0: f[0], y0: f[1], x1: f[2], y1: f[3]);
  }

  // ── Styles ──

  @override
  int style(PageHandle handle, QvpSelector sel, int color, {int ms = 0, int layer = 0}) =>
      b.styleAdd(_page(handle), layer, _writeSel(sel), color, ms);

  @override
  int styleTarget(PageHandle handle, QvpTarget target, int color, {int ms = 0, int layer = 0}) =>
      _t(handle, target, (t) => b.styleAddTarget(_page(handle), layer, t, color, ms));

  @override
  int removeStyle(PageHandle handle, int styleHandle) => b.styleRemove(_page(handle), styleHandle);

  @override
  int recolorStyle(PageHandle handle, int styleHandle, int color, int ms) =>
      b.styleRecolor(_page(handle), styleHandle, color, ms);

  @override
  int hide(PageHandle handle, QvpSelector sel) => b.hide(_page(handle), _writeSel(sel));

  @override
  void clearStyles(PageHandle handle) => b.styleClear(_page(handle));

  @override
  void clearLayer(PageHandle handle, int layer) => b.styleClearLayer(_page(handle), layer);

  @override
  void setDefaultColor(PageHandle handle, int color) => b.styleDefaultColor(_page(handle), color);

  @override
  int theme(PageHandle handle, QvpTheme t) {
    final r = _theme.ref;
    int c(Object? v) => v == null ? 0 : rgba(v);
    r.ink = c(t.ink);
    r.diacritics = c(t.diacritics);
    r.dots = c(t.dots);
    r.waqf = c(t.waqf);
    r.sifr = c(t.sifr);
    r.ayahMark = c(t.ayahMark);
    r.numeral = c(t.numeral);
    r.headers = c(t.headers);
    r.transitionMs = t.ms;
    final pairs = <int>[];
    t.marks.forEach((m, col) => pairs..add(QvpMark.id(m))..add(rgba(col)));
    return pairs.isEmpty
        ? (() {
            r.marks = ffi.nullptr;
            r.nMarks = 0;
            return b.theme(_page(handle), _theme);
          })()
        : withU32(pairs, (p, n) {
            r.marks = p;
            r.nMarks = n ~/ 2;
            return b.theme(_page(handle), _theme);
          });
  }

  @override
  List<int> styleHandles(PageHandle handle) => _u32(b.styleHandles(_page(handle), _out<ffi.Uint32>(), _cap(ffi.sizeOf<ffi.Uint32>())));

  // ── Clock & display list ──

  @override
  bool tick(PageHandle handle, double nowMs) => b.tick(_page(handle), nowMs) != 0;

  @override
  Uint32List colors(PageHandle handle, int nPaths) => Uint32List.fromList(b.colors(_page(handle)).asTypedList(nPaths));

  @override
  List<QvpStyledPath> styledPaths(PageHandle handle) {
    final n = b.styledPaths(_page(handle), ffi.nullptr, 0);
    if (n == 0) return const [];
    final buf = pffi.malloc<ffi.Uint32>(n * 2);
    try {
      b.styledPaths(_page(handle), buf, n);
      final v = buf.asTypedList(n * 2);
      return List.generate(n, (i) => (path: v[i * 2], color: v[i * 2 + 1]), growable: false);
    } finally {
      pffi.malloc.free(buf);
    }
  }

  @override
  int colorOf(PageHandle handle, int path) => b.colorOf(_page(handle), path);

  // ── Highlights ──

  @override
  int highlight(PageHandle handle, QvpTarget target, QvpHighlightStyle style) =>
      _t(handle, target, (t) => b.highlight(_page(handle), t, _writeHl(style)));

  @override
  bool moveHighlight(PageHandle handle, int highlightHandle, QvpTarget target) =>
      _t(handle, target, (t) => b.moveHighlight(_page(handle), highlightHandle, t)) != 0;

  @override
  bool restyleHighlight(PageHandle handle, int highlightHandle, QvpHighlightStyle style) =>
      b.restyleHighlight(_page(handle), highlightHandle, _writeHl(style)) != 0;

  @override
  bool removeHighlight(PageHandle handle, int highlightHandle) =>
      b.removeHighlight(_page(handle), highlightHandle) != 0;

  @override
  void clearHighlights(PageHandle handle) => b.clearHighlights(_page(handle));

  @override
  List<int> highlightHandles(PageHandle handle) => _u32(b.highlightHandles(_page(handle), _out<ffi.Uint32>(), _cap(ffi.sizeOf<ffi.Uint32>())));

  @override
  List<int> highlightWords(PageHandle handle, int highlightHandle) =>
      _u32(b.highlightWords(_page(handle), highlightHandle, _out<ffi.Uint32>(), _cap(ffi.sizeOf<ffi.Uint32>())));

  @override
  List<QvpBox> highlightBoxesView(PageHandle handle) => _boxes(b.highlightBoxesView(_page(handle), _out<QvpBoxC>(), _cap(ffi.sizeOf<QvpBoxC>())));

  @override
  List<QvpBox> wordBands(PageHandle handle, List<int> ws, {required bool inkHeight, required double padX, required double padY}) =>
      withU32(ws, (p, n) => _boxes(b.wordBands(_page(handle), p, n, inkHeight ? 1 : 0, padX, padY, _out<QvpBoxC>(), _cap(ffi.sizeOf<QvpBoxC>()))));

  // ── Selection ──

  @override
  void select(PageHandle handle, int anchor, int focus) =>
      b.select(_page(handle), anchor < 0 ? qvpNone : anchor, focus < 0 ? qvpNone : focus);

  @override
  List<int> selection(PageHandle handle) => _u32(b.selection(_page(handle), _out<ffi.Uint32>(), _cap(ffi.sizeOf<ffi.Uint32>())));

  @override
  String selectionText(PageHandle handle, int form, bool includeCitation) {
    b.selectionText(_page(handle), form, includeCitation ? 1 : 0, _str);
    return _s();
  }

  // ── Masks & memorisation ──

  @override
  void mask(PageHandle handle, QvpTarget target, int mode) => _t(handle, target, (t) => b.mask(_page(handle), t, mode));

  @override
  void maskFrom(PageHandle handle, int wordIndex, int mode) => b.maskFrom(_page(handle), wordIndex, mode);

  @override
  void maskOptions(PageHandle handle, int blockColor, double padX, double padY, double radius, bool reverse) =>
      b.maskOptions(_page(handle), blockColor, padX, padY, radius, reverse ? 1 : 0);

  @override
  int unmaskNext(PageHandle handle, int n) => b.unmaskNext(_page(handle), n);

  @override
  int maskBack(PageHandle handle, int n) => b.maskBack(_page(handle), n);

  @override
  bool unmaskWord(PageHandle handle, int wordIndex) => b.unmaskWord(_page(handle), wordIndex) != 0;

  @override
  bool maskWord(PageHandle handle, int wordIndex) => b.maskWord(_page(handle), wordIndex) != 0;

  @override
  void unmaskAll(PageHandle handle) => b.unmaskAll(_page(handle));

  @override
  void maskAll(PageHandle handle) => b.maskAll(_page(handle));

  @override
  void unmask(PageHandle handle) => b.unmask(_page(handle));

  @override
  List<int> maskHidden(PageHandle handle) => _u32(b.maskHidden(_page(handle), _out<ffi.Uint32>(), _cap(ffi.sizeOf<ffi.Uint32>())));

  @override
  List<int> maskWords(PageHandle handle) => _u32(b.maskWords(_page(handle), _out<ffi.Uint32>(), _cap(ffi.sizeOf<ffi.Uint32>())));

  @override
  List<QvpBox> maskBoxesView(PageHandle handle) => _boxes(b.maskBoxesView(_page(handle), _out<QvpBoxC>(), _cap(ffi.sizeOf<QvpBoxC>())));

  // ── Reveal ──

  @override
  int revealStart(PageHandle handle, {required int lit, required bool byAyah, required int grey, required int ink, required bool ayahMarks, required int ms}) =>
      b.revealStart(_page(handle), lit, byAyah ? 1 : 0, grey, ink, ayahMarks ? 1 : 0, ms);

  @override
  bool revealGoto(PageHandle handle, int at) => b.revealGoto(_page(handle), at) != 0;

  @override
  int? revealPosition(PageHandle handle) {
    final v = b.revealPosition(_page(handle));
    return v == -2 ? null : v;
  }

  @override
  int revealStepCount(PageHandle handle) => b.revealStepCount(_page(handle));

  @override
  int revealStepOf(PageHandle handle, int wordIndex) => b.revealStepOf(_page(handle), wordIndex);

  @override
  void revealStop(PageHandle handle) => b.revealStop(_page(handle));

  // ── Dress ──

  @override
  bool dress(PageHandle page, OrnamentsHandle set, QvpDressSpec spec) {
    int index(Object? v, QvpOrnamentKind kind) {
      final o = v ?? spec.style;
      if (o == null) return qvpNone;
      if (o is int) return o;
      if (o is QvpOrnament) return o.index;
      return ornamentFind(set, kind.index, o as String);
    }

    final ayahMark = index(spec.ayahMark, QvpOrnamentKind.ayahMark);
    final surahHeader = index(spec.surahHeader, QvpOrnamentKind.surahHeader);
    final pageFrame = index(spec.pageFrame, QvpOrnamentKind.pageFrame);
    final triples = <int>[
      for (final (o, part, colour) in spec.colors) ...[o is QvpOrnament ? o.index : o as int, part, rgba(colour)],
    ];
    var lineArt = 0;
    for (final k in spec.lineArt) {
      lineArt |= 1 << k.index;
    }
    final c = pffi.calloc<QvpDressSpecC>();
    try {
      return withU32(triples, (cp, n) {
        final r = c.ref;
        r.ayahMark = ayahMark;
        r.surahHeader = surahHeader;
        r.pageFrame = pageFrame;
        r.gap = spec.gap;
        r.bandGap = spec.bandGap;
        r.ayahMarkScale = spec.ayahMarkScale;
        r.pageFrameScale = spec.pageFrameScale;
        r.lineArt = lineArt;
        r.colors = n == 0 ? ffi.nullptr : cp;
        r.nColors = n ~/ 3;
        return b.dress(_page(page), _ornaments(set), c) != 0;
      });
    } finally {
      pffi.calloc.free(c);
    }
  }

  @override
  void undress(PageHandle page) => b.undress(_page(page));

  @override
  QvpView dressClamp(PageHandle page, QvpView view, double viewportW, double viewportH) {
    final v = pffi.calloc<QvpViewC>(), out = pffi.calloc<QvpViewC>();
    try {
      _writeView(v, view);
      b.dressClamp(_page(page), v, viewportW, viewportH, out);
      return _readView(out.ref);
    } finally {
      pffi.calloc.free(v);
      pffi.calloc.free(out);
    }
  }

  @override
  QvpDressView dressView(PageHandle page, double scale, double viewportW) {
    final out = pffi.calloc<QvpViewC>(), size = pffi.calloc<ffi.Float>(2);
    try {
      b.dressView(_page(page), scale, viewportW, out, size);
      return QvpDressView(view: _readView(out.ref), width: size[0], height: size[1]);
    } finally {
      pffi.calloc.free(out);
      pffi.calloc.free(size);
    }
  }

  @override
  QvpDressInfo? dressInfo(PageHandle page) {
    final o = pffi.calloc<QvpDressInfoC>();
    try {
      if (b.dressInfo(_page(page), o) == 0) return null;
      final i = o.ref;
      int? id(int v) => v == qvpNone ? null : v;
      return QvpDressInfo(
        ayahMark: id(i.ayahMark),
        surahHeader: id(i.surahHeader),
        pageFrame: id(i.pageFrame),
        ayahMarks: i.nAyahMarks,
        surahHeaders: i.nSurahHeaders,
        frameRepeats: i.nFrameRepeats,
        frameStretched: i.frameStretched != 0,
        draws: i.nDraws,
        revision: i.revision,
        viewBox: List<double>.generate(4, (k) => i.viewBox[k], growable: false),
        overflow: List<double>.generate(4, (k) => i.overflow[k], growable: false),
      );
    } finally {
      pffi.calloc.free(o);
    }
  }

  @override
  List<QvpDressDraw> dressGeometry(PageHandle page) {
    final g = pffi.calloc<QvpDressGeometryC>();
    try {
      b.dressGeometry(_page(page), g);
      final r = g.ref;
      final n = r.nDraws;
      if (n == 0 || r.table == ffi.nullptr) return const [];
      final ops = Uint8List.fromList(r.ops.asTypedList(r.opsLen));
      final pts = Float32List.fromList(r.pts.asTypedList(r.ptsLen));
      final t = Uint32List.fromList(r.table.asTypedList(n * 9));
      final tf = t.buffer.asFloat32List();
      return List<QvpDressDraw>.generate(n, (i) {
        final flags = t[i * 9 + 5], placement = t[i * 9 + 8];
        final evenOdd = flags & 0x100 != 0;
        final path = Path()..fillType = evenOdd ? PathFillType.evenOdd : PathFillType.nonZero;
        var o = t[i * 9];
        final oe = o + t[i * 9 + 1];
        var k = t[i * 9 + 2];
        for (; o < oe; o++) {
          switch (ops[o]) {
            case QvpOp.moveTo:
              path.moveTo(pts[k], pts[k + 1]);
              k += 2;
            case QvpOp.lineTo:
              path.lineTo(pts[k], pts[k + 1]);
              k += 2;
            case QvpOp.quadTo:
              path.quadraticBezierTo(pts[k], pts[k + 1], pts[k + 2], pts[k + 3]);
              k += 4;
            case QvpOp.cubicTo:
              path.cubicTo(pts[k], pts[k + 1], pts[k + 2], pts[k + 3], pts[k + 4], pts[k + 5]);
              k += 6;
            case QvpOp.close:
              path.close();
          }
        }
        return QvpDressDraw(
          path: path,
          color: t[i * 9 + 4],
          kind: QvpOrnamentKind.values[(flags & 0xff).clamp(0, 2)],
          evenOdd: evenOdd,
          stroke: flags & 0x200 != 0,
          strokeWidth: tf[i * 9 + 6],
          part: t[i * 9 + 7],
          placement: placement == qvpNone ? null : placement,
        );
      }, growable: false);
    } finally {
      pffi.calloc.free(g);
    }
  }

  // ── Crop ──

  @override
  QvpCropBounds? cropBounds(PageHandle handle, QvpTarget target, {required double pad, required bool keepAyahMarks}) {
    final ok = _t(handle, target, (t) => b.cropBounds(_page(handle), t, pad, keepAyahMarks ? 1 : 0, _crop));
    if (ok == 0) return null;
    final c = _crop.ref;
    return QvpCropBounds(x0: c.x0, y0: c.y0, x1: c.x1, y1: c.y1, nWords: c.nWords, ayahMarkDecoration: c.ayahMarkDecoration);
  }

  @override
  String? cropSvg(PageHandle handle, QvpTarget target, {required double pad, required bool keepAyahMarks, int? background}) {
    final ok = _t(handle, target, (t) => b.cropSvg(_page(handle), t, pad, keepAyahMarks ? 1 : 0, background ?? 0, _str));
    return ok == 0 ? null : _s();
  }

  // ── Atlas ──

  @override
  (AtlasHandle, int pageCount) atlasLoad(Uint8List bytes) {
    final h = withBytes(bytes, (p, n) => b.atlasLoad(p, n));
    if (h == ffi.nullptr) throw const FormatException('qvp_atlas_load failed');
    return (NativeAtlasHandle(h), b.atlasPageCount(h));
  }

  @override
  void atlasFree(AtlasHandle handle) {
    final p = _atlas(handle);
    if (p != ffi.nullptr) {
      b.atlasFree(p);
      (handle as NativeAtlasHandle).pointer = ffi.nullptr;
    }
  }

  @override
  int? atlasPageOf(AtlasHandle handle, int surah, int ayah) {
    final p = b.atlasPageOf(_atlas(handle), surah, ayah);
    return p < 0 ? null : p;
  }

  @override
  ({(int, int) first, (int, int) last})? atlasPageRange(AtlasHandle handle, int page) {
    final o = _out<ffi.Uint16>();
    if (b.atlasPageRange(_atlas(handle), page, o) == 0) return null;
    final v = o.asTypedList(4);
    return (first: (v[0], v[1]), last: (v[2], v[3]));
  }

  QvpAtlasSurah _readSurah(QvpAtlasSurahC s) => QvpAtlasSurah(
        number: s.number,
        page: s.firstPage,
        ayahCount: s.ayahCount,
        place: name(QvpNames.place, s.place),
        arabic: str(s.arabic),
        latin: str(s.latin),
        english: str(s.english),
      );

  @override
  QvpAtlasSurah? atlasSurah(AtlasHandle handle, int n) {
    final o = pffi.calloc<QvpAtlasSurahC>();
    try {
      return b.atlasSurah(_atlas(handle), n, o) == 0 ? null : _readSurah(o.ref);
    } finally {
      pffi.calloc.free(o);
    }
  }

  @override
  List<QvpAtlasSurah> atlasSurahs(AtlasHandle handle) {
    final o = pffi.calloc<QvpAtlasSurahC>();
    try {
      return List.generate(b.atlasSurahs(_atlas(handle)), (i) {
        b.atlasSurahAt(_atlas(handle), i, o);
        return _readSurah(o.ref);
      }, growable: false);
    } finally {
      pffi.calloc.free(o);
    }
  }

  @override
  QvpAtlasRubuAlHizb? atlasDivision(AtlasHandle handle, int division, int n) {
    final o = pffi.calloc<QvpAtlasRubuAlHizbC>();
    try {
      if (b.atlasDivision(_atlas(handle), division, n, o) == 0) return null;
      final r = o.ref;
      return QvpAtlasRubuAlHizb(rubuAlHizb: r.rubuAlHizb, surah: r.surah, ayah: r.ayah, page: r.page);
    } finally {
      pffi.calloc.free(o);
    }
  }

  @override
  int? atlasDivisionOf(AtlasHandle handle, int division, int surah, int ayah) {
    final v = b.atlasDivisionOf(_atlas(handle), division, surah, ayah);
    return v < 0 ? null : v;
  }

  @override
  List<int>? atlasPagesOfJuz(AtlasHandle handle, int n) {
    final o = _out<ffi.Uint16>();
    if (b.atlasPagesOfJuz(_atlas(handle), n, o) == 0) return null;
    final v = o.asTypedList(2);
    return [v[0], v[1]];
  }

  @override
  List<int> atlasSearchSurahs(AtlasHandle handle, String text) {
    final o = _out<ffi.Uint16>(), cap = _cap(ffi.sizeOf<ffi.Uint16>());
    final n = withString(text, (p, len) => b.atlasSearchSurahs(_atlas(handle), p, len, o, cap)).clamp(0, cap);
    return List<int>.from(o.asTypedList(n));
  }

  @override
  String atlasJson(AtlasHandle handle) {
    b.atlasJson(_atlas(handle), _str);
    return _s();
  }

  // ── Passage ──

  @override
  (PassageHandle, List<QvpPassageText> ayahs, double lineSpacing) passageLoad(List<PageHandle> pages, int surah, int from, int to) {
    final arr = pffi.malloc<PtrPage>(pages.length);
    try {
      for (var i = 0; i < pages.length; i++) {
        arr[i] = _page(pages[i]);
      }
      final h = b.passageLoad(arr, pages.length, surah, from, to);
      if (h == ffi.nullptr) throw const FormatException('qvp_passage_load failed');
      final ayahs = List.generate(b.passageAyahCount(h), (i) {
        b.passageAyahText(h, i, _str);
        return QvpPassageText(surah: surah, ayah: from + i, text: _s());
      }, growable: false);
      return (NativePassageHandle(h), ayahs, b.passageLineSpacing(h));
    } finally {
      pffi.malloc.free(arr);
    }
  }

  @override
  (PassageHandle, List<QvpPassageText> ayahs, double lineSpacing) passageLoadBasmalah(List<PageHandle> pages, int surah) {
    final arr = pffi.malloc<PtrPage>(pages.length);
    try {
      for (var i = 0; i < pages.length; i++) {
        arr[i] = _page(pages[i]);
      }
      final h = b.passageLoadBasmalah(arr, pages.length, surah);
      if (h == ffi.nullptr) throw const FormatException('qvp_passage_load_basmalah failed');
      return (NativePassageHandle(h), const <QvpPassageText>[], b.passageLineSpacing(h));
    } finally {
      pffi.malloc.free(arr);
    }
  }

  @override
  void passageFree(PassageHandle handle) {
    final p = _passage(handle);
    if (p != ffi.nullptr) {
      b.passageFree(p);
      (handle as NativePassageHandle).pointer = ffi.nullptr;
    }
  }

  @override
  QvpPassageLayout? passageLayout(PassageHandle handle, QvpPassageSpec spec) {
    if (spec.maxRows < 0) return null;
    final s = pffi.calloc<QvpPassageSpecC>(), o = pffi.calloc<QvpPassageLayoutC>();
    try {
      final r = s.ref;
      r.width = spec.width;
      r.scale = spec.scale;
      r.lineSpacing = spec.lineSpacing;
      r.padding = spec.padding;
      r.align = spec.align.index;
      r.keepAyahMark = spec.keepAyahMark ? 1 : 0;
      r.maxRows = spec.maxRows;
      r.ellipsisWidth = spec.ellipsisWidth;
      r.maxStretch = spec.maxStretch;
      if (b.passageLayout(_passage(handle), s, o) == 0) return null;
      final l = o.ref;

      final p = _passage(handle);
      final rBuf = _out<QvpPassageRowC>(), capR = _cap(ffi.sizeOf<QvpPassageRowC>());
      final nR = b.passageRows(p, rBuf, capR).clamp(0, capR);
      final rows = List.generate(nR, (i) {
        final rw = (rBuf + i).ref;
        return QvpPassageRow(x0: rw.x0, y0: rw.y0, x1: rw.x1, y1: rw.y1, baseline: rw.baseline);
      }, growable: false);

      final wBuf = _out<QvpPassageWordC>(), capW = _cap(ffi.sizeOf<QvpPassageWordC>());
      final nW = b.passageWords(p, wBuf, capW).clamp(0, capW);
      final words = List.generate(nW, (i) {
        final w = (wBuf + i).ref;
        return QvpPassageWord(
          surah: w.surah,
          ayah: w.ayah,
          word: w.word,
          page: w.page,
          row: w.row,
          x0: w.x0,
          y0: w.y0,
          x1: w.x1,
          y1: w.y1,
          wordX0: w.wordX0,
          wordY0: w.wordY0,
          wordX1: w.wordX1,
          wordY1: w.wordY1,
        );
      }, growable: false);

      final aBuf = _out<QvpPassageAyahC>(), capA = _cap(ffi.sizeOf<QvpPassageAyahC>());
      final nA = b.passageAyahs(p, aBuf, capA).clamp(0, capA);
      final ayahs = List.generate(nA, (i) {
        final a = (aBuf + i).ref;
        return QvpPassageAyah(surah: a.surah, ayah: a.ayah, x0: a.x0, y0: a.y0, x1: a.x1, y1: a.y1);
      }, growable: false);

      final nDraws = l.nDraws;
      final dBuf = pffi.malloc<ffi.Uint32>(nDraws < 1 ? 3 : nDraws * 3);
      List<QvpPassageDraw> draws;
      try {
        final nD = b.passageDrawList(p, dBuf, nDraws).clamp(0, nDraws);
        final dv = dBuf.asTypedList(nD * 3);
        draws = List.generate(nD, (i) => QvpPassageDraw(dv[i * 3], dv[i * 3 + 1], dv[i * 3 + 2]), growable: false);
      } finally {
        pffi.malloc.free(dBuf);
      }

      final fBuf = _out<ffi.Float>(), capP = _cap(16);
      final totalP = b.passagePlacements(p, fBuf, capP);
      List<QvpPlacement> placements;
      if (totalP <= capP) {
        final pf = fBuf.asTypedList(totalP * 4);
        placements = List.generate(totalP, (i) => QvpPlacement(pf[i * 4], pf[i * 4 + 1], pf[i * 4 + 2], pf[i * 4 + 3]), growable: false);
      } else {
        final bufP = pffi.malloc<ffi.Float>(totalP * 4);
        try {
          final n = b.passagePlacements(p, bufP, totalP).clamp(0, totalP);
          final pf = bufP.asTypedList(n * 4);
          placements = List.generate(n, (i) => QvpPlacement(pf[i * 4], pf[i * 4 + 1], pf[i * 4 + 2], pf[i * 4 + 3]), growable: false);
        } finally {
          pffi.malloc.free(bufP);
        }
      }

      return QvpPassageLayout(
        width: l.width,
        height: l.height,
        scale: l.scale,
        lineSpacing: l.lineSpacing,
        rows: rows,
        words: words,
        ayahs: ayahs,
        draws: draws,
        placements: placements,
        isTruncated: l.isTruncated != 0,
        ellipsis: l.isTruncated != 0 ? Rect.fromLTRB(l.ellipsisX0, l.ellipsisY0, l.ellipsisX1, l.ellipsisY1) : null,
      );
    } finally {
      pffi.calloc.free(s);
      pffi.calloc.free(o);
    }
  }


  // ── Ornaments ──

  @override
  (OrnamentsHandle, List<QvpOrnament>) ornamentsLoad(Uint8List bytes) {
    final h = withBytes(bytes, (p, n) => b.ornamentsLoad(p, n));
    if (h == ffi.nullptr) throw const FormatException('qvp_ornaments_load failed');
    final count = b.ornamentCount(h);
    final o = pffi.calloc<QvpOrnamentC>();
    final pr = pffi.calloc<QvpOrnamentPartC>();
    try {
      final list = List<QvpOrnament>.generate(count, (i) {
        if (b.ornamentInfo(h, i, o) == 0) throw StateError('qvp_ornament_info($i) failed');
        final r = o.ref;
        final parts = <QvpOrnamentPart>[];
        for (var k = 0; k < r.nParts; k++) {
          if (b.ornamentPart(h, i, k, pr) == 0) continue;
          parts.add(QvpOrnamentPart(index: k, color: pr.ref.color, stroke: pr.ref.stroke != 0, name: str(pr.ref.name)));
        }
        return QvpOrnament(
          index: i,
          kind: QvpOrnamentKind.values[r.kind.clamp(0, 2)],
          lineage: QvpLineage.values[r.lineage.clamp(0, 1)],
          style: str(r.style),
          riwayah: str(r.riwayah),
          hasSlices: r.hasSlices != 0,
          licence: QvpOrnamentLicence(id: str(r.licenseId), status: str(r.licenseStatus), redistributable: r.redistributable != 0, attribution: str(r.attribution)),
          parts: List.unmodifiable(parts),
        );
      }, growable: false);
      return (NativeOrnamentsHandle(h), list);
    } finally {
      pffi.calloc.free(o);
      pffi.calloc.free(pr);
    }
  }

  @override
  void ornamentsFree(OrnamentsHandle handle) {
    final p = _ornaments(handle);
    if (p != ffi.nullptr) {
      b.ornamentsFree(p);
      (handle as NativeOrnamentsHandle).pointer = ffi.nullptr;
    }
  }

  @override
  int ornamentFind(OrnamentsHandle handle, int kind, String style) =>
      withString(style, (p, n) => b.ornamentFind(_ornaments(handle), kind, p, n));
}
