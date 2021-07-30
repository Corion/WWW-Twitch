package WWW::Twitch;
use Moo 2;
use feature 'signatures';
no warnings 'experimental::signatures';

use HTTP::Tiny;
use JSON 'encode_json', 'decode_json';

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
    $res = decode_json( $res->{content} );
}

# Fetch the schedule of a channel
sub schedule( $self, $channel ) {
    my $res =
        $self->fetch_gql( [{"operationName" => "StreamSchedule",
                            "variables" => { "login" => $channel,
                                             "startingWeekday" => "MONDAY",
                                             "utcOffsetMinutes" => 120,
                                             "startAt" => "2021-07-25T22:00:00.000Z",
                                             "endAt"  => "2021-08-01T21:59:59.059Z"},
                                             "extensions" => {
                                                 "persistedQuery" => {
                                                     "version" => 1,
                                                     "sha256Hash" => "e9af1b7aa4c4eaa1655a3792147c4dd21aacd561f608e0933c3c5684d9b607a6"
                                                }
                                             }
                            }]
        );
    return $res->[0]->{data}->{user}->{channel}->{schedule};
};

sub is_live( $self, $channel ) {
    my $res =
        $self->fetch_gql([{"operationName" => "WithIsStreamLiveQuery",
                           "variables" => {"id" => "50985620"},
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
    use Data::Dumper;
    return $res->[0]->{data};
}

sub stream_playback_access_token( $self, $channel ) {
    my $res =
        $self->fetch_gql([{"operationName" => "PlaybackAccessToken_Template",
            "query" => 'query PlaybackAccessToken_Template($login: String!, $isLive: Boolean!, $vodID: ID!, $isVod: Boolean!, $playerType: String!) {  streamPlaybackAccessToken(channelName: $login, params: {platform: "web", playerBackend: "mediaplayer", playerType: $playerType}) @include(if: $isLive) {    value    signature    __typename  }  videoPlaybackAccessToken(id: $vodID, params: {platform: "web", playerBackend: "mediaplayer", playerType: $playerType}) @include(if: $isVod) {    value    signature    __typename  }}',
            "variables" => {"isLive" => $JSON::true,"login" => "$channel","isVod" => $JSON::false,"vodID" => "","playerType" => "site"}},
        ]);
    return decode_json( $res->[0]->{data}->{streamPlaybackAccessToken}->{value} );
};

sub live_stream( $self, $channel ) {
    my $id = $self->stream_playback_access_token( $channel )->{channel_id};
    my $res =
        $self->fetch_gql(
    [{"operationName" => "WithIsStreamLiveQuery","variables" => {"id" => "$id"},
        "extensions" => {"persistedQuery" => {"version" => 1,"sha256Hash" => "04e46329a6786ff3a81c01c50bfa5d725902507a0deb83b0edbf7abe7a3716ea"}}},
    ]);

    return $res->[0]->{data}->{user}->{stream};
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
