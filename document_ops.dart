import 'dart:convert';
import 'package:flutter_quill/flutter_quill.dart' as q;
import 'model.dart';

q.Document readDocument(CreativeObject object) {
  final delta = object.meta['delta'];
  if (delta is List) return q.Document.fromJson(List<dynamic>.from(delta));
  return q.Document.fromJson([{'insert': object.body.endsWith('\n') ? object.body : '${object.body}\n'}]);
}
void storeDocument(CreativeObject object, q.Document document) {
  object.meta['delta'] = document.toDelta().toJson();
  object.body = document.toPlainText();
}
void replaceRange(CreativeObject object, int start, int end, String text, {String? expected}) {
  final doc = readDocument(object);
  final plain = doc.toPlainText();
  if (start < 0 || end < start || end > doc.length - 1) throw const FormatException('The selected range no longer exists. Select the text again.');
  if (expected != null && plain.substring(start, end) != expected) throw const FormatException('The selected text has changed. Select it again before applying this response.');
  if (end > start) doc.delete(start, end - start);
  if (text.isNotEmpty) doc.insert(start, text);
  storeDocument(object, doc);
}
void appendText(CreativeObject object, String text) {
  if (object.meta['delta'] != null || ['script','manuscript'].contains(object.kind)) {
    final doc = readDocument(object);
    doc.insert(doc.length - 1, '\n$text');
    storeDocument(object, doc);
  } else { object.body += '\n\n$text'; }
}
Map<String,dynamic> deepMap(Map<String,dynamic> value) => Map<String,dynamic>.from(jsonDecode(jsonEncode(value)));

class SelectionRequest {
  SelectionRequest({required this.objectId,required this.start,required this.end,required this.text,required this.action});
  final String objectId, text, action;
  final int start,end;
  Map<String,dynamic> toJson()=>{'objectId':objectId,'start':start,'end':end,'text':text,'action':action};
}
