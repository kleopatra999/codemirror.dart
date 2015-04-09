// Copyright (c) 2015, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

/**
 * A wrapper around the `hint/show-hint.js` addon.
 */
library codemirror.hints;

import 'dart:async';
import 'dart:html' show Element;
import 'dart:js';

import 'codemirror.dart';
import 'src/js_utils.dart';

typedef HintResults HintsHelper(CodeMirror editor, [HintsOptions options]);

typedef Future<HintResults> HintsHelperAsync(CodeMirror editor, [HintsOptions options]);

/**
 * To use codemirror hints (aka code completion), register either a synchronous
 * or aynchronous hints helper for a given mode (see [Hints.registerHintsHelper]
 * and [Hints.registerHintsHelperAsync]). The second helper type returns a
 * `Future` with the completion results.
 *
 * In addition, you need to tie the `autocomplete` command to a key-binding.
 * When creating a CodeMirror instance, pass
 * `'extraKeys': { 'Ctrl-Space': 'autocomplete' }` into the options object.
 * Then, include the hints css in your entrypoint html file:
 * `<link href="packages/codemirror/addon/hint/show-hint.css" rel="stylesheet">`.
 *
 * See the CodeMirror
 * [sample](https://github.com/google/codemirror.dart/tree/master/example) for a
 * working example of using the hints API.
 */
class Hints {
  static bool _inited = false;

  static JsObject get _cm => context['CodeMirror'];

  static void _init() {
    if (_inited) return;
    _inited = true;

    _cm['showHint'] = new JsFunction.withThis(_showHint);
    _cm['commands']['autocomplete'] = _cm['showHint'];
  }

  static void registerHintsHelper(String mode, HintsHelper helper) {
    _init();

    CodeMirror.registerHelper('hint', mode, (editor, options) {
      HintResults results = helper(
          new CodeMirror.fromJsObject(editor), new HintsOptions(options));
      return results == null ? null : results.toProxy();
    });
  }

  static void registerHintsHelperAsync(String mode, HintsHelperAsync helper) {
    _init();

    JsFunction function = new JsFunction.withThis((win, editor, showHints, [options]) {
      var results = helper(new CodeMirror.fromJsObject(editor),
          new HintsOptions.fromProxy(options));

      if (results is Future) {
        results.then((r) {
          showHints.apply([results == null ? null : r.toProxy()]);
        });
      } else if (results is HintResults) {
        return results == null ? null : results.toProxy();
      } else {
        return null;
      }
    });

    function['async'] = true;

    CodeMirror.registerHelper('hint', mode, function);
  }

  static void _showHint(var myThis, var editor, [var hintsFunc, var opt]) {
    var pos = editor.callMethod('getCursor');
    JsObject helper = editor.callMethod('getHelper', [pos, 'hint']);

    if (helper == null) {
      helper = _cm['hint']['auto'];
    }

    Map options = {'hint': helper};
    if (opt != null) {
      options.addAll(opt);
    }

    return editor.callMethod('showHint', [jsify(options)]);
  }
}

/**
 * The plugin understands the following options (the options object will also be
 * passed along to the hinting function, which may understand additional
 * options).
 */
class HintsOptions extends ProxyHolder {
  HintsOptions(JsObject jsProxy) : super(jsProxy);

  factory HintsOptions.fromProxy(JsObject jsProxy) {
    return jsProxy == null ? null : new HintsOptions(jsProxy);
  }

  /**
   * Determines whether, when only a single completion is available, it is
   * completed without showing the dialog. Defaults to true.
   */
  bool get completeSingle => _boolOption('completeSingle', true);

  /**
   * Whether the pop-up should be horizontally aligned with the start of the
   * word (true, default), or with the cursor (false).
   */
  bool get alignWithWord => _boolOption('alignWithWord', true);

  /**
   * When enabled (which is the default), the pop-up will close when the editor
   * is unfocused.
   */
  bool get closeOnUnfocus => _boolOption('closeOnUnfocus', true);

  dynamic getOption(String name) => jsProxy[name];

  bool _boolOption(String name, bool defaultValue) {
    bool val = jsProxy[name];
    return val != null ? val : defaultValue;
  }
}

/// The return value from a hints (code completion) operation.
class HintResults {
  final List _results;
  final Position from;
  final Position to;

  JsObject _obj;

  HintResults.fromStrings(List<String> results, this.from, this.to) :
      this._results = results;

  HintResults.fromHints(List<HintResult> results, this.from, this.to) :
      this._results = results;

  /// The list of code completion results. This list is either a list of
  /// strings or a list of [HintResult]s.
  List get results => _results;

  void registerOnShown(Function onShown) {
    Hints._cm.callMethod("on", [toProxy(), "shown", onShown]);
  }

  void registerOnClose(Function onShown) {
    Hints._cm.callMethod("on", [toProxy(), "close", onShown]);
  }

  void registerOnPick(Function onPick) {
    Hints._cm.callMethod("on", [toProxy(), "pick", (completion)
        => onPick(new HintResult.fromProxy(completion))]);
  }

  void registerOnUpdate(Function onUpdate) {
    Hints._cm.callMethod("on", [toProxy(), "update", onUpdate]);
  }

  void registerOnSelect(Function onSelect) {
    Hints._cm.callMethod("on", [toProxy(), "select", (completion, element)
        => onSelect(new HintResult.fromProxy(completion), element)]);
  }


  JsObject toProxy() {
    if (_obj == null) {
      _obj = jsify({
        'list': _results.map((r) => r is HintResult ? r.toProxy() : r).toList(),
        'from': from.toProxy(),
        'to': to.toProxy()
      });
    }

    return _obj;
  }
}

typedef HintRenderer(Element element, HintResult hint);

typedef HintApplier(CodeMirror editor, HintResult hint, Position from, Position to);

class HintResult {
  /// The completion text. This is the only required property.
  final String text;

  /// The text that should be displayed in the menu.
  final String displayText;

  /// A CSS class name to apply to the completion's line in the menu.
  final String className;

  /// Optional from position that will be used by pick() instead of the global
  /// one passed with the full list of completions.
  final Position from;

  /// Optional to position that will be used by pick() instead of the global one
  /// passed with the full list of completions.
  final Position to;

  /// A method used to create the DOM structure for showing the completion by
  /// appending it to its first argument. This cooresponds to the JS codemirror
  /// `render` function.
  final HintRenderer hintRenderer;

  /// A method used to actually apply the completion, instead of the default
  /// behavior. This cooresponds to the JS codemirror `hint` function.
  final HintApplier hintApplier;

  HintResult(this.text, {this.displayText, this.className, this.from, this.to,
    this.hintRenderer, this.hintApplier});

  HintResult.fromProxy(JsObject m) :
    this.text = m['text'],
    this.displayText = m['displayText'],
    this.className = m['className'],
    this.from = m['from'],
    this.to = m['to'],
    this.hintApplier = ((CodeMirror editor, HintResult hint, Position from, Position to) {
      m['hint'](editor.jsProxy, null, hint.toProxy());
    }),
    this.hintRenderer = ((Element element, HintResult hint) {
      m['render'](element, null, hint.toProxy());
    });

  JsObject toProxy() {
    Map m = {'text': text};
    if (displayText != null) m['displayText'] = displayText;
    if (className != null) m['className'] = className;
    if (from != null) m['from'] = from.toProxy();
    if (to != null) m['to'] = to.toProxy();

    if (hintApplier != null) {
      m['hint'] = (cm, data, completion) {
        Position from = new Position.fromProxy(data['from']);
        Position to = new Position.fromProxy(data['to']);
        hintApplier(new CodeMirror.fromJsObject(cm), this, from, to);
      };
    }

    if (hintRenderer != null) {
      m['render'] = (element, data, completion) {
        hintRenderer(element, this);
      };
    }

    return jsify(m);
  }

  String toString() => '[${text}]';
}
