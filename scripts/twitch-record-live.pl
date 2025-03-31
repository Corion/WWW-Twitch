#!perl
use 5.020;
use experimental 'signatures';

use WWW::Twitch;
use Getopt::Long;
use Pod::Usage;
use POSIX 'strftime';
use YAML 'LoadFile';
use IO::Async;
use Future::AsyncAwait;
use Text::Table;
use Future::Utils 'fmap_scalar';

=head1 NAME

twitch-record-live.pl - record live Twitch streams

=head1 SYNOPSIS

  twitch-record-live.pl [options] [channel ...]

=head1 OPTIONS

=over 4

=item B<--directory, -d>

Set the output directory for downloading streams

=item B<--dl>

Set the program to use for downloading

Default is C<yt-dlp>

=item B<--quiet, -q>

Don't output anything except in case of errors

=item B<--dry-run, -n>

Do a dry run, don't start a download. This outputs a table with the
live/recording/offline status of the channels.

=item B<--json>

Output the status as JSON structure

This implies C<--dry-run>.

=item B<--max-stale, -s>

Maximum age of last change to a file in seconds until it is considered stale

=item B<--channel-id, -i>

Numeric id of a channel

Specifying this saves one lookup from name to channel id. This currently only
supports a single channel.

=back

=cut

GetOptions(
    'directory|d=s' => \my $stream_dir,
    'dl=s' => \my $youtube_dl,
    'quiet|q' => \my $quiet,
    'max-stale|s=s' => \my $maximum_stale_seconds,
    'channel-id|i=s' => \my $channel_id,
    'config|f=s' => \my $config,
    'n|dry-run'      => \my $dry_run,
    'json'           => \my $output_json,
) or pod2usage(2);

$stream_dir //= '.';
$youtube_dl //= 'yt-dlp';
$maximum_stale_seconds //= 15;
$config //= 'twitch-record-live.yml';
if( -f $config ) {
    $config = LoadFile( $config )
} else {
    $config = {}
}
$dry_run //= $output_json;

my $twitch = WWW::Twitch->new();

sub info( $msg ) {
    if( ! $quiet ) {
        say $msg;
    }
}

my %info;
async sub get_channel_live_info( $channel ) {
    my $res;
    if( exists $info{ $channel }) {
        $res = $info{ $channel }
    } else {
        $res = $info{ $channel } = await $twitch->live_stream_f($channel);
    };
    return $res
};

async sub get_channel_id( $channel ) {
    my $id //= $channel_id
        // $config->{channels}->{$channel}
        // do {
            my $i = await get_channel_live_info($channel);
            if ( $i->{status} eq 'found' ) {
                $i->{stream}->{id}

            } else {
                $i->{status}
            }
        };
    return $id
};

async sub stream_recordings( $directory, $streamname ) {
    my $id = await get_channel_id( $streamname );
    opendir my $dh, $stream_dir
        or die "$stream_dir: $!";
    my @recordings;
    if( $id ) {
        @recordings = grep { /\b$id\b.*\.mp4(\.part)?\z/ }
                     readdir $dh;
    };
    return @recordings
};

if( ! -d $stream_dir ) {
    die "Stream directory '$stream_dir' was not found: $!";
};

# If we have stale recordings, maybe our network went down
# in between
my $stale = $maximum_stale_seconds / (24*60*60);

async sub currently_recording( $channel ) {
    my @current = grep { -M "$stream_dir/$_" < $stale }
                  await stream_recordings( $stream_dir, $channel );
};

async sub check_channel( $channel ) {
    # Check whether the channel is live
    my $info = await get_channel_live_info($channel);
    my $id = { $info->{stream} // {} }->{id};
    return { channel => $channel, id => $id, status => $info->{status} };
};

async sub fetch_info( $channel ) {
    await currently_recording( $channel )->then(async sub(@r) {
        my $res;
        #say sprintf "%s has %d files", $channel, scalar @r;
        my $res;
        if( @r ) {
            # If we have a recent file, we are obviously still recording, no
            # need to hit Twitch
            $res = +{ channel => $channel, status => 'recording' };
        } else {
            my $s = await check_channel( $channel );
            if( $s ) {
                $res = $s;
            } else {
                $res = +{ channel => $channel, status => undef };
            }
        }
        return $res
    });
}

sub check_channels( @channels ) {
    my @fetch = map {
        my $res = fetch_info("$_");
        $res
    } @channels;
    my @status = Future->wait_all(@fetch)->catch(sub { use Data::Dumper; warn Dumper \@_ })->get;
    return map { $_->get } @status
};

my @channels = check_channels( @ARGV );
my $info = [map { [ $_->{channel}, $_->{status} ]} @channels];
if( $output_json) {
    info( encode_json( $info ));
} else {
    my $t = Text::Table->new("Channel", "Status");
    $t->load( $info->@* );
    info( $t );
}

for my $channel (@channels) {
    if( $channel->{status} eq 'live' ) {
        info( "Launching $youtube_dl in $stream_dir" );
        if( ! $dry_run ) {
            chdir $stream_dir;
            # Ugh, we can't do exec() if we have multiple streams ...
            if( my $pid = fork ) {
                info("Download started as pid $pid");
            } else {
                exec $youtube_dl,
                    '-f', 'bestvideo[height<=480]+bestaudio/best[height<=480]/bestvideo[height<=720]/bestvideo',
                    '-q', "https://www.twitch.tv/$channel->{channel}",
                    ;
                die "Couldn't launch $youtube_dl: $!";
            };
        };
    }
}
