package WWW::Twitch;
use Moo 2;
use feature 'signatures';
no warnings 'experimental::signatures';

use Carp 'croak';

use HTTP::Tiny;
use JSON 'encode_json', 'decode_json';
use POSIX 'strftime';

our $VERSION = '0.01';

=head1 NAME

WWW::Twitch - automate parts of Twitch without the need for an API key

=head1 SYNOPSIS

  use 5.012; # say
  use WWW::Twitch;

  my $channel = 'corion_de';
  my $twitch = WWW::Twitch->new();
  my $info = $twitch->live_stream($channel);
  if( $info ) {
      my $id = $info->{id};

      opendir my $dh, '.'
          or die "$!";

      # If we have stale recordings, maybe our network went down
      # in between
      my @recordings = grep { /\b$id\.mp4(\.part)?$/ && -M $_ < 30/24/60/60 }
                       readdir $dh;

      if( ! @recordings ) {
          say "$channel is live (Stream $id)";
          say "Launching youtube-dl";
          exec "youtube_dl", '-q', "https://www.twitch.tv/$channel";
      } else {
          say "$channel is recording (@recordings)";
      };

  } else {
      say "$channel is offline";
  }


=cut

=head1 METHODS

=head2 C<< ->new >>

  my $twitch = WWW::Twitch->new();

Creates a new Twitch client

=over 4

=item B<device_id>

Optional device id. If missing, a hardcoded
device id will be used.

=item B<client_id>

Optional client id. If missing, a hardcoded
client id will be used.

=item B<client_version>

Optional client version. If missing, a hardcoded
client version will be used.

=item B<ua>

Optional HTTP user agent. If missing, a L<HTTP::Tiny>
object will be constructed.

=back

=cut

has 'device_id' => (
    is => 'ro',
    default => 'WQS1BrvLDgmo6QcdpHY7M3d4eMRjf6ji'
);
has 'client_id' => (
    is => 'ro',
    default => 'kimne78kx3ncx6brgo4mv6wki5h1ko'
);
has 'client_version' => (
    is => 'ro',
    default => '2be2ebe0-0a30-4b77-b67e-de1ee11bcf9b',
);
has 'ua' =>
    is => 'lazy',
    default => sub {
    HTTP::Tiny->new( verify_SSL => 1 ),
};

sub fetch_gql( $self, $query ) {
    my $res = $self->ua->post( 'https://gql.twitch.tv/gql', {
        content => encode_json( $query ),
        headers => {
            # so far we need no headers
            "Client-ID" => $self->client_id,
        },
    });
    if( $res->{content}) {
        $res = decode_json( $res->{content} );
    } else {
        return
    }
}

=head2 C<< ->schedule( $channel ) >>

  my $schedule = $twitch->schedule( 'somechannel', %options );

Fetch the schedule of a channel

=cut

sub schedule( $self, $channel, %options ) {
    $options{ start_at } //= strftime '%Y-%m-%dT%H:%M:%SZ', gmtime(time);
    $options{ end_at }   //= strftime '%Y-%m-%dT%H:%M:%SZ', gmtime(time+24*7*3600);
    warn $options{ start_at };
    warn $options{ end_at };
    my $res =
        $self->fetch_gql( [{"operationName" => "StreamSchedule",
                            "variables" => { "login" => $channel,
                                             "startingWeekday" => "MONDAY",
                                             "utcOffsetMinutes" => 120,
                                             "startAt" => $options{ start_at },
                                             "endAt"  =>  $options{ end_at }
                                             },
                             "extensions" => {
                                 "persistedQuery" => {
                                    "version" => 1,
                                    "sha256Hash" => "d495cb17a67b6f7a8842e10297e57dcd553ea17fe691db435e39a618fe4699cf"
                                 }
                             }
                            }]
        );
    #use Data::Dumper;
    #warn Dumper $res;
    return $res->[0]->{data}->{user}->{channel}->{schedule};
};

=head2 C<< ->is_live( $channel ) >>

  if( $twitch->is_live( 'somechannel' ) ) {
      ...
  }

Check whether a stream is currently live on a channel

=cut

sub is_live( $self, $channel ) {
    my $res =
        $self->fetch_gql([{"operationName" => "WithIsStreamLiveQuery",
                            "extensions" => {
                                                "persistedQuery" => {
                                                    "version" => 1,
                                                    "sha256Hash" => "04e46329a6786ff3a81c01c50bfa5d725902507a0deb83b0edbf7abe7a3716ea"
                                                }
                                            }
                            },
                            #{"operationName" => "ChannelPollContext_GetViewablePoll",
                            #    "variables" => {"login" => "papaplatte"},
                            #    "extensions" => {"persistedQuery" => {"version" => 1,"sha256Hash" => "d37a38ac165e9a15c26cd631d70070ee4339d48ff4975053e622b918ce638e0f"}}}
        ]
        #"Client-Version": "9ea2055a-41f0-43b7-b295-70885b40c41c",
        );
    if( $res ) {
        return $res->[0]->{data};
    } else {
        return
    }
}

=head2 C<< ->stream_playback_access_token( $channel ) >>

  my $tok = $twitch->stream_playback_access_token( 'somechannel' );
  say $tok->{channel_id};

Internal method to fetch the stream playback access token

=cut

sub stream_playback_access_token( $self, $channel ) {
    my $res =
        $self->fetch_gql([{"operationName" => "PlaybackAccessToken_Template",
            "query" => 'query PlaybackAccessToken_Template($login: String!, $isLive: Boolean!, $vodID: ID!, $isVod: Boolean!, $playerType: String!) {  streamPlaybackAccessToken(channelName: $login, params: {platform: "web", playerBackend: "mediaplayer", playerType: $playerType}) @include(if: $isLive) {    value    signature    __typename  }  videoPlaybackAccessToken(id: $vodID, params: {platform: "web", playerBackend: "mediaplayer", playerType: $playerType}) @include(if: $isVod) {    value    signature    __typename  }}',
            "variables" => {"isLive" => $JSON::true,"login" => "$channel","isVod" => $JSON::false,"vodID" => "","playerType" => "site"}},
        ]);
    if ( $res ) {
        if( my $v = $res->[0]->{data}->{streamPlaybackAccessToken}->{value} ) {
            return decode_json( $v )
        };
        require Data::Dumper;
        warn Data::Dumper::Dumper( $res );
        croak "... here";
    } else {
        return
    }
};

=head2 C<< ->live_stream( $channel ) >>

  my $tok = $twitch->live_stream( 'somechannel' );

Internal method to fetch information about a stream on a channel

=cut

sub live_stream( $self, $channel ) {
    my $id = $self->stream_playback_access_token( $channel );
    my $res;
    if( $id ) {
        $id = $id->{channel_id};
        $res =
            $self->fetch_gql(
        [{"operationName" => "WithIsStreamLiveQuery","variables" => {"id" => "$id"},
            "extensions" => {"persistedQuery" => {"version" => 1,"sha256Hash" => "04e46329a6786ff3a81c01c50bfa5d725902507a0deb83b0edbf7abe7a3716ea"}}},
        ]);
    };

    if( $res ) {
        return $res->[0]->{data}->{user}->{stream};
    } else {
        return
    }
}

#curl 'https://gql.twitch.tv/gql#origin=twilight'
#    -H 'User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:90.0) Gecko/20100101 Firefox/90.0'
#    -H 'Accept: */*'
#    -H 'Accept-Language: de-DE'
#    --compressed
#    -H 'Referer: https://www.twitch.tv/'
#    -H 'Client-Id: kimne78kx3ncx6brgo4mv6wki5h1ko'
#    -H 'X-Device-Id: WQS1BrvLDgmo6QcdpHY7M3d4eMRjf6ji'
#    -H 'Client-Version: 2be2ebe0-0a30-4b77-b67e-de1ee11bcf9b'
#    -H 'Content-Type: text/plain;charset=UTF-8'
#    -H 'Origin: https://www.twitch.tv'
#    -H 'DNT: 1'
#    -H 'Connection: keep-alive'
#    -H 'Sec-Fetch-Dest: empty'
#    -H 'Sec-Fetch-Mode: cors'
#    -H 'Sec-Fetch-Site: same-site'
#    --data-raw '[{"operationName":"StreamSchedule","variables":{"login":"bootiemashup","startingWeekday":"MONDAY","utcOffsetMinutes":120,"startAt":"2021-07-25T22:00:00.000Z","endAt":"2021-08-01T21:59:59.059Z"},"extensions":{"persistedQuery":{"version":1,"sha256Hash":"e9af1b7aa4c4eaa1655a3792147c4dd21aacd561f608e0933c3c5684d9b607a6"}}}]'

1;
