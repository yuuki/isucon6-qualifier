use FindBin;
use lib "$FindBin::Bin/extlib/lib/perl5";
use lib "$FindBin::Bin/lib";
use File::Basename;
use Plack::Builder;
use Isuda::Web;
use Cache::Memcached::Fast;
use Sereal;

my $root_dir = File::Basename::dirname(__FILE__);

my $decoder = Sereal::Decoder->new();
my $encoder = Sereal::Encoder->new();

my $app = Isuda::Web->psgi($root_dir);
builder {
    enable 'ReverseProxy';
    enable 'Static',
        path => qr!^/(?:(?:css|js|img)/|favicon\.ico$)!,
        root => $root_dir . '/../public';
    enable 'Session::Simple',
        store => Cache::Memcached::Fast->new({
            servers => [ { address => "localhost:11211",noreply=>0} ],
            serialize_methods => [ sub { $encoder->encode($_[0])}, 
                                   sub { $decoder->decode($_[0])} ],
        }),
        httponly => 1,
        cookie_name => "isuda_session",
        keep_empty => 0;
    $app;
};
