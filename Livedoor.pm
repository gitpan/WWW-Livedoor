package WWW::Livedoor;

use strict;
use Carp ();
use vars qw($VERSION @ISA);

$VERSION = sprintf("%d.%02d", q$Revision: 0.01$ =~ /(\d+)\.(\d+)/);

require LWP::RobotUA;
@ISA = qw(LWP::RobotUA);
require HTTP::Request;
require HTTP::Response;

use LWP::Debug ();
use HTTP::Cookies;
use HTTP::Request::Common;

sub new {
	my ($class, $livedoor_id, $password, %opt) = @_;
	my $base = 'http://livedoor.com';

	# Option
	Carp::croak('WWW::Livedoor id required') unless $livedoor_id;
	Carp::croak('WWW::Livedoor password required') unless $password;

	# Make Object
	my $name = "WWW::Livedoor/" . $VERSION;
	my $rules = WWW::Livedoor::RobotRules->new($name);
	my $self = LWP::RobotUA->new($livedoor_id, 'WWW-Livedoor@mail.com', $rules);
	$self = bless $self, $class;
	$self->from($livedoor_id);
	$self->delay(1/60);

	# Setting
	$self->{'livedoor'} = {
		'base'       => $base,
		'id'         => $livedoor_id,
		'password'   => $password,
		'response'   => undef,
		'log'        => $opt{'-log'} ? $opt{'-log'} : \&callback_log,
		'abort'      => $opt{'-abort'} ? $opt{'-abort'} : \&callback_abort,
		'rewrite'    => $opt{'-rewrite'} ? $opt{'-rewrite'} : \&callback_rewrite,
	};

	return $self;
}

sub login {
	my $self = shift;
	my $page = 'http://member.livedoor.com/login/index';
	my $next = ($self->{'livedoor'}->{'next_url'}) ? $self->{'livedoor'}->{'next_url'} : 'http://member.livedoor.com/login/index';
	my %form = (
		'livedoor_id'    => $self->{'livedoor'}->{'id'},
		'password' => $self->{'livedoor'}->{'password'},
		'next_url' => $self->absolute_url($next),
	);
	$self->enable_cookies;
	# Login
	my $res = $self->post($page, %form);
	$self->{'livedoor'}->{'refresh'} = ($res->is_success and $res->headers->header('refresh') =~ /url=([^ ;]+)/) ? $self->absolute_url($1) : undef;
	return $res;
}

sub is_login_required {
	my $self = shift;
	my $res  = (@_) ? shift : $self->{'livedoor'}->{'response'};
	if    (not $res)             { return "cannot get the page"; }
	elsif (not $res->is_success) { return sprintf('Connected is sucessed but faild get page（%s）', $res->message); }
	else {
		my $content = $res->content;

		return "Login Failed ($1)" if ($content =~ /ログインに失敗しました/);
	}
	return 0;
}

sub refresh { return $_[0]->{'livedoor'}->{'refresh'}; }

sub request {
	my $self = shift;
	my @args = @_;
	my $res = $self->SUPER::request(@args);
	
	if ($res->is_success) {
		
		# check contents existence
		
		
		if (my $message = $self->is_login_required($res)) {
			$res->code(401);
			$res->message($message);
		}
	}
	
	# store and return response
	$self->{'livedoor'}->{'response'} = $res;
	return $res;
}

sub get {
	my $self = shift;
	my $url  = shift;
	$url     = $self->absolute_url($url);
	$self->log("[info] GET method => '${url}'\n");
	# get
	my $res  = $self->request(HTTP::Request->new('GET', $url));
	$self->log("[info] Request done.\n");
	return $res;
}

sub post {
	my $self = shift;
	my $url  = shift;
	$url     = $self->absolute_url($url);
	$self->log("[info] Post Method '${url}'\n");

	my @form = @_;
	my $req  = (grep {ref($_) eq 'ARRAY'} @form) ?
	           &HTTP::Request::Common::POST($url, Content_Type => 'form-data', Content => [@form]) : 
	           &HTTP::Request::Common::POST($url, [@form]);
	# Do Request
	my $res = $self->request($req);
	$self->log("[info] Request Done.\n");
	return $res;
}

sub response {
	my $self = shift;
	return $self->{'livedoor'}->{'response'};
}

sub absolute_url {
	my $self = shift;
	my $url  = shift;
	return undef unless ($url);
	my $base = (@_) ? shift : $self->{'livedoor'}->{'base'};
	$url     .= '.pl' if ($url and $url !~ /[\/\.]/);
	return URI->new($url)->abs($base)->as_string;
}

sub absolute_linked_url {
	my $self = shift;
	my $url  = shift;
	return $url unless ($url and $self->response());
	my $res  = $self->response();
	my $base = $res->request->uri->as_string;
	return $self->absolute_url($url, $base);
}

sub query_sorted_url {
	my $self = shift;
	my $url  = shift;
	return undef unless ($url);
	if ($url =~ s/\?(.*)$//) {
		my $qurey_string = join('&', map {join('=', @{$_})}
			map { $_->[1] =~ s/%20/+/g if @{$_} == 2; $_; }
			sort {$a->[0] cmp $b->[0]}
			map {[split(/=/, $_, 2)]} split(/&/, $1));
		$url = "$url?$qurey_string";
	}
	return $url;
}

sub enable_cookies {
	my $self = shift;
	unless ($self->cookie_jar) {
		my $cookie = sprintf('cookie_%s_%s.txt', $$, time);
		$self->cookie_jar(HTTP::Cookies->new(file => $cookie, ignore_discard => 1));
		$self->log("[info] Setted Cookie\n");
	}
	return $self;
}

sub save_cookies {
	my $self = shift;
	my $file = shift;
	my $info = '';
	my $result = 0;
	if (not $self->cookie_jar) {
		$info = "[error] cannot use Cookie\n";
	} elsif (not $file) {
		$info = "[error] Nothing cookie file name\n";
	} else {
		$info = "[info] Save to Cookie '${file}'\n";
		$result = eval "\$self->cookie_jar->save(\$file)";
		$info .= "[error] $@\n" if ($@);
	}
	return $result;
}

sub load_cookies {
	my $self = shift;
	my $file = shift;
	my $info = '';
	my $result = 0;
	if (not $file){ 
		$info = "[error] Cookie filename Nothing..\n";
	} elsif (not $file) {
		$info = "[error] Cookie-File is nothing '${file}'\n";
	} else {
		$info = "[info] Load Cookie data from '${file}'\n";
		$self->enable_cookies;
		$result = eval "\$self->cookie_jar->load(\$file)";
		$info .= "[error] $@\n" if ($@);
	}
	return $result;
}

sub log {
	my $self = shift;
	return &{$self->{'livedoor'}->{'log'}}($self, @_);
}

sub dumper_log {
	my $self = shift;
	my @logs = @_;
	if (not defined($self->{'livedoor'}->{'dumper'})) {
		eval "use Data::Dumper";
		$self->{'livedoor'}->{'dumper'} = ($@) ? 0 : Data::Dumper->can('Dumper');
		$self->log("[warn] Data::Dumper is not available : $@\n") unless ($self->{'livedoor'}->{'dumper'});
	}
	if ($self->{'livedoor'}->{'dumper'}) {
		local $Data::Dumper::Indent = 1;
		my $log = &{$self->{'livedoor'}->{'dumper'}}([@logs]);
		$log =~ s/\n/\n  /g;
		$log =~ s/\s+$/\n/s;
		return $self->log("  $log");
	} else {
		return $self->log("  [dumper] " . join(', ', @logs) . "\n");
	}
}

sub abort {
	my $self = shift;
	return &{$self->{'livedoor'}->{'abort'}}($self, @_);
}

sub callback_log {
	eval "use Jcode";
	my $use_jcode = ($@) ? 0 : 1;
	my $self  = shift;
	my @logs  = @_;
	my $error = 0;
	foreach my $log (@logs) {
		eval '$log = jcode($log, "euc")->sjis' if ($use_jcode);
		if    ($log !~ /^(\s|\[.*?\])/) { print $log; }
		elsif ($log =~ /^\[error\]/)    { print $log; $error = 1; }
		elsif ($log =~ /^\[usage\]/)    { print $log; }
		elsif ($log =~ /^\[warn\]/)     { print $log; }
	}
	$self->abort if ($error);
	return $self;
}

sub callback_abort {
	die;
}

sub rewrite {
	my $self = shift;
	return &{$self->{'livedoor'}->{'rewrite'}}($self, @_);
}

sub callback_rewrite {
	my $self = shift;
	my $str  = shift;
	$str = $self->remove_tag($str);
	$str = $self->unescape($str);
	return $str;
}

sub escape {
	my $self = shift;
	my $str  = shift;
	my %escaped = ('&' => '&amp;', '"' => '&quot;', '>' => '&gt;', '<' => '&lt;');
	my $re_target = join('|', keys(%escaped));
	$str =~ s/($re_target)/$escaped{$1}/g;
	return $str;
}

sub unescape {
	my $self = shift;
	my $str  = shift;
	my %unescaped = ('amp' => '&', 'quot' => '"', 'gt' => '>', 'lt' => '<', 'nbsp' => ' ', 'apos' => "'", 'copy' => '(c)');
	my $re_target = join('|', keys(%unescaped));
	$str =~ s[&(.*?);]{
		local $_ = lc($1);
		/^($re_target)$/  ? $unescaped{$1} :
		/^#x([0-9a-f]+)$/ ? chr(hex($1)) :
		$_
	}gex;
	return $str;
}


sub redirect_ok {
	return 1;
}

package WWW::Livedoor::RobotRules;
use vars qw($VERSION @ISA);
require WWW::RobotRules;
@ISA = qw(WWW::RobotRules::InCore);

$VERSION = sprintf("%d.%02d", q$Revision: 0.01 $ =~ /(\d+)\.(\d+)/);

sub allowed {
	return 1;
}

1;

=head1 NAME

WWW::Livedoor - LWP::UserAgent module for Livedoor.com

=head1 SYNOPSIS

  use HTTP::Request::Common;
  use WWW::Livedoor;
  use strict;

## Login livedoor.com using livedoor_id & password
  my $livedoor= WWW::Livedoor->new('[livedoor_id]', '[password]');
     $livedoor->login;

## Getting Any Logined Page
  my $res = $livedoor->get('http://frepa.livedoor.com');
     $res->content; ## result

## POST Any Query And Get the Result
  my @form = ('k' => 'search',
              'q' => 'test');

  my $req = &HTTP::Request::Common::POST("http://search.livedoor.com/search/",[@form]);
  my $res = $livedoor->request($req);
     $res->content; ## result

=head1 DESCRIPTION

WWW::Livedoor uses LWP::RobotUA to scrape livedoor.com
This provide login method, get and put method, and some parsing method for user who create livedoor spider.

=head1 SEE ALSO

L<LWP::UserAgent>, L<WWW::RobotUA>, L<HTTP::Request::Common>

=head1 AUTHORS

WWW::Livedoor is written by http://satoru.net <sayano@cpan.org>


=head1 COPYRIGHT

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

