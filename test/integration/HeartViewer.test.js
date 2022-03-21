const { expect } = require('chai');
const { setupTests } = require('fixtures/GardenFixture');

describe('Heart Viewer', function () {
  let heartViewer;

  beforeEach(async () => {
    ({ heartViewer } = await setupTests()());
  });

  describe('can call getter methods', async function () {
    it('calls get goovernance proposals', async function () {
      const proposalInfo = await heartViewer.getGovernanceProposals([]);
      expect(proposalInfo.length).to.eq(4);
    });
  });
});
