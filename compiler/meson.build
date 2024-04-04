project('Compiler', 'c',
  default_options : ['c_std=c2x'])

executable('Compiler',
  sources : ['src/main.c'],
  include_directories : include_directories('include'),
  install : true,
  c_args : ['-std=c2x']
  )

subdir('tests')
