Inspector numeric field with a one-letter label and trailing unit. Pair them in rows for X/Y and W/H.
```jsx
<NumericField label="X" value={x} onChange={setX} />
<NumericField label="R" value={rot} unit="°" onChange={setRot} />
<NumericField label="" value={op} unit="%" min={0} max={100} onChange={setOp} width={48} />
```
