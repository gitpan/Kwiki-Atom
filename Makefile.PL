use inc::Module::Install;

name('Kwiki-Atom');
author('Autrijus Tang <autrijus@autrijus.org>');
abstract('Kwiki Atom Plugin');
license('perl');
version_from('lib/Kwiki/Atom.pm');

warn << ".";
Note: This module does *not* need XML::LibXML.
Please simply ignore XML::Atom's demand of that module.
.

requires(qw(
    perl        5.6.1
    Kwiki       0.32
    XML::XPath  1.13
    XML::Atom   0.09
));

WriteAll( sign => 1 );
