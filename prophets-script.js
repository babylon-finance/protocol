const names = require('./names-babylonians');

const permutationsWithReps = (options) => {
  const holdingArr = [];
  const recursivePerms = (singleSolution) => {
    if (singleSolution.length > 3) {
      holdingArr.push(singleSolution);
      return;
    }
    for (let i = 0; i < options.length; i++) {
      recursivePerms(singleSolution.concat([options[i]]));
    }
  };
  recursivePerms([]);
  return holdingArr;
};

const maleNames = names.male.map((name) => {
  return name.split(',')[0].toLowerCase();
});

const femaleNames = names.female.map((name) => {
  return name.split(',')[0].toLowerCase();
});
const nameAppendixes = ['', '-zeri', '-ubni', '-ukin', ' I', ' II', ' III', ' IV', ' V', ' X'];

const valuesBonues = [0, 0.5, 0.75, 1.0, 1.5, 3.5];
const allPerms = permutationsWithReps(valuesBonues, 4);
const perms = allPerms.slice(100, 1050).concat(allPerms.slice(1245, 1296));

const minimumLpBonus = 1.0;
const BABL_TO_SPLIT = 27330;
let totalBonusScore = 0;

let prophets = [];

const namesUsed = {};
for (let i = 0; i <= 9000; i++) {
  const prophet = {
    // gender: Math.random() >= 0.2 ? 'male' : 'female',
    babl: 5,
    floorPrice: 0.25,
    number: i,
    lpBonus: minimumLpBonus,
    voterBonus: 0,
    strategistBonus: 0,
    creatorBonus: 0,
  };
  prophet.name = `Prophet ${i + 1}`;
  // Great prophets
  if (i > 8000) {
    const listToUse = prophet.gender === 'female' ? femaleNames : maleNames;
    const randomItem = listToUse[Math.floor(Math.random() * listToUse.length)];
    prophet.name = randomItem[0].toUpperCase() + randomItem.slice(1);
    // Add suffix
    if (i > 8350) {
      let potentialName = prophet.name + nameAppendixes[Math.floor(Math.random() * nameAppendixes.length)];
      while (namesUsed[potentialName]) {
        potentialName = prophet.name + nameAppendixes[Math.floor(Math.random() * nameAppendixes.length)];
      }
      prophet.name = potentialName;
      namesUsed[potentialName] = true;
    }
    prophet.lpBonus = perms[i - 8000][3] + minimumLpBonus;
    prophet.voterBonus = perms[i - 8000][2];
    prophet.strategistBonus = perms[i - 8000][1];
    prophet.creatorBonus = perms[i - 8000][0];
  }
  prophet.bonusScore =
    (prophet.lpBonus * 2 + prophet.voterBonus + prophet.strategistBonus * 2.5 + prophet.creatorBonus * 1.5) * 100;
  if (i > 8000) {
    totalBonusScore += prophet.bonusScore;
  }
  prophets.push(prophet);
}

const uniqueCharacters = [
  { name: 'Bansir', babl: '100' },
  { name: 'Rodan', babl: '120' },
  { name: 'Sharru-Nada', babl: '145' },
  { name: 'Mathon', babl: '325' },
  { name: 'Kalabab', babl: '400' },
  { name: 'Nomasir, Son of Arkad', babl: '500' },
  { name: 'Arkad', babl: '1000' },
];

prophets = prophets.slice(0, 8000).concat(
  prophets.slice(8000).sort(function (a, b) {
    return a.bonusScore - b.bonusScore;
  }),
);

let totalBablGreat = 0;
prophets.map((p, index) => {
  if (index > 8000) {
    p.number = index;
    if (index >= 8994) {
      p.name = uniqueCharacters[index - 8994].name;
      p.babl = uniqueCharacters[index - 8994].babl;
    } else {
      p.babl = Math.ceil((p.bonusScore / totalBonusScore) * BABL_TO_SPLIT);
    }
    p.floorPrice = (p.babl * 0.05).toFixed(2);
    totalBablGreat += Number(p.babl);
    delete p.bonusScore;
  }
  return p;
});

console.log('total babl given', totalBablGreat);
console.log('[');
prophets.map((p) => console.log(`${JSON.stringify(p)},`));
console.log(']');
