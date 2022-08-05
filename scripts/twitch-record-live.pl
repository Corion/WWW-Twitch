#!perl
use 5.020;
use feature 'signatures';
no warnings 'experimental::signatures';

use WWW::Twitch;
use Getopt::Long;
use Pod::Usage;
use POSIX 'strftime';

GetOptions(
    'directory|d=s' => \my $stream_dir,
    'dl=s' => \my $youtube_dl,
    'quiet|q' => \my $quiet,
) or pod2usage(2);

$stream_dir //= '.';
$youtube_dl //= 'youtube-dl';

my $twitch = WWW::Twitch->new();

my $channel = $ARGV[0];
my $info = $twitch->live_stream($channel);

sub info( $msg ) {
    if( ! $quiet ) {
        say $msg;
    }
}

if( ! -d $stream_dir ) {
    die "Stream directory '$stream_dir' was not found: $!";
};

if( $info ) {
    my $id = $info->{id};

    opendir my $dh, $stream_dir
        or die "$stream_dir: $!";

    # If we have stale recordings, maybe our network went down
    # in between
    my $one_minute = 24/60/60;
    my @recordings = grep { /\b$id\b.*\.mp4(\.part)?$/ && -M $_ < $one_minute }
                     readdir $dh;

    @recordings = map { sprintf "%s (%s)", $_, strftime('%H:%M:%S', localtime(-M $_ * 24*60*60 ))} @recordings;

    if( ! @recordings ) {
        info( "$channel is live (Stream $id)");
        info( "Launching $youtube_dl in $stream_dir" );
        chdir $stream_dir;
        exec $youtube_dl, '-q', "https://www.twitch.tv/$channel";
    } else {
        info( "$channel is recording (@recordings)" );
    };

} else {
    info( "$channel is offline" );
}

