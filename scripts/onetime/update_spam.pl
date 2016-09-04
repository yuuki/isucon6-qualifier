#!/usr/bin/env perl

use strict;
use warnings;
use utf8;

use Isuda::Web;
use Digest::SHA1 qw/sha1_hex/;
use Encode qw/encode_utf8 decode_utf8/;

my $web = Isuda::Web->new;
my $entries = $web->dbh->select_all(qq[
    SELECT keyword,description FROM entry WHERE id > 7352
]);

foreach my $entry (@$entries) {
    my $is_description_valid = $web->is_spam_contents($entry->{description});
    $web->dbh->query(qq[
        INSERT INTO spam (content_hash, valid)
        VALUES  (?, ?)
    ], sha1_hex(encode_utf8 $entry->{description}), 0+$is_description_valid);

    my $is_keyword_valid = $web->is_spam_contents($entry->{keyword});
    $web->dbh->query(qq[
        INSERT INTO spam (content_hash, valid)
        VALUES  (?, ?)
    ], sha1_hex(encode_utf8 $entry->{keyword}), 0+$is_keyword_valid);
}

