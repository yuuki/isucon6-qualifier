#!/usr/bin/env perl
use strict;
use warnings;
use utf8;

use Kossy::Connection;
use Kossy::Request;
use Isuda::Web;

my $web = Isuda::Web->new;
my $entries = $web->dbh->select_all(qq[
    SELECT * FROM entry
]);

my $c = Kossy::Connection->new({
    req => Kossy::Request->new(env => {}),
});

foreach my $entry (@$entries) {
    my $html = $web->htmlify($c, $entry->{description});
    $web->dbh->query(qq[
        UPDATE entry SET html=? WHERE id = ?
    ], $html, $entry->{id});
}
