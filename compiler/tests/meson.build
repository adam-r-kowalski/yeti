munit_dep = dependency('munit', fallback : ['munit', 'munit_dep'])

test_executable = executable(
  'test_compiler',
  sources : [
    'src/test_main.c',
    'src/test_tokenizer.c',
    'src/test_string_interner.c',
    '../src/string_interner.c'
  ],
  dependencies : munit_dep,
  include_directories : [
    include_directories('include'),
    include_directories('../include'),
  ],
  c_args : ['-std=c2x']
)

test('compiler_test', test_executable)
