package Kwiki::Atom::Server;
use base 'XML::Atom::Server';

sub client { $_[0]{client} = $_[1] if @_ > 1; $_[0]{client} }
sub print  { $_[0]{print}  = $_[1] if @_ > 1; $_[0]{print} }

*XML::Atom::Server::textValue = \&XML::Atom::Util::textValue;

sub xml_body {
    my $server = shift;
    unless (exists $server->{xml_body}) {
        $server->{xml_body} = XML::XPath->new(
            xml => $server->request_content
        );
    }
    $server->{xml_body};
}

sub handle_request {
    my $server = shift;
    my $self = $server->client;

#    local $SIG{__DIE__} = sub { print "\n\n@_\n"; exit };

    if ($server->request_method eq 'POST') {
        my $page = $self->update_page or return;
        my $url = $server->uri;
        $self->fill_header(
            -status => 201,
            -Content_location => "$url?".$page->id,
        );
        return;
    }

    $server->{cgi}->parse_params($ENV{QUERY_STRING});
    if (my $name = $server->{cgi}->param('page_name')) {
        $page = $self->pages->new_page( $self->pages->name_to_id($name) );
    }
    else {
        $page = $self->pages->current;
    }

    if ($server->request_method eq 'PUT') {
        $self->update_page($page);
    }

    my $entry = $self->make_entry($page, 1);
    return $self->munge($entry->as_xml);
}

sub send_http_header { return }

1;
