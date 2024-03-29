#!/usr/bin/env perl
use utf8;
use strict;
use warnings;

use Isuda::Web;

my $logfile = $ARGV[0] or die "log file reuqire";

open(my $logfh, '<', $logfile);

my $web = Isuda::Web->new;

while (my $line = readline $logfh) {
    chomp($line);
    my $is_description_valid = $web->is_spam_contents($line);
    $web->dbh->query(qq[
        INSERT IGNORE INTO spam (content_hash, valid)
        VALUES  (?, ?)
    ], $line, 0+$is_description_valid);
}

close($logfh);
