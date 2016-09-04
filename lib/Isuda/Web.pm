package Isuda::Web;
use 5.014;
use warnings;
use utf8;
use Kossy;
use DBIx::Sunny;
use Encode qw/encode_utf8 decode_utf8/;
use POSIX qw/ceil/;
use Furl;
use JSON qw/decode_json/;
use String::Random qw/random_string/;
use Digest::SHA1 qw/sha1_hex/;
use URI::Escape qw/uri_escape_utf8/;
use Text::Xslate::Util qw/html_escape/;
use List::Util qw/min max/;
use Cache::Memcached::Fast;
use Sereal qw(encode_sereal decode_sereal);

my $decoder = Sereal::Decoder->new();
my $encoder = Sereal::Encoder->new();

{

    my $memd = Cache::Memcached::Fast->new({
        servers => [ { address => 'localhost:11211', noreply => 1 }, ]
    });
    my $dbh = DBIx::Sunny->connect(config('dsn'), config('db_user'), config('db_password'), {
        Callbacks => {
            connected => sub {
                my $dbh = shift;
                $dbh->do(q[SET SESSION sql_mode='TRADITIONAL,NO_AUTO_VALUE_ON_ZERO,ONLY_FULL_GROUP_BY']);
                $dbh->do('SET NAMES utf8mb4');
                return;
            },
        },
    });

    my $users = $dbh->select_all(q[
        SELECT * FROM user
    ]);

    for my $user (@$users) {
        my $encoded_user = $encoder->encode($user);
        $memd->set('user:'.$user->{id}, $encoded_user);
        $memd->set('user:'.$user->{name}, $encoded_user);
    }
}

sub config {
    state $conf = {
        dsn           => $ENV{ISUDA_DSN}         // 'dbi:mysql:db=isuda',
        db_user       => $ENV{ISUDA_DB_USER}     // 'root',
        db_password   => $ENV{ISUDA_DB_PASSWORD} // 'root',
        isutar_origin => $ENV{ISUTAR_ORIGIN}     // 'http://localhost:5001',
        isupam_origin => $ENV{ISUPAM_ORIGIN}     // 'http://localhost:5050',
    };
    my $key = shift;
    my $v = $conf->{$key};
    unless (defined $v) {
        die "config value of $key undefined";
    }
    return $v;
}

sub memd {
    my ($self) = @_;

    return $self->{memd} //= Cache::Memcached::Fast->new({
        servers => [ { address => 'localhost:11211', noreply => 1 }, ]
    });
}

sub dbh {
    my ($self) = @_;
    return $self->{dbh} //= DBIx::Sunny->connect(config('dsn'), config('db_user'), config('db_password'), {
        Callbacks => {
            connected => sub {
                my $dbh = shift;
                $dbh->do(q[SET SESSION sql_mode='TRADITIONAL,NO_AUTO_VALUE_ON_ZERO,ONLY_FULL_GROUP_BY']);
                $dbh->do('SET NAMES utf8mb4');
                return;
            },
        },
    });
}

sub dbh_star {
    my ($self) = @_;
    return $self->{dbh_star} //= DBIx::Sunny->connect(
        $ENV{ISUTAR_DSN} // 'dbi:mysql:db=isutar', $ENV{ISUTAR_DB_USER} // 'root', $ENV{ISUTAR_DB_PASSWORD} // 'root', {
            Callbacks => {
                connected => sub {
                    my $dbh = shift;
                    $dbh->do(q[SET SESSION sql_mode='TRADITIONAL,NO_AUTO_VALUE_ON_ZERO,ONLY_FULL_GROUP_BY']);
                    $dbh->do('SET NAMES utf8mb4');
                    return;
                },
            },
        },
    );
}

filter 'set_name' => sub {
    my $app = shift;
    sub {
        my ($self, $c) = @_;
        my $user_id = $c->env->{'psgix.session'}->{user_id};
        if ($user_id) {
            $c->stash->{user_id} = $user_id;
            if (my $cache = $self->memd->get('user:'.$user_id)) {
                my $user = $decoder->decode($cache);
                $c->stash->{user_name} = $user->{name};
            } else {
                $c->stash->{user_name} = $self->dbh->select_one(q[
                    SELECT name FROM user
                    WHERE id = ?
                ], $user_id);
            }
            $c->halt(403) unless defined $c->stash->{user_name};
        }
        $app->($self,$c);
    };
};

filter 'authenticate' => sub {
    my $app = shift;
    sub {
        my ($self, $c) = @_;
        $c->halt(403) unless defined $c->stash->{user_id};
        $app->($self,$c);
    };
};

get '/initialize' => sub {
    my ($self, $c)  = @_;
    $self->dbh->query(q[
        DELETE FROM entry WHERE id > 7352
    ]);
    # my $origin = config('isutar_origin');
    # my $url = URI->new("$origin/initialize");
    # Furl->new->get($url);
    $self->dbh_star->query('TRUNCATE star');

    $c->render_json({
        result => 'ok',
    });
};

get '/' => [qw/set_name/] => sub {
    my ($self, $c)  = @_;

    my $PER_PAGE = 10;
    my $page = $c->req->parameters->{page} || 1;

    my $entries = $self->dbh->select_all(qq[
        SELECT * FROM entry
        ORDER BY updated_at DESC
        LIMIT $PER_PAGE
        OFFSET @{[ $PER_PAGE * ($page-1) ]}
    ]);
    foreach my $entry (@$entries) {
        my $html = $self->memd->get($entry->{id});
        if ($html) {
            $entry->{html} = decode_utf8 $html;
        } else {
            $self->memd->set($entry->{id}, encode_utf8($entry->{html}));
        }
        $entry->{stars} = $self->load_stars_from_db($entry->{keyword});
    }

    my $total_entries = $self->dbh->select_one(q[
        SELECT COUNT(*) FROM entry
    ]);
    my $last_page = ceil($total_entries / $PER_PAGE);
    my @pages = (max(1, $page-5)..min($last_page, $page+5));

    $c->render('index.tx', { entries => $entries, page => $page, last_page => $last_page, pages => \@pages });
};

get 'robots.txt' => sub {
    my ($self, $c)  = @_;
    $c->halt(404);
};

post '/keyword' => [qw/set_name authenticate/] => sub {
    my ($self, $c) = @_;
    my $keyword = $c->req->parameters->{keyword};
    unless (length $keyword) {
        $c->halt(400, q('keyword' required));
    }
    my $user_id = $c->stash->{user_id};
    my $description = $c->req->parameters->{description};

    if (is_spam_contents($description) || is_spam_contents($keyword)) {
        $c->halt(400, 'SPAM!');
    }
    my $html = $self->htmlify($c, $description);
    $self->dbh->query(q[
        INSERT INTO entry (author_id, keyword, description, created_at, updated_at, html)
        VALUES (?, ?, ?, NOW(), NOW(), ?)
        ON DUPLICATE KEY UPDATE
        author_id = ?, keyword = ?, description = ?, updated_at = NOW(), html = ?
    ], ($user_id, $keyword, $description, $html) x 2);

    $c->redirect('/');
};

get '/register' => [qw/set_name/] => sub {
    my ($self, $c)  = @_;
    $c->render('authenticate.tx', {
        action => 'register',
    });
};

post '/register' => sub {
    my ($self, $c) = @_;

    my $name = $c->req->parameters->{name};
    my $pw   = $c->req->parameters->{password};
    $c->halt(400) if $name eq '' || $pw eq '';

    my $user_id = register($self->dbh, $name, $pw);

    $c->env->{'psgix.session'}->{user_id} = $user_id;
    $c->redirect('/');
};

sub register {
    my ($dbh, $user, $pass) = @_;

    my $salt = random_string('....................');
    $dbh->query(q[
        INSERT INTO user (name, salt, password, created_at)
        VALUES (?, ?, ?, NOW())
    ], $user, $salt, sha1_hex($salt . $pass));

    return $dbh->last_insert_id;
}

get '/login' => [qw/set_name/] => sub {
    my ($self, $c)  = @_;
    $c->render('authenticate.tx', {
        action => 'login',
    });
};

post '/login' => sub {
    my ($self, $c) = @_;

    my $row;
    my $name = $c->req->parameters->{name};
    my $cache = $self->memd->get('user:'.$name);
    if ($cache) {
        $row = $decoder->decode($cache);
    } else {
        $row = $self->dbh->select_row(q[
            SELECT * FROM user
            WHERE name = ?
        ], $name);
    }
    if (!$row || $row->{password} ne sha1_hex($row->{salt}.$c->req->parameters->{password})) {
        $c->halt(403)
    }

    $c->env->{'psgix.session'}->{user_id} = $row->{id};
    $c->redirect('/');
};

get '/logout' => sub {
    my ($self, $c)  = @_;
    $c->env->{'psgix.session'} = {};
    $c->redirect('/');
};

get '/keyword/:keyword' => [qw/set_name/] => sub {
    my ($self, $c) = @_;
    my $keyword = $c->args->{keyword} // $c->halt(400);

    my $entry = $self->dbh->select_row(qq[
        SELECT * FROM entry
        WHERE keyword = ?
    ], $keyword);
    $c->halt(404) unless $entry;

    my $html = $self->memd->get($entry->{id});
    if ($html) {
        $entry->{html} = decode_utf8 $html;
    } else {
        $self->memd->set($entry->{id}, encode_utf8($entry->{html}));
    }
    $entry->{stars} = $self->load_stars_from_db($entry->{keyword});

    $c->render('keyword.tx', { entry => $entry });
};

post '/keyword/:keyword' => [qw/set_name authenticate/] => sub {
    my ($self, $c) = @_;
    my $keyword = $c->args->{keyword} or $c->halt(400);
    $c->req->parameters->{delete} or $c->halt(400);

    $c->halt(404) unless $self->dbh->select_row(qq[
        SELECT * FROM entry
        WHERE keyword = ?
    ], $keyword);

    $self->dbh->query(qq[
        DELETE FROM entry
        WHERE keyword = ?
    ], $keyword);
    $c->redirect('/');
};

sub htmlify {
    my ($self, $c, $content) = @_;
    return '' unless defined $content;
    my $keywords = $self->dbh->select_all(qq[
        SELECT * FROM entry ORDER BY CHARACTER_LENGTH(keyword) DESC
    ]);
    my %kw2sha;
    my $re = join '|', map { quotemeta $_->{keyword} } @$keywords;
    $content =~ s{($re)}{
        my $kw = $1;
        $kw2sha{$kw} = "isuda_" . sha1_hex(encode_utf8($kw));
    }eg;
    $content = html_escape($content);
    while (my ($kw, $hash) = each %kw2sha) {
        my $url = $c->req->uri_for('/keyword/' . uri_escape_utf8($kw));
        my $link = sprintf '<a href="%s">%s</a>', $url, html_escape($kw);
        $content =~ s/$hash/$link/g;
    }
    $content =~ s{\n}{<br \/>\n}gr;
}

sub load_stars_from_db {
    my ($self, $keyword) = @_;

    my $stars = $self->dbh_star->select_all(q[
        SELECT * FROM star WHERE keyword = ?
    ], $keyword);

    return $stars;
}

sub is_spam_contents {
    my $content = shift;
    my $ua = Furl->new;
    my $res = $ua->post(config('isupam_origin'), [], [
        content => encode_utf8($content),
    ]);
    my $data = decode_json $res->content;
    !$data->{valid};
}

# Isutar

get '/stars' => sub {
    my ($self, $c) = @_;

    my $stars = $self->dbh_star->select_all(q[
        SELECT * FROM star WHERE keyword = ?
    ], $c->req->parameters->{keyword});

    $c->render_json({
        stars => $stars,
    });
};

post '/stars' => sub {
    my ($self, $c) = @_;
    my $keyword = $c->req->parameters->{keyword};

    # my $origin = $ENV{ISUDA_ORIGIN} // 'http://localhost:5000';
    # my $url = "$origin/keyword/" . uri_escape_utf8($keyword);
    # my $res = Furl->new->get($url);
    # unless ($res->is_success) {
    #     $c->halt(404);
    # }
    my $entry = $self->dbh->select_row(qq[
        SELECT * FROM entry
        WHERE keyword = ?
    ], $keyword);
    $c->halt(404) unless $entry;

    $self->dbh_star->query(q[
        INSERT INTO star (keyword, user_name, created_at)
        VALUES (?, ?, NOW())
    ], $keyword, $c->req->parameters->{user});

    $c->render_json({
        result => 'ok',
    });
};

1;
