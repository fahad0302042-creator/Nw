import 'package:html/dom.dart' as dom;

import 'rule.dart';

/// Pure (network free) extraction helpers used by [SourceEngine].
///
/// Everything here is deterministic so it can be unit tested without hitting
/// the internet.
class Extractor {
  Extractor._();

  // ------------------------------------------------------------------- html

  static List<dom.Element> htmlList(dynamic root, String? selector) {
    if (selector == null || selector.trim().isEmpty) {
      return const <dom.Element>[];
    }
    try {
      final found = root.querySelectorAll(selector);
      return List<dom.Element>.from(found as Iterable);
    } catch (_) {
      return const <dom.Element>[];
    }
  }

  static dom.Element? htmlPick(dynamic root, String? selector) {
    if (selector == null || selector.trim().isEmpty) {
      return root is dom.Element ? root : null;
    }
    try {
      return root.querySelector(selector) as dom.Element?;
    } catch (_) {
      return null;
    }
  }

  static String? htmlValue(dynamic root, Rule? rule) {
    if (rule == null) return null;
    if (rule.value != null) return rule.value;

    dom.Element? element;
    if (rule.sel == null || rule.sel!.isEmpty) {
      element = root is dom.Element ? root : htmlPick(root, 'html');
    } else {
      element = htmlPick(root, rule.sel);
    }
    if (element == null) return null;
    return rule.apply(readAttribute(element, rule.attrCandidates));
  }

  static List<String> htmlValues(dynamic root, Rule? rule) {
    if (rule == null) return const <String>[];
    final elements = htmlList(root, rule.sel);
    final out = <String>[];
    for (final element in elements) {
      final value = rule.apply(readAttribute(element, rule.attrCandidates));
      if (value != null && value.isNotEmpty) out.add(value);
    }
    return out;
  }

  static String? readAttribute(dom.Element element, List<String> candidates) {
    for (final attr in candidates) {
      switch (attr) {
        case 'text':
          final text = element.text.trim();
          if (text.isNotEmpty) return text;
          break;
        case 'html':
        case 'innerHtml':
          return element.innerHtml;
        case 'outerHtml':
          return element.outerHtml;
        default:
          final value = element.attributes[attr];
          if (value != null && value.trim().isNotEmpty) return value;
      }
    }
    return null;
  }

  // ------------------------------------------------------------------- json

  static dynamic jsonNode(dynamic root, String? path) {
    if (path == null || path.isEmpty || path == '.') return root;
    dynamic current = root;
    for (final part in path.split('.')) {
      if (current == null) return null;
      if (part.isEmpty) continue;
      final indexMatches = RegExp(r'\[(\d+)\]').allMatches(part).toList();
      final name = part.replaceAll(RegExp(r'\[\d+\]'), '');
      if (name.isNotEmpty) {
        if (current is Map) {
          current = current[name];
        } else {
          return null;
        }
      }
      for (final match in indexMatches) {
        final index = int.parse(match.group(1)!);
        if (current is List && index >= 0 && index < current.length) {
          current = current[index];
        } else {
          return null;
        }
      }
    }
    return current;
  }

  static List<dynamic> jsonList(dynamic root, String? path) {
    final node = jsonNode(root, path);
    if (node is List) return node;
    if (node is Map) return node.values.toList();
    return const <dynamic>[];
  }

  static String? jsonValue(dynamic node, Rule? rule) {
    if (rule == null) return null;
    if (rule.value != null) return rule.value;
    final found = jsonNode(node, rule.path);
    if (found == null) return null;
    if (found is List || found is Map) return null;
    return rule.apply(found.toString());
  }

  static List<String> jsonValues(dynamic node, Rule? rule) {
    if (rule == null) return const <String>[];
    final found = jsonNode(node, rule.path);
    if (found is List) {
      return found
          .map((e) => rule.apply(e.toString()))
          .whereType<String>()
          .where((e) => e.isNotEmpty)
          .toList();
    }
    final single = jsonValue(node, rule);
    if (single == null || single.isEmpty) return const <String>[];
    return single
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }
}
