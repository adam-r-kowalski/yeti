project('Compiler', 'c',
  default_options : ['c_std=c11'])

executable('Compiler',
  sources : ['src/main.c', 'src/tokenizer.c'],
  include_directories : include_directories('include'),
  install : true)

subdir('tests')
