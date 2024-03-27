munit_dep = dependency('munit', fallback : ['munit', 'munit_dep'])

test_executable = executable(
  'test_tokenizer',
  sources : [
    'test_tokenizer.c',
    '../src/tokenizer.c'
  ],
  dependencies : munit_dep,
  include_directories : inc,
  override_options: ['c_std=c2x']
)

test('tokenizer_test', test_executable)
