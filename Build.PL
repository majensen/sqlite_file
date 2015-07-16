use Module::Build;

Module::Build->new
    ( module_name        => 'SQLite_File',
      perl               => '5.8',
      requires           => {
			     'DBD::SQLite'                 => '1.25',
			     'Fcntl'                       => 0
                            },
      build_requires     => {
	                     'Test::More'                  => 0,
                             'AnyDBM_File::Importer'       => 0,
                             'Module::Build'               => 0
                            },
      create_makefile_pl => 'passthrough',
      recommends         => {
	                     'AnyDBM_File::Importer'       => 0
                            },
      license            => 'perl',
    )->create_build_script;
