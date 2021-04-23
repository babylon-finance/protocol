module.exports = {
  extends: ['standard', 'plugin:promise/recommended', 'plugin:prettier/recommended'],
  plugins: ['promise', 'babel', 'no-only-tests'],
  env: {
    browser: true,
    node: true,
    mocha: true,
    jest: true,
  },
  globals: {
    artifacts: false,
    contract: false,
    assert: false,
    web3: false,
    ethers: false,
  },
  rules: {
    'prettier/prettier': ['error'],
    'import/extensions': [
      'error',
      'ignorePackages',
      {
        js: 'never',
        ts: 'never',
      },
    ],
    'import/prefer-default-export': 'off',
    'prefer-destructuring': 'off',
    'prefer-template': 'off',
    'no-console': 'off',
    'func-names': 'off',
    // 'no-only-tests/no-only-tests': 'error',
  },
};
