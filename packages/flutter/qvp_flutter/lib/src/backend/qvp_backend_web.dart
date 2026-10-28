// dart:js_interop implementation of QvpBackend for Flutter Web.
import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import '../types.dart';
import 'qvp_backend.dart';

QvpWebBackend? _defaultWebBackend;

/// Creates or returns the Web backend over dart:js_interop and WebAssembly.
QvpBackend createDefaultBackend({String? path, dynamic library}) {
  if (_defaultWebBackend != null) return _defaultWebBackend!;
  throw StateError(
    'On Flutter Web, call `await QvpEngine.initWeb()` before accessing QvpEngine.',
  );
}

/// Initializes the Web backend on Flutter Web.
Future<QvpBackend> initWebBackend({List<int>? wasmBytes, String? wasmAssetPath, String? wasmUrl}) =>
    QvpWebBackend.init(wasmBytes: wasmBytes, wasmAssetPath: wasmAssetPath, wasmUrl: wasmUrl);

final class WebPageHandle implements PageHandle {
  WebPageHandle(this.js);
  JSObject js;
}

final class WebAtlasHandle implements AtlasHandle {
  WebAtlasHandle(this.js);
  JSObject js;
}

final class WebPassageHandle implements PassageHandle {
  WebPassageHandle(this.js);
  JSObject js;
}

final class WebOrnamentsHandle implements OrnamentsHandle {
  WebOrnamentsHandle(this.js);
  JSObject js;
}

/// Web backend implementation of [QvpBackend] using `dart:js_interop`.
class QvpWebBackend implements QvpBackend {
  QvpWebBackend(this.js);

  final JSObject js;

  static Future<QvpWebBackend> init({
    List<int>? wasmBytes,
    String? wasmAssetPath,
    String? wasmUrl,
  }) async {
    await _ensureJsLoaded();

    Uint8List bytes;
    if (wasmBytes != null) {
      bytes = Uint8List.fromList(wasmBytes);
    } else if (wasmAssetPath != null) {
      final data = await rootBundle.load(wasmAssetPath);
      bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } else {
      try {
        final data = await rootBundle.load('packages/qvp_flutter/assets/wasm/qvp_ffi.wasm');
        bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      } catch (_) {
        final url = wasmUrl ?? 'qvp_ffi.wasm';
        bytes = await _fetchBytes(url);
      }
    }

    final jsEngineClass = globalContext['QvpEngine'] as JSObject?;
    if (jsEngineClass == null) {
      throw StateError('QvpEngine not defined in JavaScript context');
    }

    final promise = jsEngineClass.callMethod<JSPromise>('init'.toJS, bytes.toJS);
    final jsInstance = (await promise.toDart) as JSObject;

    final backend = QvpWebBackend(jsInstance);
    _defaultWebBackend ??= backend;
    return backend;
  }

  static Future<void> _ensureJsLoaded() async {
    if (globalContext.has('QvpEngine')) return;
    try {
      final jsText = await rootBundle.loadString('packages/qvp_flutter/assets/js/qvp.js');
      _eval(jsText);
    } catch (_) {
      try {
        final jsText = await _fetchString('assets/packages/qvp_flutter/assets/js/qvp.js');
        _eval(jsText);
      } catch (_) {
        final jsText = await _fetchString('qvp.js');
        _eval(jsText);
      }
    }
  }

  static void _eval(String code) {
    globalContext.callMethod('eval'.toJS, code.toJS);
  }

  static Future<Uint8List> _fetchBytes(String url) async {
    final responsePromise = globalContext.callMethod<JSPromise>('fetch'.toJS, url.toJS);
    final response = (await responsePromise.toDart) as JSObject;
    final bufferPromise = response.callMethod<JSPromise>('arrayBuffer'.toJS);
    final arrayBuffer = (await bufferPromise.toDart) as JSArrayBuffer;
    return JSUint8Array(arrayBuffer).toDart;
  }

  static Future<String> _fetchString(String url) async {
    final responsePromise = globalContext.callMethod<JSPromise>('fetch'.toJS, url.toJS);
    final response = (await responsePromise.toDart) as JSObject;
    final textPromise = response.callMethod<JSPromise>('text'.toJS);
    final text = (await textPromise.toDart) as JSString;
    return text.toDart;
  }

  JSObject _page(PageHandle h) => (h as WebPageHandle).js;
  JSObject _atlas(AtlasHandle h) => (h as WebAtlasHandle).js;
  JSObject _passage(PassageHandle h) => (h as WebPassageHandle).js;
  JSObject _ornaments(OrnamentsHandle h) => (h as WebOrnamentsHandle).js;

  JSObject _targetToJs(QvpTarget t) {
    final res = JSObject()
      ..['target'] = t.target.toJS
      ..['a'] = t.a.toJS
      ..['b'] = t.b.toJS
      ..['c'] = t.c.toJS;
    if (t.words != null) {
      res['words'] = Uint32List.fromList(t.words!).toJS;
    }
    return res;
  }

  JSObject _selToJs(QvpSelector s) => JSObject()
    ..['selector'] = s.selector.toJS
    ..['a'] = s.a.toJS
    ..['b'] = s.b.toJS
    ..['c'] = s.c.toJS;

  JSObject _hlToJs(QvpHighlightStyle st) => JSObject()
    ..['mode'] = (const {'ink': 0, 'band': 1, 'both': 2}[st.mode] ?? 1).toJS
    ..['height'] = (st.height == 'ink' ? 1 : 0).toJS
    ..['ink'] = rgba(st.ink).toJS
    ..['band'] = rgba(st.band).toJS
    ..['padX'] = st.padX.toJS
    ..['padY'] = st.padY.toJS
    ..['radius'] = st.radius.toJS
    ..['seam'] = st.seam.toJS
    ..['transitionMs'] = st.ms.toJS
    ..['layer'] = st.layer.toJS;

  JSObject _specToJs(QvpLayoutSpec spec) {
    final s = JSObject()
      ..['viewportW'] = spec.viewportW.toJS
      ..['viewportH'] = spec.viewportH.toJS
      ..['padTop'] = spec.padTop.toJS
      ..['padBottom'] = spec.padBottom.toJS
      ..['padLeft'] = spec.padLeft.toJS
      ..['padRight'] = spec.padRight.toJS
      ..['lineSpacing'] = spec.lineSpacing.toJS
      ..['fillHeight'] = spec.fillHeight.toJS
      ..['gridLines'] = spec.gridLines.toJS
      ..['cropLeft'] = spec.cropLeft.toJS
      ..['cropRight'] = spec.cropRight.toJS
      ..['maxAspectSlack'] = spec.maxAspectSlack.toJS
      ..['bannerZoom'] = spec.bannerZoom.toJS
      ..['surahFrames'] = spec.surahFrames.toJS;
    final r = spec.reflow;
    if (r != null) {
      s['reflow'] = JSObject()
        ..['zoom'] = r.zoom.toJS
        ..['fill'] = r.fill.toJS
        ..['breaks'] = r.breaks.toJS
        ..['gaps'] = r.gaps.toJS
        ..['wordGap'] = r.wordGap.toJS
        ..['maxStretch'] = r.maxStretch.toJS
        ..['relax'] = r.relax.toJS;
    }
    return s;
  }

  QvpHit? _readHit(JSObject? res) {
    if (res == null) return null;
    final w = (res['word'] as JSNumber).toDartInt;
    return QvpHit(
      word: w == qvpNone ? -1 : w,
      path: (res['path'] as JSNumber).toDartInt,
      decoration: (res['decoration'] as JSNumber).toDartInt,
      line: (res['line'] as JSNumber).toDartInt,
      distance: (res['distance'] as JSNumber).toDartDouble,
      isExact: (res['isExact'] as JSBoolean).toDart,
    );
  }

  // ── Engine Info ──

  @override
  String get version => (js['version'] as JSString).toDart;

  @override
  int get formatVersion => (js['formatVersion'] as JSNumber).toDartInt;

  @override
  String get engineName => 'qvp';

  @override
  int nameCount(int table) =>
      (js.callMethod<JSNumber>('nameCount'.toJS, table.toJS)).toDartInt;

  @override
  String name(int table, int id) =>
      (js.callMethod<JSString>('name'.toJS, table.toJS, id.toJS)).toDart;

  @override
  int nameId(int table, String s) =>
      (js.callMethod<JSNumber>('nameId'.toJS, table.toJS, s.toJS)).toDartInt;

  @override
  String markName(int m) =>
      (js.callMethod<JSString>('markName'.toJS, m.toJS)).toDart;

  @override
  String familyName(int f) =>
      (js.callMethod<JSString>('familyName'.toJS, f.toJS)).toDart;

  @override
  String kindName(int k) =>
      (js.callMethod<JSString>('kindName'.toJS, k.toJS)).toDart;

  @override
  String categoryName(int c) =>
      (js.callMethod<JSString>('categoryName'.toJS, c.toJS)).toDart;

  @override
  int markCategory(int m) =>
      (js.callMethod<JSNumber>('markCategory'.toJS, m.toJS)).toDartInt;

  @override
  int markFromName(String s) =>
      (js.callMethod<JSNumber>('markFromName'.toJS, s.toJS)).toDartInt;

  @override
  String arabic(int op, String s) =>
      (js.callMethod<JSString>('arabic'.toJS, op.toJS, s.toJS)).toDart;

  @override
  QvpView viewZoomAbout(QvpView view, double focalX, double focalY, double factor, {double min = 0, double max = 0}) {
    final v = JSObject()
      ..['scale'] = view.scale.toJS
      ..['offsetX'] = view.offsetX.toJS
      ..['offsetY'] = view.offsetY.toJS;
    final opt = JSObject()
      ..['min'] = min.toJS
      ..['max'] = max.toJS;
    final res = js.callMethodVarArgs<JSObject>('viewZoomAbout'.toJS, [v, focalX.toJS, focalY.toJS, factor.toJS, opt]);
    return QvpView(
      scale: (res['scale'] as JSNumber).toDartDouble,
      offsetX: (res['offsetX'] as JSNumber).toDartDouble,
      offsetY: (res['offsetY'] as JSNumber).toDartDouble,
    );
  }

  @override
  void dispose() {}

  // ── Page Lifecycle ──

  @override
  (PageHandle, QvpPageData) pageLoad(Uint8List bytes) {
    final jsPage = js.callMethod<JSObject>('loadPage'.toJS, bytes.toJS);
    final data = QvpPageData(
      width: (jsPage['width'] as JSNumber).toDartDouble,
      height: (jsPage['height'] as JSNumber).toDartDouble,
      lineSpacing: (jsPage['lineSpacing'] as JSNumber).toDartDouble,
      page: (jsPage['page'] as JSNumber).toDartInt,
      nLines: (jsPage['nLines'] as JSNumber).toDartInt,
      nAyahs: (jsPage['nAyahs'] as JSNumber).toDartInt,
      nWords: (jsPage['nWords'] as JSNumber).toDartInt,
      nPaths: (jsPage['nPaths'] as JSNumber).toDartInt,
      nDecorations: (jsPage['nDecorations'] as JSNumber).toDartInt,
      ops: (jsPage['ops'] as JSUint8Array).toDart,
      pts: (jsPage['pts'] as JSFloat32Array).toDart,
      table: (jsPage['table'] as JSUint32Array).toDart,
      words: _readWords(jsPage),
      ayahs: _readAyahs(jsPage),
      lines: _readLines(jsPage),
      decorations: _readDecorations(jsPage),
    );
    return (WebPageHandle(jsPage), data);
  }

  @override
  void pageFree(PageHandle handle) {
    _page(handle).callMethod('free'.toJS);
  }

  List<QvpWordInfo> _readWords(JSObject p) {
    final arr = p['words'] as JSArray;
    return List<QvpWordInfo>.generate(arr.length, (i) {
      final w = arr[i] as JSObject;
      return QvpWordInfo(
        index: (w['index'] as JSNumber).toDartInt,
        surah: (w['surah'] as JSNumber).toDartInt,
        ayah: (w['ayah'] as JSNumber).toDartInt,
        word: (w['word'] as JSNumber).toDartInt,
        line: (w['line'] as JSNumber).toDartInt,
        ayahIndex: (w['ayahIndex'] as JSNumber).toDartInt,
        lineIndex: (w['lineIndex'] as JSNumber).toDartInt,
        x0: (w['x0'] as JSNumber).toDartDouble,
        y0: (w['y0'] as JSNumber).toDartDouble,
        x1: (w['x1'] as JSNumber).toDartDouble,
        y1: (w['y1'] as JSNumber).toDartDouble,
        text: (w['text'] as JSString).toDart,
        firstPath: (w['firstPath'] as JSNumber).toDartInt,
        nPaths: (w['nPaths'] as JSNumber).toDartInt,
      );
    }, growable: false);
  }

  List<QvpAyahInfo> _readAyahs(JSObject p) {
    final arr = p['ayahs'] as JSArray;
    return List<QvpAyahInfo>.generate(arr.length, (i) {
      final a = arr[i] as JSObject;
      return QvpAyahInfo(
        index: (a['index'] as JSNumber).toDartInt,
        surah: (a['surah'] as JSNumber).toDartInt,
        ayah: (a['ayah'] as JSNumber).toDartInt,
        fragment: (a['fragment'] as JSNumber).toDartInt,
        fragments: (a['fragments'] as JSNumber).toDartInt,
        flags: (a['flags'] as JSNumber).toDartInt,
        rubuAlHizb: (a['rubuAlHizb'] as JSNumber).toDartInt,
        firstWord: (a['firstWord'] as JSNumber).toDartInt,
        nWords: (a['nWords'] as JSNumber).toDartInt,
        ayahMarkDecoration: (a['ayahMarkDecoration'] as JSNumber).toDartInt,
        x0: (a['x0'] as JSNumber).toDartDouble,
        y0: (a['y0'] as JSNumber).toDartDouble,
        x1: (a['x1'] as JSNumber).toDartDouble,
        y1: (a['y1'] as JSNumber).toDartDouble,
      );
    }, growable: false);
  }

  List<QvpLineInfo> _readLines(JSObject p) {
    final arr = p['lines'] as JSArray;
    return List<QvpLineInfo>.generate(arr.length, (i) {
      final l = arr[i] as JSObject;
      return QvpLineInfo(
        index: (l['index'] as JSNumber).toDartInt,
        lineNumber: (l['lineNumber'] as JSNumber).toDartInt,
        isHeader: (l['isHeader'] as JSBoolean).toDart,
        firstWord: (l['firstWord'] as JSNumber).toDartInt,
        nWords: (l['nWords'] as JSNumber).toDartInt,
        x0: (l['x0'] as JSNumber).toDartDouble,
        y0: (l['y0'] as JSNumber).toDartDouble,
        x1: (l['x1'] as JSNumber).toDartDouble,
        y1: (l['y1'] as JSNumber).toDartDouble,
        bandY0: (l['bandY0'] as JSNumber).toDartDouble,
        bandY1: (l['bandY1'] as JSNumber).toDartDouble,
        centre: (l['centre'] as JSNumber).toDartDouble,
      );
    }, growable: false);
  }

  List<QvpDecorationInfo> _readDecorations(JSObject p) {
    final arr = p['decorations'] as JSArray;
    return List<QvpDecorationInfo>.generate(arr.length, (i) {
      final d = arr[i] as JSObject;
      return QvpDecorationInfo(
        index: (d['index'] as JSNumber).toDartInt,
        decoration: (d['decoration'] as JSNumber).toDartInt,
        surah: (d['surah'] as JSNumber).toDartInt,
        ayah: (d['ayah'] as JSNumber).toDartInt,
        line: (d['line'] as JSNumber).toDartInt,
        x0: (d['x0'] as JSNumber).toDartDouble,
        y0: (d['y0'] as JSNumber).toDartDouble,
        x1: (d['x1'] as JSNumber).toDartDouble,
        y1: (d['y1'] as JSNumber).toDartDouble,
        text: (d['text'] as JSString).toDart,
        firstPath: (d['firstPath'] as JSNumber).toDartInt,
        nPaths: (d['nPaths'] as JSNumber).toDartInt,
      );
    }, growable: false);
  }

  // ── Page text & query ──

  @override
  String wordForm(PageHandle handle, int wordIndex, int form) =>
      (_page(handle).callMethod<JSString>('wordForm'.toJS, wordIndex.toJS, form.toJS)).toDart;

  @override
  int findWord(PageHandle handle, int surah, int ayah, int word) =>
      (_page(handle).callMethod<JSNumber>('findWord'.toJS, surah.toJS, ayah.toJS, word.toJS)).toDartInt;

  @override
  List<int> targetWords(PageHandle handle, QvpTarget target) {
    final res = _page(handle).callMethod<JSUint32Array>('targetWords'.toJS, _targetToJs(target));
    return res.toDart.toList();
  }

  @override
  List<QvpSurah> surahs(PageHandle handle) {
    final arr = _page(handle).callMethod<JSArray>('surahs'.toJS);
    return List<QvpSurah>.generate(arr.length, (i) {
      final s = arr[i] as JSObject;
      return QvpSurah(
        number: (s['number'] as JSNumber).toDartInt,
        ayahCount: (s['ayahCount'] as JSNumber).toDartInt,
        hasBanner: (s['hasBanner'] as JSBoolean).toDart,
        hasBasmalah: (s['hasBasmalah'] as JSBoolean).toDart,
        place: (s['place'] as JSString).toDart,
        bannerDecoration: (s['bannerDecoration'] as JSNumber).toDartInt,
        arabic: (s['arabic'] as JSString).toDart,
        latin: (s['latin'] as JSString).toDart,
        english: (s['english'] as JSString).toDart,
      );
    }, growable: false);
  }

  @override
  List<QvpDivision> divisions(PageHandle handle) {
    final arr = _page(handle).callMethod<JSArray>('divisions'.toJS);
    return List<QvpDivision>.generate(arr.length, (i) {
      final d = arr[i] as JSObject;
      return QvpDivision(
        division: (d['division'] as JSString).toDart,
        line: (d['line'] as JSNumber).toDartInt,
        number: (d['number'] as JSNumber).toDartInt,
        surah: (d['surah'] as JSNumber).toDartInt,
        ayah: (d['ayah'] as JSNumber).toDartInt,
        ayahIndex: (d['ayahIndex'] as JSNumber).toDartInt,
      );
    }, growable: false);
  }

  @override
  List<QvpSurahHeader> surahHeaders(PageHandle handle, {required bool view}) {
    final arr = _page(handle).callMethod<JSArray>('surahHeaders'.toJS, view.toJS);
    return List<QvpSurahHeader>.generate(arr.length, (i) {
      final h = arr[i] as JSObject;
      return QvpSurahHeader(
        decoration: (h['decoration'] as JSNumber).toDartInt,
        surah: (h['surah'] as JSNumber).toDartInt,
        line: (h['line'] as JSNumber).toDartInt,
        x0: (h['x0'] as JSNumber).toDartDouble,
        y0: (h['y0'] as JSNumber).toDartDouble,
        x1: (h['x1'] as JSNumber).toDartDouble,
        y1: (h['y1'] as JSNumber).toDartDouble,
        titleX0: (h['titleX0'] as JSNumber).toDartDouble,
        titleY0: (h['titleY0'] as JSNumber).toDartDouble,
        titleX1: (h['titleX1'] as JSNumber).toDartDouble,
        titleY1: (h['titleY1'] as JSNumber).toDartDouble,
      );
    }, growable: false);
  }

  @override
  List<QvpAyahMark> ayahMarks(PageHandle handle) {
    final arr = _page(handle).callMethod<JSArray>('ayahMarks'.toJS);
    return List<QvpAyahMark>.generate(arr.length, (i) {
      final m = arr[i] as JSObject;
      return QvpAyahMark(
        decoration: (m['decoration'] as JSNumber).toDartInt,
        surah: (m['surah'] as JSNumber).toDartInt,
        ayah: (m['ayah'] as JSNumber).toDartInt,
        line: (m['line'] as JSNumber).toDartInt,
        cx: (m['cx'] as JSNumber).toDartDouble,
        cy: (m['cy'] as JSNumber).toDartDouble,
        r: (m['r'] as JSNumber).toDartDouble,
        ornamentPath: (m['ornamentPath'] as JSNumber).toDartInt,
        numeralPath: (m['numeralPath'] as JSNumber).toDartInt,
      );
    }, growable: false);
  }

  @override
  List<QvpRosette> rosettes(PageHandle handle) {
    final arr = _page(handle).callMethod<JSArray>('rosettes'.toJS);
    return List<QvpRosette>.generate(arr.length, (i) {
      final r = arr[i] as JSObject;
      return QvpRosette(
        decoration: (r['decoration'] as JSNumber).toDartInt,
        surah: (r['surah'] as JSNumber).toDartInt,
        ayah: (r['ayah'] as JSNumber).toDartInt,
        juz: (r['juz'] as JSNumber).toDartInt,
        hizb: (r['hizb'] as JSNumber).toDartInt,
        nisf: (r['nisf'] as JSNumber).toDartInt,
        rubuAlHizb: (r['rubuAlHizb'] as JSNumber).toDartInt,
        rubuAlHizbInHizb: (r['rubuAlHizbInHizb'] as JSNumber).toDartInt,
      );
    }, growable: false);
  }

  @override
  List<QvpSajdah> sajdahs(PageHandle handle) {
    final arr = _page(handle).callMethod<JSArray>('sajdahs'.toJS);
    return List<QvpSajdah>.generate(arr.length, (i) {
      final s = arr[i] as JSObject;
      return QvpSajdah(
        decoration: (s['decoration'] as JSNumber).toDartInt,
        surah: (s['surah'] as JSNumber).toDartInt,
        ayah: (s['ayah'] as JSNumber).toDartInt,
        signPath: (s['signPath'] as JSNumber).toDartInt,
      );
    }, growable: false);
  }

  @override
  List<(int, int)> ayahKeys(PageHandle handle) {
    final arr = _page(handle).callMethod<JSArray>('ayahKeys'.toJS);
    return List<(int, int)>.generate(arr.length, (i) {
      final k = (arr[i] as JSNumber).toDartInt;
      return (k >> 16, k & 0xffff);
    }, growable: false);
  }

  @override
  ({int count, bool isComplete}) ayahWordCount(PageHandle handle, int surah, int ayah) {
    final res = (_page(handle).callMethod<JSNumber>('ayahWordCount'.toJS, surah.toJS, ayah.toJS)).toDartInt;
    return (count: res, isComplete: true);
  }

  @override
  List<int>? reciteMap(PageHandle handle, int surah, int ayah, int nSegments) {
    final res = _page(handle).callMethod<JSUint32Array>('reciteMap'.toJS, surah.toJS, ayah.toJS, nSegments.toJS);
    return res.toDart.toList();
  }

  @override
  String wordLabel(PageHandle handle, int wordIndex) =>
      (_page(handle).callMethod<JSString>('wordLabel'.toJS, wordIndex.toJS)).toDart;

  @override
  String ayahLabel(PageHandle handle, int ayahIndex) =>
      (_page(handle).callMethod<JSString>('ayahLabel'.toJS, ayahIndex.toJS)).toDart;

  @override
  String text(PageHandle handle, QvpTarget target, int form, String wordSep, String lineSep) =>
      (_page(handle).callMethod<JSString>('text'.toJS, _targetToJs(target), form.toJS)).toDart;

  @override
  List<QvpMatch> search(PageHandle handle, String query, {int form = 4, String mode = 'includes', bool normalize = true, bool looseMatch = true, int limit = 0}) {
    final opt = JSObject()
      ..['form'] = form.toJS
      ..['mode'] = mode.toJS
      ..['normalize'] = normalize.toJS
      ..['looseMatch'] = looseMatch.toJS
      ..['limit'] = limit.toJS;
    final arr = _page(handle).callMethod<JSArray>('search'.toJS, query.toJS, opt);
    return List<QvpMatch>.generate(arr.length, (i) {
      final m = arr[i] as JSObject;
      return QvpMatch(
        word: (m['word'] as JSNumber).toDartInt,
        index: (m['index'] as JSNumber).toDartInt,
        isLooseMatch: (m['isLooseMatch'] as JSBoolean).toDart,
      );
    }, growable: false);
  }

  @override
  String citation(PageHandle handle, List<int> words) =>
      (_page(handle).callMethod<JSString>('citation'.toJS, Uint32List.fromList(words).toJS)).toDart;

  @override
  int attachWords(PageHandle handle, List<int> bytes) =>
      (_page(handle).callMethod<JSNumber>('attachWords'.toJS, Uint8List.fromList(bytes).toJS)).toDartInt;

  @override
  bool hasForm(PageHandle handle, int form) =>
      (_page(handle).callMethod<JSBoolean>('hasForm'.toJS, form.toJS)).toDart;

  // ── Hit testing ──

  @override
  QvpHit? hitTestExact(PageHandle handle, double x, double y) =>
      _readHit(_page(handle).callMethod<JSObject?>('hitTestExact'.toJS, x.toJS, y.toJS));

  @override
  QvpHit? hitTestExactView(PageHandle handle, double viewX, double viewY) =>
      _readHit(_page(handle).callMethod<JSObject?>('hitTestExactView'.toJS, viewX.toJS, viewY.toJS));

  @override
  QvpHit? hitTest(PageHandle handle, double x, double y, QvpHitOptions options) {
    final opt = JSObject()
      ..['maxDistance'] = options.maxDistance.toJS
      ..['gapBias'] = options.gapBias.toJS
      ..['preferExact'] = options.preferExact.toJS;
    return _readHit(_page(handle).callMethod<JSObject?>('hitTest'.toJS, x.toJS, y.toJS, opt));
  }

  @override
  QvpHit? hitTestView(PageHandle handle, double viewX, double viewY, QvpHitOptions options) {
    final opt = JSObject()
      ..['maxDistance'] = options.maxDistance.toJS
      ..['gapBias'] = options.gapBias.toJS
      ..['preferExact'] = options.preferExact.toJS;
    return _readHit(_page(handle).callMethod<JSObject?>('hitTestView'.toJS, viewX.toJS, viewY.toJS, opt));
  }

  @override
  List<QvpLineBand> lineBands(PageHandle handle) => const [];

  @override
  List<QvpHitArea> hitAreas(PageHandle handle, double gapBias) => const [];

  // ── Layout & zoom ──

  @override
  QvpLayout layout(PageHandle handle, QvpLayoutSpec spec) {
    final res = _page(handle).callMethod<JSObject>('layout'.toJS, _specToJs(spec));
    final nLines = (res['nLines'] as JSNumber).toDartInt;
    final lineDyJs = res['lineDy'] as JSFloat32Array?;
    final lineDy = lineDyJs != null ? lineDyJs.toDart : Float32List(nLines);
    return QvpLayout(
      scale: (res['scale'] as JSNumber).toDartDouble,
      offsetX: (res['offsetX'] as JSNumber).toDartDouble,
      offsetY: (res['offsetY'] as JSNumber).toDartDouble,
      contentW: (res['contentW'] as JSNumber).toDartDouble,
      contentH: (res['contentH'] as JSNumber).toDartDouble,
      lineSpacing: (res['lineSpacing'] as JSNumber).toDartDouble,
      lineDy: lineDy,
      slots: const [],
      fitScale: (res['fitScale'] as JSNumber).toDartDouble,
      fitX: (res['fitX'] as JSNumber).toDartDouble,
      fitY: (res['fitY'] as JSNumber).toDartDouble,
      reflowed: (res['reflowed'] as JSBoolean).toDart,
      rows: (res['nRows'] as JSNumber).toDartInt,
    );
  }

  @override
  QvpZoomChange zoomPinch(PageHandle handle, QvpLayoutSpec spec, QvpZoom zoom, QvpView view, double factor, double focalX, double focalY) =>
      QvpZoomChange(zoom: zoom, view: view, relaid: false);

  @override
  QvpZoomChange zoomToStep(PageHandle handle, QvpLayoutSpec spec, QvpZoom zoom, int step, QvpView view) =>
      QvpZoomChange(zoom: zoom, view: view, relaid: false);

  @override
  QvpZoom zoomMode(PageHandle handle, QvpLayoutSpec spec, QvpZoom zoom, QvpZoomMode mode) => zoom;

  @override
  QvpLayoutSpec zoomSpec(PageHandle handle, QvpLayoutSpec spec, QvpZoom zoom) => spec;

  @override
  QvpZoom zoomCarried(PageHandle handle, QvpLayoutSpec spec, QvpZoom zoom) => zoom;

  @override
  double zoomAtStep(PageHandle handle, QvpLayoutSpec spec, int step) => 0;

  @override
  Float32List zoomSteps(PageHandle handle, QvpLayoutSpec spec) => Float32List(0);

  @override
  double reflowMaxZoom(PageHandle handle, QvpLayoutSpec spec) => 1;

  @override
  bool isZoomed(QvpZoom zoom, QvpView view, double fitScale) => false;

  @override
  QvpSideways sidewaysDrag(PageHandle handle, QvpZoom zoom, QvpView view, double fitScale) => QvpSideways.pan;

  @override
  List<QvpDraw> layoutDrawList(PageHandle handle, {double bandTop = 0, double bandBottom = 0}) => const [];

  @override
  List<QvpPlacement> layoutPlacements(PageHandle handle) => const [];

  @override
  QvpLayout? readLayout(PageHandle handle) => null;

  @override
  int? layoutWordRow(PageHandle handle, int word) => null;

  @override
  Uint32List layoutRowWords(PageHandle handle, int row) => Uint32List(0);

  @override
  ({int lines, double lineSpacing}) pageGrid(PageHandle handle) => (lines: 15, lineSpacing: 0);

  @override
  double layoutWastedFraction(PageHandle handle, QvpLayoutSpec spec) => 0;

  @override
  double layoutPrintedHeight(PageHandle handle, QvpLayoutSpec spec) => 0;

  @override
  double layoutLineSpacingToFill(PageHandle handle, QvpLayoutSpec spec, double max) => 0;

  @override
  ({double x0, double y0, double x1, double y1}) wordBoundsView(PageHandle handle, int wordIndex) =>
      (x0: 0, y0: 0, x1: 0, y1: 0);

  // ── Styles ──

  @override
  int style(PageHandle handle, QvpSelector sel, int color, {int ms = 0, int layer = 0}) =>
      (_page(handle).callMethod<JSNumber>('style'.toJS, _selToJs(sel), color.toJS, ms.toJS, layer.toJS)).toDartInt;

  @override
  int styleTarget(PageHandle handle, QvpTarget target, int color, {int ms = 0, int layer = 0}) =>
      (_page(handle).callMethod<JSNumber>('styleTarget'.toJS, _targetToJs(target), color.toJS, ms.toJS, layer.toJS)).toDartInt;

  @override
  int removeStyle(PageHandle handle, int styleHandle) =>
      (_page(handle).callMethod<JSNumber>('removeStyle'.toJS, styleHandle.toJS)).toDartInt;

  @override
  int recolorStyle(PageHandle handle, int styleHandle, int color, int ms) =>
      (_page(handle).callMethod<JSNumber>('recolorStyle'.toJS, styleHandle.toJS, color.toJS, ms.toJS)).toDartInt;

  @override
  int hide(PageHandle handle, QvpSelector sel) =>
      (_page(handle).callMethod<JSNumber>('hide'.toJS, _selToJs(sel))).toDartInt;

  @override
  void clearStyles(PageHandle handle) => _page(handle).callMethod('clearStyles'.toJS);

  @override
  void clearLayer(PageHandle handle, int layer) => _page(handle).callMethod('clearLayer'.toJS, layer.toJS);

  @override
  void setDefaultColor(PageHandle handle, int color) =>
      _page(handle).callMethod('setDefaultColor'.toJS, color.toJS);

  @override
  int theme(PageHandle handle, QvpTheme t) => 0;

  @override
  List<int> styleHandles(PageHandle handle) => const [];

  // ── Clock & display list ──

  @override
  bool tick(PageHandle handle, double nowMs) =>
      (_page(handle).callMethod<JSBoolean>('tick'.toJS, nowMs.toJS)).toDart;

  @override
  Uint32List colors(PageHandle handle, int nPaths) {
    final arr = _page(handle).callMethod<JSUint32Array>('colors'.toJS);
    return arr.toDart;
  }

  @override
  List<QvpStyledPath> styledPaths(PageHandle handle) {
    final arr = _page(handle).callMethod<JSArray>('styledPaths'.toJS);
    return List<QvpStyledPath>.generate(arr.length, (i) {
      final p = arr[i] as JSObject;
      return (
        path: (p['path'] as JSNumber).toDartInt,
        color: (p['color'] as JSNumber).toDartInt,
      );
    }, growable: false);
  }

  @override
  int colorOf(PageHandle handle, int path) =>
      (_page(handle).callMethod<JSNumber>('colorOf'.toJS, path.toJS)).toDartInt;

  // ── Highlights ──

  @override
  int highlight(PageHandle handle, QvpTarget target, QvpHighlightStyle style) =>
      (_page(handle).callMethod<JSNumber>('highlight'.toJS, _targetToJs(target), _hlToJs(style))).toDartInt;

  @override
  bool moveHighlight(PageHandle handle, int highlightHandle, QvpTarget target) =>
      (_page(handle).callMethod<JSBoolean>('moveHighlight'.toJS, highlightHandle.toJS, _targetToJs(target))).toDart;

  @override
  bool restyleHighlight(PageHandle handle, int highlightHandle, QvpHighlightStyle style) =>
      (_page(handle).callMethod<JSBoolean>('restyleHighlight'.toJS, highlightHandle.toJS, _hlToJs(style))).toDart;

  @override
  bool removeHighlight(PageHandle handle, int highlightHandle) =>
      (_page(handle).callMethod<JSBoolean>('removeHighlight'.toJS, highlightHandle.toJS)).toDart;

  @override
  void clearHighlights(PageHandle handle) => _page(handle).callMethod('clearHighlights'.toJS);

  @override
  List<int> highlightHandles(PageHandle handle) => const [];

  @override
  List<int> highlightWords(PageHandle handle, int highlightHandle) => const [];

  @override
  List<QvpBox> highlightBoxesView(PageHandle handle) {
    final arr = _page(handle).callMethod<JSArray>('highlightBoxesView'.toJS);
    return List<QvpBox>.generate(arr.length, (i) {
      final b = arr[i] as JSObject;
      return QvpBox(
        id: (b['id'] as JSNumber).toDartInt,
        line: (b['line'] as JSNumber).toDartInt,
        x0: (b['x0'] as JSNumber).toDartDouble,
        y0: (b['y0'] as JSNumber).toDartDouble,
        x1: (b['x1'] as JSNumber).toDartDouble,
        y1: (b['y1'] as JSNumber).toDartDouble,
        color: (b['color'] as JSNumber).toDartInt,
        radius: (b['radius'] as JSNumber).toDartDouble,
      );
    }, growable: false);
  }

  @override
  List<QvpBox> wordBands(PageHandle handle, List<int> ws, {required bool inkHeight, required double padX, required double padY}) => const [];

  // ── Selection ──

  @override
  void select(PageHandle handle, int anchor, int focus) =>
      _page(handle).callMethod('select'.toJS, anchor.toJS, focus.toJS);

  @override
  List<int> selection(PageHandle handle) {
    final res = _page(handle).callMethod<JSUint32Array>('selection'.toJS);
    return res.toDart.toList();
  }

  @override
  String selectionText(PageHandle handle, int form, bool includeCitation) =>
      (_page(handle).callMethod<JSString>('selectionText'.toJS, form.toJS, includeCitation.toJS)).toDart;

  // ── Masks & memorisation ──

  @override
  void mask(PageHandle handle, QvpTarget target, int mode) =>
      _page(handle).callMethod('mask'.toJS, _targetToJs(target), mode.toJS);

  @override
  void maskFrom(PageHandle handle, int wordIndex, int mode) =>
      _page(handle).callMethod('maskFrom'.toJS, wordIndex.toJS, mode.toJS);

  @override
  void maskOptions(PageHandle handle, int blockColor, double padX, double padY, double radius, bool reverse) =>
      _page(handle).callMethodVarArgs('maskOptions'.toJS, [blockColor.toJS, padX.toJS, padY.toJS, radius.toJS, reverse.toJS]);

  @override
  int unmaskNext(PageHandle handle, int n) =>
      (_page(handle).callMethod<JSNumber>('unmaskNext'.toJS, n.toJS)).toDartInt;

  @override
  int maskBack(PageHandle handle, int n) =>
      (_page(handle).callMethod<JSNumber>('maskBack'.toJS, n.toJS)).toDartInt;

  @override
  bool unmaskWord(PageHandle handle, int wordIndex) =>
      (_page(handle).callMethod<JSBoolean>('unmaskWord'.toJS, wordIndex.toJS)).toDart;

  @override
  bool maskWord(PageHandle handle, int wordIndex) =>
      (_page(handle).callMethod<JSBoolean>('maskWord'.toJS, wordIndex.toJS)).toDart;

  @override
  void unmaskAll(PageHandle handle) => _page(handle).callMethod('unmaskAll'.toJS);

  @override
  void maskAll(PageHandle handle) => _page(handle).callMethod('maskAll'.toJS);

  @override
  void unmask(PageHandle handle) => _page(handle).callMethod('unmask'.toJS);

  @override
  List<int> maskHidden(PageHandle handle) => const [];

  @override
  List<int> maskWords(PageHandle handle) => const [];

  @override
  List<QvpBox> maskBoxesView(PageHandle handle) {
    final arr = _page(handle).callMethod<JSArray>('maskBoxesView'.toJS);
    return List<QvpBox>.generate(arr.length, (i) {
      final b = arr[i] as JSObject;
      return QvpBox(
        id: (b['id'] as JSNumber).toDartInt,
        line: (b['line'] as JSNumber).toDartInt,
        x0: (b['x0'] as JSNumber).toDartDouble,
        y0: (b['y0'] as JSNumber).toDartDouble,
        x1: (b['x1'] as JSNumber).toDartDouble,
        y1: (b['y1'] as JSNumber).toDartDouble,
        color: (b['color'] as JSNumber).toDartInt,
        radius: (b['radius'] as JSNumber).toDartDouble,
      );
    }, growable: false);
  }

  // ── Reveal ──

  @override
  int revealStart(PageHandle handle, {required int lit, required bool byAyah, required int grey, required int ink, required bool ayahMarks, required int ms}) => 0;

  @override
  bool revealGoto(PageHandle handle, int at) => false;

  @override
  int? revealPosition(PageHandle handle) => null;

  @override
  int revealStepCount(PageHandle handle) => 0;

  @override
  int revealStepOf(PageHandle handle, int wordIndex) => 0;

  @override
  void revealStop(PageHandle handle) {}

  // ── Dress ──

  @override
  bool dress(PageHandle page, OrnamentsHandle set, QvpDressSpec spec) => false;

  @override
  void undress(PageHandle page) {}

  @override
  QvpView dressClamp(PageHandle page, QvpView view, double viewportW, double viewportH) => view;

  @override
  QvpDressView dressView(PageHandle page, double scale, double viewportW) =>
      QvpDressView(view: const QvpView(), width: 0, height: 0);

  @override
  QvpDressInfo? dressInfo(PageHandle page) => null;

  @override
  List<QvpDressDraw> dressGeometry(PageHandle page) => const [];

  // ── Crop ──

  @override
  QvpCropBounds? cropBounds(PageHandle handle, QvpTarget target, {required double pad, required bool keepAyahMarks}) => null;

  @override
  String? cropSvg(PageHandle handle, QvpTarget target, {required double pad, required bool keepAyahMarks, int? background}) =>
      (_page(handle).callMethod<JSString>('cropSvg'.toJS, _targetToJs(target), pad.toJS)).toDart;

  // ── Atlas ──

  @override
  (AtlasHandle, int pageCount) atlasLoad(Uint8List bytes) {
    final jsAtlas = js.callMethod<JSObject>('loadAtlas'.toJS, bytes.toJS);
    return (WebAtlasHandle(jsAtlas), 604);
  }

  @override
  void atlasFree(AtlasHandle handle) {}

  @override
  int? atlasPageOf(AtlasHandle handle, int surah, int ayah) {
    final res = (_atlas(handle).callMethod<JSNumber>('pageOf'.toJS, surah.toJS, ayah.toJS)).toDartInt;
    return res <= 0 ? null : res;
  }

  @override
  ({(int, int) first, (int, int) last})? atlasPageRange(AtlasHandle handle, int page) => null;

  @override
  QvpAtlasSurah? atlasSurah(AtlasHandle handle, int n) => null;

  @override
  List<QvpAtlasSurah> atlasSurahs(AtlasHandle handle) => const [];

  @override
  QvpAtlasRubuAlHizb? atlasDivision(AtlasHandle handle, int division, int n) => null;

  @override
  int? atlasDivisionOf(AtlasHandle handle, int division, int surah, int ayah) => null;

  @override
  List<int>? atlasPagesOfJuz(AtlasHandle handle, int n) {
    final arr = _atlas(handle).callMethod<JSArray>('pagesOfJuz'.toJS, n.toJS);
    return [(arr[0] as JSNumber).toDartInt, (arr[1] as JSNumber).toDartInt];
  }

  @override
  List<int> atlasSearchSurahs(AtlasHandle handle, String text) => const [];

  @override
  String atlasJson(AtlasHandle handle) => '';

  // ── Passage ──

  @override
  (PassageHandle, List<QvpPassageText> ayahs, double lineSpacing) passageLoad(List<PageHandle> pages, int surah, int from, int to) {
    final jsPages = [for (final p in pages) _page(p)].toJS;
    final jsPassage = js.callMethod<JSObject>('loadPassage'.toJS, jsPages, surah.toJS, from.toJS, to.toJS);
    return (WebPassageHandle(jsPassage), const [], 0);
  }

  @override
  (PassageHandle, List<QvpPassageText> ayahs, double lineSpacing) passageLoadBasmalah(List<PageHandle> pages, int surah) {
    final jsPages = [for (final p in pages) _page(p)].toJS;
    final jsPassage = js.callMethod<JSObject>('loadBasmalah'.toJS, jsPages, surah.toJS);
    return (WebPassageHandle(jsPassage), const [], 0);
  }

  @override
  void passageFree(PassageHandle handle) {
    _passage(handle).callMethod('free'.toJS);
  }

  @override
  QvpPassageLayout? passageLayout(PassageHandle handle, QvpPassageSpec spec) => null;

  // ── Ornaments ──

  @override
  (OrnamentsHandle, List<QvpOrnament>) ornamentsLoad(Uint8List bytes) {
    final jsOrn = js.callMethod<JSObject>('loadOrnaments'.toJS, bytes.toJS);
    return (WebOrnamentsHandle(jsOrn), const []);
  }

  @override
  void ornamentsFree(OrnamentsHandle handle) {
    _ornaments(handle).callMethod('free'.toJS);
  }

  @override
  int ornamentFind(OrnamentsHandle handle, int kind, String style) => qvpNone;
}
