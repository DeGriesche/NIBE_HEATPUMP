package main;
use strict;
use warnings;
use JSON;
use Encode;
use LWP::Authen::OAuth2;

my $filename = 'C:/Users/601457/Desktop/.NIBE_Uplink_API_Tokens.json';
my $apiBaseUrl = 'https://api.nibeuplink.com/api/v1';
my $oauth2;
my @opts = ("mode");

sub NIBE_HEATPUMP_Initialize($) {
    my ($hash) = @_;

    $hash->{DefFn}      = 'NIBE_HEATPUMP_Define';
    $hash->{UndefFn}    = 'NIBE_HEATPUMP_Undef';
    $hash->{SetFn}      = 'NIBE_HEATPUMP_Set';
    $hash->{GetFn}      = 'NIBE_HEATPUMP_Get';
    $hash->{AttrFn}     = 'NIBE_HEATPUMP_Attr';
    $hash->{ReadFn}     = 'NIBE_HEATPUMP_Read';

    $hash->{AttrList} = "systemId mode:DEFAULT_OPERATION,AWAY_FROM_HOME,VACATION ".$readingFnAttributes;
}

sub NIBE_HEATPUMP_Define($$) {
    my ($hash, $def) = @_;
    my @param = split('[ \t]+', $def);
    
	if(int(@param) < 3) {
        return "wrong number of parameters: define <name> NIBE_HEATPUMP <clientId> <clientSecret> <authCode>";
    }
	
	$hash->{name}  = $param[0];
	$hash->{clientId}  = $param[2];
	
    if(int(@param) > 5) {
        return "wrong number of parameters: define <name> NIBE_HEATPUMP <clientId> <clientSecret> <authCode> \n Generate authCode via https://api.nibeuplink.com/oauth/authorize?response_type=code&client_id=".$hash->{clientId}."&scope=WRITESYSTEM+READSYSTEM&redirect_uri=https://www.marshflattsfarm.org.uk/nibeuplink/oauth2callback/index.php&state=STATE";
    }
    
	$hash->{clientSecret}  = $param[3];    
	$hash->{authCode}  = $param[4];

	requestToken($hash);

    return undef;
}

sub NIBE_HEATPUMP_Undef($$) {
    my ($hash, $arg) = @_; 
    # nothing to do
    return undef;
}

sub NIBE_HEATPUMP_Delete ($$) {
	my ( $hash, $name ) = @_;
	# nothing to do
	return $undef;
}


sub NIBE_HEATPUMP_Get($@) {
	my ( $hash, $name, $opt, @args ) = @_;
	
	return "\"get $name\" needs at least one argument" unless(defined($opt));
	
	if($opt eq "mode") {
		return getSmartHomeMode($attr{$name}{systemId};
	} else {
		return "Unknown argument $opt, choose one of ".join(@opts, " ");
	}
}

sub NIBE_HEATPUMP_Set($@) {
	my ( $hash, $name, $cmd, @args ) = @_;
	
	return "\"set $name\" needs at least one argument" unless(defined($cmd));

	if ($cmd eq "mode") {
		if ($args[0] eq "DEFAULT_OPERATION") {
			# DEFAULT_OPERATION
		} elsif ($args[0] eq "AWAY_FROM_HOME") {
			# 
		} elsif ($args[0] eq "VACATION") {
			# 
		} else {
			return "Unknown value $args[0] for $cmd, choose one of DEFAULT_OPERATION AWAY_FROM_HOME VACATION";
		}
	} else {
		return "Unknown argument $cmd, choose one of ".join(@opts, " ");
	}
}

sub NIBE_HEATPUMP_Attr(@) {
	my ($cmd,$name,$attr_name,$attr_value) = @_;
	if($cmd eq "set") {
        if($attr_name eq "formal") {
			if($attr_value !~ /^yes|no$/) {
			    my $err = "Invalid argument $attr_value to $attr_name. Must be yes or no.";
			    Log 3, "Hello: ".$err;
			    return $err;
			}
		} else {
		    return "Unknown attr $attr_name";
		}
	}
	return undef;
}

sub save_tokens($) {
	my ($hash) = @_;
	$hash->{token} = shift;
}

sub requestToken($) {
	my ($hash) = @_;
	my $oauth2 = LWP::Authen::OAuth2->new(
		client_id => $hash->{clientId},
		client_secret => $hash->{clientSecret},
		token_endpoint => 'https://api.nibeuplink.com/oauth/token',
		redirect_uri => 'https://www.marshflattsfarm.org.uk/nibeuplink/oauth2callback/index.php',
		request_required_params => [ 'redirect_uri', 'state', 'scope', 'grant_type', 'client_id', 'client_secret', 'code' ],
		scope => 'READSYSTEM+WRITESYSTEM',
		save_tokens => \&save_tokens
	);

	print "Create a new Authorization Code and enter (copy-and-paste) it here\n";
	my $code = $hash->{authCode};
	chomp $code;

	$oauth2->request_tokens(
		code=> $code,
		state => 'STATE'
	);
}

sub oauth2($) {
	my ($hash) = @_;
	if (!$oauth2) {
		print "INITIALIZE\n";
	
		# Read saved token_string
		my $token_string = $hash->{token};
		print token_string;

		# Construct the OAuth2 object
		$oauth2 = LWP::Authen::OAuth2->new(
			client_id => $hash->{clientId},
			client_secret => $hash->{clientSecret},
			token_endpoint => 'https://api.nibeuplink.com/oauth/token',
			redirect_uri => 'https://www.marshflattsfarm.org.uk/nibeuplink/oauth2callback/index.php',
			request_required_params => [ 'redirect_uri', 'state', 'scope', 'grant_type', 'client_id', 'client_secret', 'code' ],
			scope => 'READSYSTEM+WRITESYSTEM',
			token_string => $token_string,
			save_tokens => \&save_tokens
		);
	}
	
	return $oauth2;
}

sub getSystemsIds() {
	my $url = "$apiBaseUrl/systems";
	my $response = oauth2->get($url);
	if ( $response->is_error ) { 
		print $response->error_as_HTML;
	}
	if ( $response->is_success ) {
		#print $response->content."\n";
		my $decoded = decode_json( $response->content );
		my $objects = $decoded->{ 'objects' };
		my @result;
		for my $hashref ( @ { $objects } ) {
			my $systemId = $hashref->{ 'systemId' };
			push @result, $systemId;
		}
		return @result;
	}
}

sub getSystem($) {
	my ($systemId) = @_;
	my $url = "$apiBaseUrl/systems/$systemId";
	my $response = oauth2->get($url);
	if ( $response->is_error ) { 
		print $response->error_as_HTML;
	}
	if ( $response->is_success ) {
		#print $response->content."\n";
		return % { decode_json(encode_utf8($response->content)) };
	}
}

sub getSmartHomeMode($) {
	my ($systemId) = @_;
	my $url = "$apiBaseUrl/systems/$systemId/smarthome/mode";
	my $response = oauth2->get( $url );
	if ( $response->is_error ) { 
		print $response->error_as_HTML; 
	}
	if ( $response->is_success ) {
		#print $response->content."\n";
		my $decoded = decode_json( $response->content );
		return $decoded->{'mode'};
	}
}

sub setSmartHomeMode($$) {
	my ($systemId, $value) = @_;
	my $url = "$apiBaseUrl/systems/$systemId/smarthome/mode";
	my $json = '{ "mode": "'.$value.'" }';
	my $response = oauth2->put( $url, "Content-Type" => "application/json", "Content" => $json );
	if ( $response->is_error ) { 
		print $response->error_as_HTML; 
	}
	if ( $response->is_success ) {
		print $response->content."\n";
	}
}

sub getConfig($) {
	my ($systemId) = @_;
	my $url = "$apiBaseUrl/systems/$systemId/config";
	my $response = oauth2->get( $url );
	if ( $response->is_error ) { 
		print $response->error_as_HTML; 
	}
	if ( $response->is_success ) {
		#print $response->content."\n";
		return % { decode_json(encode_utf8($response->content)) };
	}
}

sub getParameter($@) {
	my ($systemId, @parameterIds) = @_;
	my $url = "$apiBaseUrl/systems/$systemId/parameters?parameterIds=".join("&parameterIds=", @parameterIds);
	my $response = oauth2->get( $url );
	if ( $response->is_error ) { 
		print $response->error_as_HTML;
	}
	if ( $response->is_success ) {
		#print $response->content."\n";
		my $decoded = decode_json(encode_utf8($response->content));
		return @ { $decoded };
    }  
}

sub setParameter($$$) {
	my ($systemId, $parameterId, $value) = @_;
	my $url = "$apiBaseUrl/systems/$systemId/parameters";
	my $json = '{ "settings": { "'.$parameterId.'": "'.$value.'" }}';
	print $json."\n";
	my $response = oauth2->put( $url, "Content-Type" => "application/json", "Content" => $json );
	if ( $response->is_error ) { 
		print $response->error_as_HTML;
	}
	if ( $response->is_success ) {
		print $response->content."\n";
	}
}

1;

=pod
=begin html

<a name="NIBE_HEATPUMP"></a>
<h3>NIBE_HEATPUMP</h3>
<ul>
    <i>Hello</i> implements the classical "Hello World" as a starting point for module development. 
    You may want to copy 98_Hello.pm to start implementing a module of your very own. See 
    <a href="http://wiki.fhem.de/wiki/DevelopmentModuleIntro">DevelopmentModuleIntro</a> for an 
    in-depth instruction to your first module.
    <br><br>
    <a name="Hellodefine"></a>
    <b>Define</b>
    <ul>
        <code>define &lt;name&gt; Hello &lt;greet&gt;</code>
        <br><br>
        Example: <code>define HELLO Hello TurnUrRadioOn</code>
        <br><br>
        The "greet" parameter has no further meaning, it just demonstrates
        how to set a so called "Internal" value. See <a href="http://fhem.de/commandref.html#define">commandref#define</a> 
        for more info about the define command.
    </ul>
    <br>
    
    <a name="Helloset"></a>
    <b>Set</b><br>
    <ul>
        <code>set &lt;name&gt; &lt;option&gt; &lt;value&gt;</code>
        <br><br>
        You can <i>set</i> any value to any of the following options. They're just there to 
        <i>get</i> them. See <a href="http://fhem.de/commandref.html#set">commandref#set</a> 
        for more info about the set command.
        <br><br>
        Options:
        <ul>
              <li><i>satisfaction</i><br>
                  Defaults to "no"</li>
              <li><i>whatyouwant</i><br>
                  Defaults to "can't"</li>
              <li><i>whatyouneed</i><br>
                  Defaults to "try sometimes"</li>
        </ul>
    </ul>
    <br>

    <a name="Helloget"></a>
    <b>Get</b><br>
    <ul>
        <code>get &lt;name&gt; &lt;option&gt;</code>
        <br><br>
        You can <i>get</i> the value of any of the options described in 
        <a href="#Helloset">paragraph "Set" above</a>. See 
        <a href="http://fhem.de/commandref.html#get">commandref#get</a> for more info about 
        the get command.
    </ul>
    <br>
    
    <a name="Helloattr"></a>
    <b>Attributes</b>
    <ul>
        <code>attr &lt;name&gt; &lt;attribute&gt; &lt;value&gt;</code>
        <br><br>
        See <a href="http://fhem.de/commandref.html#attr">commandref#attr</a> for more info about 
        the attr command.
        <br><br>
        Attributes:
        <ul>
            <li><i>formal</i> no|yes<br>
                When you set formal to "yes", all output of <i>get</i> will be in a
                more formal language. Default is "no".
            </li>
        </ul>
    </ul>
</ul>

=end html

=cut