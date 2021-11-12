const prophets = require('./prophets.json');

const nameAppendixes = ['-zeri', '-ubni', '-ukin', ' I', ' II', ' III', ' IV', ' V', ' X'];

const namesUsed = {};
prophets.map((p, index) => {
  if (index > 8000) {
    if (namesUsed[p.name]) {
      p.name = p.name + nameAppendixes[Math.floor(Math.random() * nameAppendixes.length)];
    }
    namesUsed[p.name] = true;
  }
  return p;
});

console.log('[');
prophets.map((p) => console.log(`${JSON.stringify(p)},`));
console.log(']');
