package Kwiki::Atom;
use strict;
use warnings;
use Kwiki::Plugin '-Base';
use Kwiki::Display;
use mixin 'Kwiki::Installer';
our $VERSION = '0.01';

use DateTime;
use XML::Atom;
use XML::Atom::Feed;
use XML::Atom::Link;
use XML::Atom::Entry;
use XML::Atom::Server;
use XML::Atom::Content;

const class_id => 'atom';
const class_title => 'Atom';
#const css_file => 'atom.css';
const config_file => 'atom.yaml';

sub register {
    my $registry = shift;
    $registry->add(action => 'atom_edit');
    $registry->add(action => 'atom_feed');
    $registry->add(action => 'atom_post');
    $registry->add(toolbar => 'recent_changes_atom_button', 
                   template => 'recent_changes_atom_button.html',
                   show_for => ['recent_changes'],
                  );
    $registry->add(toolbar => 'edit_atom_button', 
                   template => 'edit_atom_button.html',
                   show_for => ['display'],
                  );
}

sub fill_links {
    my $name = eval { $self->hub->cgi->page_name };
    push @{ $self->hub->{links}{all} }, ($name ? {
        rel => 'alternate',
        type => 'application/atom+xml',
        href => $self->hub->config->script_name . '?action=atom_edit' .
                '&page_name='. $self->hub->cgi->page_name,
    } : ()), {
        rel => 'service.feed',
        type => 'application/atom+xml',
        href => $self->hub->config->script_name . '?action=atom_feed',
    }, {
        rel => 'service.post',
        type => 'application/atom+xml',
        href => $self->hub->config->script_name . '?action=atom_post',
    };
    return;
}

sub fill_header {
    my @headers = @_;
    require Spoon::Cookie;
    my $ref = Spoon::Cookie->can('content_type');
    *Spoon::Cookie::content_type = sub {
        *Spoon::Cookie::content_type = $ref;
        return( -type => 'application/atom+xml', @headers );
    };
}


sub make_entry {
    my $page = shift;
    my $url = $self->config->site_url . '?' . $page->uri;

    my $author = XML::Atom::Person->new;
    $author->name($page->metadata->edit_by);

    my $link = XML::Atom::Link->new;
    $link->type('text/html');
    $link->rel('alternate');
    $link->href($url);
    $link->title($page->id);

    my $entry = XML::Atom::Entry->new;
    $entry->title($page->id);
    $entry->content(do {
        no warnings 'redefine';
        local *XML::LibXML::new = sub { die };
        local *XML::XPath::new = sub { die };
        XML::Atom::Content->new(
            Type => 'text/plain',
            Body => $self->utf8_encode($page->content),
        );
    });
    # $entry->summary('');
    $entry->issued( DateTime->from_epoch( epoch => $page->io->ctime )->iso8601 . 'Z' );
    $entry->modified( DateTime->from_epoch( epoch => $page->io->mtime )->iso8601 . 'Z' );
    $entry->id($url);

    $entry->author($author);
    $entry->add_link($link);

    return $entry;
}

sub atom_post {
    my $server = XML::Atom::Server->new;
    my $entry = $server->atom_body;
    my $page = $self->pages->new_page($entry->title);
    if ($page->exists) {
        $self->fill_header( -status => 409 );
        return '';
    }
    $self->hub->users->current(
        $self->hub->users->new_user(
            $server->get_auth_info->{UserName}
        )
    );
    $page->content($entry->content);
    $page->update->store;
    return $self->redirect($page->uri);
}

sub atom_edit {
    my $page = $self->pages->current;
    my $entry = $self->make_entry($page);
    $self->fill_header;
    return $entry->as_xml;
}

sub atom_feed {
    my $depth = 15;
    my $pages = [
        sort {
            $b->modified_time <=> $a->modified_time 
        } $self->pages->recent_by_count($depth)
    ];

    $self->fill_header;
    return $self->generate($pages); # XXX

    $self->hub->load_class('cache')->process(
        sub { $self->generate($pages) }, 'atom', $depth, int(time / 120)
    );
}

use Spiffy '-yaml';
sub generate {
    my $pages = shift;
    my $datetime = @$pages 
        ? DateTime->from_epoch( epoch => $pages->[0]->metadata->edit_unixtime )
        : DateTime->now;

    my $link = XML::Atom::Link->new;
    $link->type('text/html');
    $link->rel('alternate');
    $link->title($self->config->site_title);
    $link->href($self->config->site_url);

    my $feed = XML::Atom::Feed->new;
    $feed->title($self->config->site_title);
    $feed->info($self->config->site_title);
    $feed->add_link($link);
    $feed->modified($datetime->iso8601 . 'Z');

    my $author = XML::Atom::Person->new;
    $author->name($self->config->site_url);

    $self->config->script_name(
        $self->config->site_url . $self->config->script_name
    );
    for my $page (@$pages) {
        $feed->add_entry( $self->make_entry($page) );
    }
    $feed->as_xml;
}

1;

__DATA__

=head1 NAME 

Kwiki::Atom - Kwiki Atom Plugin

=head1 SYNOPSIS

=head1 DESCRIPTION

This is merely a stub pre-release.  It does not do anything really
sensible yet, and had not been checked for interoperability.

Please check back in a few days.

=head1 AUTHOR

Autrijus Tang E<lt>autrijus@autrijus.orgE<gt>

=head1 COPYRIGHT

Copyright 2004 by Autrijus Tang E<lt>autrijus@autrijus.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See http://www.perl.com/perl/misc/Artistic.html

=cut
__config/atom.yaml__
site_description: The Kwiki Wiki
site_url: http://www.kwiki.org/
__template/tt2/recent_changes_atom_button.html__
<!-- BEGIN recent_changes_atom_button.html -->
<a href="[% script_name %]?action=atom_feed" title="AtomFeed">
[% INCLUDE recent_changes_atom_button_icon.html %]
</a>
<!-- END recent_changes_atom_button.html -->
__template/tt2/recent_changes_atom_button_icon.html__
<!-- BEGIN recent_changes_atom_button_icon.html -->
Atom
<!-- END recent_changes_atom_button_icon.html -->
__icons/gnome/template/recent_changes_atom_button_icon.html__
<!-- BEGIN recent_changes_atom_button_icon.html -->
<img src="icons/gnome/image/atom_feed.png" alt="Atom" />
<!-- END recent_changes_atom_button_icon.html -->
__icons/gnome/image/atom_feed.png
iVBORw0KGgoAAAANSUhEUgAAAA8AAAAPBAMAAADJ+Ih5AAAAMFBMVEX////yZ2fh4eH5+fm+
v7/r6+u3SEjV1dWmenqzs7PPz8/Hx8elpaXGxsbMzMyUlJQfgNlcAAAAAXRSTlMAQObYZgAA
ABZ0RVh0U29mdHdhcmUAZ2lmMnBuZyAyLjQuNqQzgxcAAAB7SURBVHjaY2DAAEy3d++NelfM
wBBrwHzziuodA4ZFDOvKy51YFjBctdVqy7iieoCh6JGFYFqr7wQGewU1QbE8/g0MlUBGWpb9
BIbNSy3S0lqnTmC4YLeyLeNIwQGGCwxaV+ZMYjjA8IiB+c7PUJ0CBrvbWyZZvduKsBMAMi0q
dW1+s4IAAAAASUVORK5CYII=
__template/tt2/edit_atom_button.html__
<!-- BEGIN edit_atom_button.html -->
<a href="[% script_name %]?action=atom_edit&page_name=[% page_uri %]" title="AtomEdit">
[% INCLUDE edit_atom_button_icon.html %]
</a>
<!-- END edit_button.html -->
__template/tt2/edit_atom_button_icon.html__
<!-- BEGIN edit_atom_button_icon.html -->
Atom
<!-- END edit_atom_button_icon.html -->

__icons/gnome/template/edit_atom_button_icon.html__
<!-- BEGIN edit_atom_button_icon.html -->
<img src="icons/gnome/image/atom_edit.png" alt="Atom" />
<!-- END edit_atom_button_icon.html -->

__icons/gnome/image/atom_edit.png__
iVBORw0KGgoAAAANSUhEUgAAAA8AAAAPBAMAAADJ+Ih5AAAAMFBMVEX////yZ2fh4eH5+fm+
v7/r6+u3SEjV1dWmenqzs7PPz8/Hx8elpaXGxsbMzMyUlJQfgNlcAAAAAXRSTlMAQObYZgAA
ABZ0RVh0U29mdHdhcmUAZ2lmMnBuZyAyLjQuNqQzgxcAAAB7SURBVHjaY2DAAEy3d++NelfM
wBBrwHzziuodA4ZFDOvKy51YFjBctdVqy7iieoCh6JGFYFqr7wQGewU1QbE8/g0MlUBGWpb9
BIbNSy3S0lqnTmC4YLeyLeNIwQGGCwxaV+ZMYjjA8IiB+c7PUJ0CBrvbWyZZvduKsBMAMi0q
dW1+s4IAAAAASUVORK5CYII=
__template/tt2/kwiki_begin.html__
<!-- BEGIN kwiki_begin.html -->
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
  <meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
  <title>
[% IF hub.action == 'display' || 
      hub.action == 'edit' || 
      hub.action == 'revisions' 
%]
  [% hub.cgi.page_name %] -
[% END %]
[% IF hub.action != 'display' %]
  [% self.class_title %] - 
[% END %]
  [% site_title %]</title>
[% hub.load_class('atom').fill_links %]
[% FOR link = hub.links.all -%]
  <link rel="[% link.rel %]" type="[% link.type %]" href="[% link.href %]" />
[% END %]
[% FOR css_file = hub.css.files -%]
  <link rel="stylesheet" type="text/css" href="[% css_file %]" />
[% END -%]
[% FOR javascript_file = hub.javascript.files -%]
  <script type="text/javascript" src="[% javascript_file %]"></script>
[% END -%]
  <link rel="shortcut icon" href="" />
  <link rel="start" href="[% script_name %]" title="Home" />
</head>
<body>
<!-- END kwiki_begin.html -->
