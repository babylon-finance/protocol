module.exports = {
  env: {
    mocha: true,
  },
  extends: ['airbnb', 'plugin:prettier/recommended'],
  plugins: ['babel', 'no-only-tests'],
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
    'no-only-tests/no-only-tests': 'error',
  },
};
