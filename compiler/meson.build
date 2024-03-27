project('Compiler', 'c',
  default_options : ['c_std=c11'])

inc = include_directories('include')

executable('Compiler',
  sources : ['src/main.c', 'src/tokenizer.c'],
  include_directories : inc,
  install : true)

subdir('tests')
