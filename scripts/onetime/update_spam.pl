#!/usr/bin/env perl

use strict;
use warnings;
use utf8;

use Isuda::Web;

my $web = Isuda::Web->new;
my $entries = $web->dbh->select_all(qq[
    SELECT keyword,description FROM entry WHERE id > 7352
]);

foreach my $entry (@$entries) {
    my $is_description_valid = $web->is_spam_contents($entry->{description});
    $web->dbh->query(qq[
        INSERT INTO spam (content, valid)
        VALUES  (?, ?)
    ], $entry->{description}, $is_description_valid);

    my $is_keyword_valid = $web->is_spam_contents($entry->{keyword});
    $web->dbh->query(qq[
        INSERT INTO spam (content, valid)
        VALUES  (?, ?)
    ], $entry->{keyword}, $is_keyword_valid);
}

