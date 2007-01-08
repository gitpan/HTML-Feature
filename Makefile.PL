use ExtUtils::MakeMaker;
WriteMakefile(
    NAME              => 'HTML::Feature',
    VERSION_FROM      => 'lib/HTML/Feature.pm', # finds $VERSION
    PREREQ_PM         => {
        LWP::Simple => 1.41,
        HTML::TokeParser => 2.37,
        HTML::Entities => 1.35,
        Statistics::Lite => 2.0,
        Encode => 2.12,
        Encode::Guess => 2.00,
        Data::Dumper => 2.121_08,
    }, 
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/HTML/Feature.pm', # retrieve abstract from module
       AUTHOR         => 'Takeshi Miki <miki@cpan.org>') : ()),
);
