import test from 'node:test';
import assert from 'node:assert/strict';
import { hasCoreEditorControl, voiceOverMove } from './voiceover.mjs';

test('selection state alone is not proof of the Select tool', () => {
  assert.equal(hasCoreEditorControl('Properties selected button'), false);
  assert.equal(hasCoreEditorControl('Select layers, then Create Component — the source appears here.'), false);
  assert.equal(hasCoreEditorControl('Design canvas design canvas has keyboard focus'), false);
});
test('reader traversal enters containers and backs out of a repeated boundary', () => {
  assert.equal(voiceOverMove('scroll area', 'scroll area', 1, 0), 'into');
  assert.equal(voiceOverMove('toolbar', 'toolbar', 1, 1), 'into');
  assert.equal(voiceOverMove('scroll area', 'scroll area', 3, 2), 'out');
  assert.equal(voiceOverMove('Rectangle button', 'Rectangle', 1, 1), 'right');
  assert.equal(voiceOverMove('Select layers, then group', 'Select layers, then group', 1, 0), 'right');
});
test('named core controls require their button role', () => {
  for (const phrase of ['Select selected button', 'Rectangle button', 'Zoom in button', 'Select, selected, button']) {
    assert.equal(hasCoreEditorControl(phrase), true, phrase);
  }
  assert.equal(hasCoreEditorControl('Rectangle'), false);
});
