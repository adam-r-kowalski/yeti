project('Compiler', 'c')

inc = include_directories('include')

executable('Compiler',
  sources : ['src/main.c', 'src/tokenizer.c'],
  include_directories : inc,
  install : true,
  override_options : ['c_std=c2x'])

subdir('tests')
