package Kwiki::Atom;
use strict;
use warnings;
use Kwiki::Plugin '-Base';
use Kwiki::Display;
use mixin 'Kwiki::Installer';
our $VERSION = '0.02';

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
const cgi_class => 'Kwiki::Atom::CGI';
field depth => 0;
field 'server';

sub process {
}

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
                   params_class => $self->class_id,
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

sub toolbar_params {
    return () unless $ENV{CONTENT_TYPE} eq 'application/atom+xml';

    $self->atom_post;

    my %header = &Spoon::Cookie::content_type;
    print CGI::header(%header);
    print $header{-warning} if exists $header{-warning};
    exit;
}

sub fill_header {
    my @headers = @_;

    $self->server(XML::Atom::Server->new);

    no warnings 'redefine';
    require Spoon::Cookie;
    my $ref = Spoon::Cookie->can('content_type');
    *Spoon::Cookie::content_type = sub {
        *Spoon::Cookie::content_type = $ref;
        return( -type => 'application/atom+xml', @headers );
    };
}

sub make_entry {
    my ($page, $depth) = @_;
    my $url = $self->server->uri;

    my $author = XML::Atom::Person->new;
    $author->name($page->metadata->edit_by);

    my $link_html = XML::Atom::Link->new;
    $link_html->type('text/html');
    $link_html->rel('alternate');
    $link_html->href("$url?".$page->uri);
    $link_html->title($page->id);

    my $link_edit = XML::Atom::Link->new;
    $link_edit->type('application/atom+xml');
    $link_edit->rel('service.edit');
    $link_edit->href("$url?action=atom_edit&page_name=".$page->id);
    $link_edit->title($page->id);

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
    }) if $depth;
    $entry->summary('');
    $entry->issued( DateTime->from_epoch( epoch => $page->io->ctime )->iso8601 . 'Z' );
    $entry->modified( DateTime->from_epoch( epoch => $page->io->mtime )->iso8601 . 'Z' );
    $entry->id("$url?".$page->uri);

    $entry->author($author);
    $entry->add_link($link_html);
    $entry->add_link($link_edit);

    return $entry;
}

sub update_page {
    my $page = shift;
    my $method = $self->server->request_method;
    my $entry = $self->server->atom_body;

    open Y, ">>/tmp/y";
    print Y "$method - $entry - $page - ".$self->cgi->POSTDATA."\n";
    close Y;

    if (!$page) {
        $page = $self->pages->new_page($entry->title);

        if ($page->exists and $method eq 'POST') {
            $self->fill_header(
                -status => 409,
                -type => 'text/plain',
                -warning => 'This page already exists',
            );
            return undef;
        }
    }

    $self->hub->users->current(
        $self->hub->users->new_user(
            $self->server->get_auth_info->{UserName}
        )
    );

    $page->content($entry->content->body);
    $page->update->store;
}

sub atom_post {
    $self->fill_header;
    $self->server->{request_content} = $self->cgi->POSTDATA
        if $self->server->request_content eq 'POST';

    my $page = $self->update_page or return;

    my $url = $self->server->uri;
    $self->fill_header(
        -status => 201,
        -Content_location => "$url?".$page->id,
    );

    return;
}

sub atom_edit {
    $self->fill_header;
    my $page = $self->pages->current;

    if ($self->server->request_method eq 'PUT') {
        $self->update_page($page);
    }

    my $entry = $self->make_entry($page, 1);
    return $entry->as_xml;
}

sub atom_feed {
    $self->fill_header;

    my $depth = $self->cgi->depth;
    my $pages = [
        sort {
            $b->modified_time <=> $a->modified_time 
        } ($depth ? $self->pages->recent_by_count($depth) : $self->pages->all)
    ];

    return $self->generate($pages, $depth); # XXX

    $self->hub->load_class('cache')->process(
        sub { $self->generate($pages) }, 'atom', $depth, int(time / 120)
    );
}

use Spiffy '-yaml';
sub generate {
    my ($pages, $depth) = @_;
    my $datetime = @$pages 
        ? DateTime->from_epoch( epoch => $pages->[0]->metadata->edit_unixtime )
        : DateTime->now;

    my $url = $self->server->uri;
    my $link_html = XML::Atom::Link->new;
    $link_html->type('text/html');
    $link_html->rel('alternate');
    $link_html->title($self->config->site_title);
    $link_html->href($url);

    my $link_post = XML::Atom::Link->new;
    $link_post->type('application/atom+xml');
    $link_post->rel('service.post');
    $link_post->title($self->config->site_title);
    $link_post->href("$url?action=atom_post");

    my $feed = XML::Atom::Feed->new;
    $feed->title($self->config->site_title);
    $feed->info($self->config->site_title);
    $feed->add_link($link_html);
    $feed->add_link($link_post);
    $feed->modified($datetime->iso8601 . 'Z');

    my $author = XML::Atom::Person->new;
    $author->name($self->config->site_url);

    $self->config->script_name($url);

    for my $page (@$pages) {
        $feed->add_entry( $self->make_entry($page, $depth) );
    }
    $feed->as_xml;
}

package Kwiki::Atom::CGI;
use Kwiki::CGI '-base';

cgi 'depth';
cgi 'POSTDATA';

1;

package Kwiki::Atom;
1;

__DATA__

=head1 NAME 

Kwiki::Atom - Kwiki Atom Plugin

=head1 VERSION

This document describes version 0.02 of Kwiki::Atom, released
Auguest 26, 2004.

=head1 SYNOPSIS

    % cd /path/to/kwiki
    % kwiki -add Kwiki::Atom

=head1 DESCRIPTION

This Kwiki plugin provides Atom 0.3 integration with Kwiki.

For more info about this kind of integration, please refer to
L<http://www.xml.com/pub/a/2004/04/14/atomwiki.html>.

Currently, this plugin has been tested with the following AtomAPI clients:

=over 4

=item * wxAtomClient.py

L<http://piki.bitworking.org/piki.cgi>

=back

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
site_url: http://localhost/par/
__template/tt2/recent_changes_atom_button.html__
<!-- BEGIN recent_changes_atom_button.html -->
<a href="[% script_name %]?action=atom_feed&depth=15" title="AtomFeed">
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
