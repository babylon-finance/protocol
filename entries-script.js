const csv = require('csv-parser');
const fs = require('fs');
// const TwitterApi = require('twitter-api-v2').TwitterApi;

let entries = require('./entries.json')[0].data;
const superagent = require('superagent');

const impossibleUsers = require('./if.js').users;
const babUsers = require('./babdeposits.js').users;
const degenUsers = require('./degen.js').users;
const validEmails = require('./emails.js').emails;
const twitterList = require('./twitter.js').twitter;
const settlersList = require('./settlers.js').settlers;

// Instanciate with desired auth type (here's Bearer v2 auth)
// const twitterClient = new TwitterApi('AAAAAAAAAAAAAAAAAAAAAB7PVgEAAAAAcboprQmIBJ1AFt16tgH4PL3Rq1Q%3DTphxU4mHBPjdeAZ9T10ReyiLBXYq9xTqbQaK51ROcYjoUFAUXW');

// Tell typescript it's a readonly app
// const roClient = twitterClient.readOnly;

const ifMap = {};
const babMap = {};
const degenMap = {};
const sushiMap = {};
const farmMap = {};
const pickleMap = {};
const emailMap = {};
const twitterMap = {};
const settlersMap = {};

impossibleUsers.forEach((add) => {
  ifMap[add.toLowerCase()] = true;
});

babUsers.forEach((add) => {
  babMap[add.toLowerCase()] = true;
});

degenUsers.forEach((add) => {
  degenMap[add.toLowerCase()] = true;
});

settlersList.forEach((add) => {
  settlersMap[add.toLowerCase()] = true;
});

validEmails &&
  validEmails.forEach((add) => {
    emailMap[add.toLowerCase()] = true;
  });
twitterList &&
  twitterList.forEach((add) => {
    twitterMap[add.name.toLowerCase()] = add.score;
  });

const IDIA_PRICE = 3;
const FARM_PRICE = 150;
const XSUSHI_PRICE = 13;
const PICKLE_PRICE = 12;

// console.log('emailMap', emailMap);
const mainRoutine = async () => {
  await fs
    .createReadStream('pickle.csv')
    .pipe(csv())
    .on('data', (data) => {
      pickleMap[data.HolderAddress.toLowerCase()] = parseFloat(data.Balance);
    })
    .on('end', () => {
      // console.log(pickleMap);
    });

  await fs
    .createReadStream('farm.csv')
    .pipe(csv())
    .on('data', (data) => {
      farmMap[data.HolderAddress.toLowerCase()] = parseFloat(data.Balance);
    })
    .on('end', () => {
      // console.log(farmMap);
    });

  await fs
    .createReadStream('ifarm.csv')
    .pipe(csv())
    .on('data', (data) => {
      farmMap[data.HolderAddress.toLowerCase()] = farmMap[data.HolderAddress.toLowerCase()]
        ? farmMap[data.HolderAddress.toLowerCase()] + parseFloat(data.Balance)
        : parseFloat(data.Balance);
    })
    .on('end', () => {
      // console.log(farmMap);
    });

  await fs
    .createReadStream('xsushi.csv')
    .pipe(csv())
    .on('data', (data) => {
      sushiMap[data.HolderAddress.toLowerCase()] = parseFloat(data.Balance);
    })
    .on('end', () => {
      // console.log(sushiMap);
    });
  setTimeout(() => {
    entries = entries
      .map(({ data }) => {
        if (!settlersMap[data.wallet.toLowerCase()]) {
          let score = 1;
          if (emailMap[data.email]) {
            score += 10;
          }
          // grab from twitter api
          if (twitterMap[data.twitter]) {
            score += 2 * twitterMap[data.twitter];
          }
          // Impossible finance
          if (ifMap[data.wallet.toLowerCase()]) {
            score = IDIA_PRICE * 30;
          }
          // xSushi finance
          if (sushiMap[data.wallet.toLowerCase()]) {
            score = XSUSHI_PRICE * sushiMap[data.wallet.toLowerCase()];
          }
          // Harvest finance
          if (farmMap[data.wallet.toLowerCase()]) {
            score = FARM_PRICE * farmMap[data.wallet.toLowerCase()];
          }
          // Pickle finance
          if (pickleMap[data.wallet.toLowerCase()]) {
            score = PICKLE_PRICE * pickleMap[data.wallet.toLowerCase()];
          }

          return { address: data.wallet, score, email: data.email, twitter: data.twitter };
        } else {
          return {};
        }
      })
      .filter((e) => e);

    // Add Harvest NFT holders to the top 10000
    // Add Degens to the top 10000
    Object.keys(degenMap).forEach((key) => {
      entries.push({ address: key.toLowerCase(), score: 20000 });
    });
    // Add our depositors to the top 10000
    Object.keys(babMap).forEach((key) => {
      entries.push({ address: key.toLowerCase(), score: 10000 });
    });

    // Sort
    entries = entries.sort(function (a, b) {
      return b.score - a.score;
    });

    const entriesMap = {};
    // Removes duplicates
    entries = entries.filter((entry) => {
      if (entriesMap[entry.address]) {
        return false;
      }
      entriesMap[entry.address] = true;
      return true;
    });
    // Remove duplicates

    console.log('---- sorted ---');
    console.log('count DeFi', entries.filter((e) => e.score > 100).length);
    console.log('count Degen', entries.filter((e) => e.score === 20000).length);
    console.log('count Bab users', entries.filter((e) => e.score === 10000).length);
    console.log('count Email', entries.filter((e) => e.score >= 10).length);
    console.log('count Twitter', entries.filter((e) => e.score > 11).length);
    console.log('count', entries.length);
  }, 1000);
};

const checkEmail = async (email) => {
  try {
    return await superagent.get(
      `https://apilayer.net/api/check?access_key=423293250a0582dd066f1e608f160484&email=${email}`,
    );
  } catch (err) {
    console.error(err);
  }
};

const getEmails = async () => {
  console.log('module.exports = { emails: [');
  entries.forEach(async (e) => {
    if (e.data.email) {
      const result = await checkEmail(e.data.email);
      if (result && result.body && result.body.mx_found) {
        console.log(`'${e.data.email.trim()}',`);
      }
    }
  });
};

const getTwitter = async () => {
  const usersToCheck = [];
  let insideList = [];
  entries.forEach(async (e) => {
    if (e.data.twitter) {
      insideList.push(
        e.data.twitter
          .trim()
          .replace(' ', '')
          .replace('@', '')
          .replace('https://twitter.com/', '')
          .replace('https://mobile.twitter.com/', '')
          .replace('.com', '')
          .replace('.', '')
          .replace('gmail', '')
          .replace('.', '')
          .replace('.', '')
          .split('/')[0],
      );
      if (insideList.length === 100) {
        usersToCheck.push([...insideList]);
        insideList = [];
      }
    }
  });
  let res = [];
  const top = usersToCheck;
  // console.log('top', top);
  while (top.length > 0) {
    const list = top.shift();
    await setTimeout(() => {}, Math.floor(700 * Math.random()));
    try {
      if (list && list.length > 0) {
        // console.log('list', list);
        const users = await roClient.v2.usersByUsernames(list, { 'user.fields': 'public_metrics' });
        res = res.concat(
          users.data.map((user) => {
            return { name: user.username, score: user.public_metrics.followers_count / 100 };
          }),
        );
      }
    } catch (e) {
      console.error('e', e);
    }
  }
  res.forEach((e) => {
    console.log(e);
  });
};
// getEmails();
// getTwitter();
mainRoutine();
