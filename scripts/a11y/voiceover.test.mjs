import test from 'node:test';
import assert from 'node:assert/strict';
import { hasCoreEditorControl } from './voiceover.mjs';

test('selection state alone is not proof of the Select tool', () => {
  assert.equal(hasCoreEditorControl('Properties selected button'), false);
  assert.equal(hasCoreEditorControl('Select layers, then Create Component — the source appears here.'), false);
  assert.equal(hasCoreEditorControl('Design canvas design canvas has keyboard focus'), false);
});
test('named core controls require their button role', () => {
  for (const phrase of ['Select selected button', 'Rectangle button', 'Zoom in button', 'Select, selected, button']) {
    assert.equal(hasCoreEditorControl(phrase), true, phrase);
  }
  assert.equal(hasCoreEditorControl('Rectangle'), false);
});
