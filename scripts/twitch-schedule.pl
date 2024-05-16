#!perl
use 5.020;
use feature 'signatures';

use WWW::Twitch;
use Data::Dumper;
use Text::Table;

my $twitch = WWW::Twitch->new();

my @out;

#my $channel = 'twitchfarming';
my $channel = 'bootiemashup';

my $s = $twitch->schedule($channel);
if( ! $s ) {
    say "No schedule for $channel";
};

for my $entry ( @{ $s->{segments} } ) {
    push @out, [ $entry->{title}, $entry->{startAt}, $entry->{endAt} ];
    #use Data::Dumper;
    #say Dumper $entry;
};

my $t = Text::Table->new('Title','Start', 'End');
$t->load( @out );
say $t;
