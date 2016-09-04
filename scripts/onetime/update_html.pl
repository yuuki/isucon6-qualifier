#!/usr/bin/env perl
use strict;
use warnings;
use utf8;

use Kossy::Connection;
use Isuda::Web;

my $web = Isuda::Web->new;
my $entries = $web->dbh->select_all(qq[
    SELECT * FROM entry
]);

my $c = Kossy::Connection->new;

foreach my $entry (@$entries) {
    my $html = $web->htmlify($web, $entry->{description});
    $web->dbh->query(qq[
        UPDATE entry SET html=? WHERE id = ?
    ], $html, $entry->{id});
}
