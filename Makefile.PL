use inc::Module::Install;
name 'Catalyst-Model-FormValidator-Lite';
all_from 'lib/Catalyst/Model/FormValidator/Lite.pm';

# requires '';

tests 't/*.t';
author_tests 'xt';

build_requires 'Test::More';
use_test_base;
auto_include;
WriteAll;
