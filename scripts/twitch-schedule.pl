#!perl
use 5.020;
use feature 'signatures';

use WWW::Twitch;
use Data::Dumper;
use Text::Table;

my $twitch = WWW::Twitch->new();

my @out;

for my $channel (@ARGV) {
    my $s = $twitch->schedule($channel);
    if( ! $s ) {
        say "No schedule for $channel";
    };

    for my $entry ( @{ $s->{segments} } ) {
        $entry->{channel} = $channel;
        push @out, $entry;
    };
}

@out = map {[ $_->{channel}, $_->{title}, $_->{startAt}, $_->{endAt} ]}
       sort {  $a->{startAt} cmp $b->{startAt}
            || $a->{endAt}   cmp $b->{endAt}
            || $a->{channel} cmp $b->{channel}
            } @out;

my $t = Text::Table->new('Channel', 'Title','Start', 'End');
$t->load( @out );
say $t;
