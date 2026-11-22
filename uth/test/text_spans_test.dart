import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:uth/text_classes.dart';
import 'package:uth/text_spans.dart';

const original = """
Am biodhte ann a bhiodh iad sàbhailte?

’S dòcha rachadh iad thall an Ungair. B’ àbhaist dhaibh toilichte ann.

Bha bàta ga dhèanamh deiseil dhaibh.

Dh’fhalbh iad Northumbria ach cha do ràinig am bàta an Roinn Eòrpa. Shèid stoirm am bàta gu tìr ann an Alba.

B’ e fògarraich a bh’ aca. Cha robh Gàidhlig aca. Dè nam biodh iad an glacadh agus an reic mar thràillean?

Cha robh feum aca a bhith dragh orra.

Bha an clann Sasannach a thaobh athar agus bha an teaghlach air a bhith a’ fuireach ann an Sasainn airson còrr is deich bliadhna. Bha Beurla math aca. Bha beurla math aig mòran Gàidheil cuideachd.
""";

const transcript =
    "nam biodh to ann a bhiodh iad sàbhailte s dè s dòcha rachad air thall an ungair b' àbhaist dhaibh toilichte ann bha bàta ga dhìon air deiseil dhaibh dh'fhalbh iad notumbria agus cha robh ràinig am bàta ann an roinn europa thèid stoirm am bàta gu tìr an alba b e fògarraich a bha aga cha robh gàidhlig aca jane and biggie air an glagadh agus an reic mu chroillidhean cha robh feum agaibh a bhith a dragh oirre bha an clann sasannach a thaobh atha agus bha an t-eagalach air a bhith a fuireach ann an sasainn airson còrr is deich";

void main() {
    test('reveal spans preserve the original text for multiple insertions', () {
    final spanBuilder = ComparisonTextSpanBuilder();
    addTearDown(spanBuilder.dispose);
    final spans = spanBuilder.build(
      original: original,
      comparison: compareText(original, transcript),
      showTranscript: false,
      originalHighlightColor: Colors.green,
      transcriptHighlightColor: Colors.red,
    );

    expect(spans.map((span) => span.toPlainText()).join(), original);
  });
}