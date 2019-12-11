package main;
use strict;
use warnings;
use JSON;
use Encode;
use HttpUtils;
use LWP::Authen::OAuth2;

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
	$hash->{clientId} = $param[2];
	
	print "NAME ".$hash->{name}."\n";
	print "CLIENTID ".$hash->{clientId}."\n";
	
    if(int(@param) < 5) {
        return "wrong number of parameters: define <name> NIBE_HEATPUMP <clientId> <clientSecret> <authCode> \n Generate authCode via https://api.nibeuplink.com/oauth/authorize?response_type=code&client_id=".$hash->{clientId}."&scope=WRITESYSTEM+READSYSTEM&redirect_uri=https://www.marshflattsfarm.org.uk/nibeuplink/oauth2callback/index.php&state=STATE";
    }
    
	$hash->{clientSecret} = $param[3];    
	$hash->{authCode} = $param[4];

	print "SECRET ".$hash->{clientSecret}."\n";
	print "CODE ".$hash->{authCode}."\n";

	NIBE_HEATPUMP_requestToken($hash);

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
	return undef;
}

sub NIBE_HEATPUMP_Get($@) {
	my ( $hash, $name, $opt, @args ) = @_;
	
	return "\"get $name\" needs at least one argument" unless(defined($opt));
	
	if ($opt eq "mode") {
		return getSmartHomeMode($attr{$name}{systemId});
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

sub NIBE_HEATPUMP_saveToken($) {
	my ($hash) = @_;
	$hash->{token} = shift;
	print "TOKEN ".$hash->{token}."\n";
}

sub NIBE_HEATPUMP_ParseHttpResponse($) {
    my ($param, $err, $data) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    if ($err ne "") {
        Log3 $name, 3, "error while requesting ".$param->{url}." - $err";
        readingsSingleUpdate($hash, "fullResponse", "ERROR", 0);
    } elsif ($data ne "") {
        Log3 $name, 3, "url ".$param->{url}." returned: $data";
        # An dieser Stelle die Antwort parsen / verarbeiten mit $data
        #readingsSingleUpdate($hash, "fullResponse", $data, 0);
    }
}

sub NIBE_HEATPUMP_requestToken($) {
	my ($hash) = @_;
	my $code = $hash->{authCode};
	chomp $code;
	my $url = "https://api.nibeuplink.com/oauth/token?grant_type=authorization_code&client_id=".$hash->{clientId}."&client_secret=".$hash->{clientSecret}."code=$code&redirect_uri=https://www.marshflattsfarm.org.uk/nibeuplink/oauth2callback/index.php&scope=READSYSTEM+WRITESYSTEM";
	print "URL $url";
	
	my $param = {
		url        => $url,
		timeout    => 5,
		hash       => $hash, # Muss gesetzt werden, damit die Callback funktion wieder $hash hat
		method     => "POST",
		header     => "Accept: application/json\nContent-Length: 0",
		data	   => "",
		callback   => \&NIBE_HEATPUMP_ParseHttpResponse
	};

	HttpUtils_NonblockingGet($param);
	
	#my $oauth2 = LWP::Authen::OAuth2->new(
	#	client_id => $hash->{clientId},
	#	client_secret => $hash->{clientSecret},
	#	token_endpoint => 'https://api.nibeuplink.com/oauth/token',
	#	redirect_uri => 'https://www.marshflattsfarm.org.uk/nibeuplink/oauth2callback/index.php',
	#	request_required_params => [ 'redirect_uri', 'state', 'scope', 'grant_type', 'client_id', 'client_secret', 'code' ],
	#	scope => 'READSYSTEM+WRITESYSTEM',
	#	save_tokens => \&NIBE_HEATPUMP_saveToken($hash)
	#);

	#my $code = $hash->{authCode};
	#chomp $code;
	
	#$oauth2->request_tokens(
	#	code => $code,
	#	state => 'STATE'
	#);
}

sub NIBE_HEATPUMP_oauth2($) {
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

sub NIBE_HEATPUMP_getSystemsIds($) {
        my ($hash) = @_;
	my $url = "$apiBaseUrl/systems";
	my $response = oauth2($hash)->get($url);
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

sub NIBE_HEATPUMP_getSystem($) {
	my ($hash) = @_;
	my $url = "$apiBaseUrl/systems/".$hash->{systemId};
	my $response = oauth2($hash)->get($url);
	if ( $response->is_error ) { 
		print $response->error_as_HTML;
	}
	if ( $response->is_success ) {
		#print $response->content."\n";
		return % { decode_json(encode_utf8($response->content)) };
	}
}

sub NIBE_HEATPUMP_getSmartHomeMode($) {
	my ($hash) = @_;
	my $url = "$apiBaseUrl/systems/".$hash->{systemId}."/smarthome/mode";
	my $response = oauth2($hash)->get( $url );
	if ( $response->is_error ) { 
		print $response->error_as_HTML; 
	}
	if ( $response->is_success ) {
		#print $response->content."\n";
		my $decoded = decode_json( $response->content );
		return $decoded->{'mode'};
	}
}

sub NIBE_HEATPUMP_setSmartHomeMode($$) {
	my ($hash, $value) = @_;
	my $url = "$apiBaseUrl/systems/".$hash->{systemId}."/smarthome/mode";
	my $json = '{ "mode": "'.$value.'" }';
	my $response = oauth2($hash)->put( $url, "Content-Type" => "application/json", "Content" => $json );
	if ( $response->is_error ) { 
		print $response->error_as_HTML; 
	}
	if ( $response->is_success ) {
		print $response->content."\n";
	}
}

sub NIBE_HEATPUMP_getConfig($) {
	my ($hash) = @_;
	my $url = "$apiBaseUrl/systems/".$hash->{systemId}."/config";
	my $response = oauth2($hash)->get( $url );
	if ( $response->is_error ) { 
		print $response->error_as_HTML; 
	}
	if ( $response->is_success ) {
		#print $response->content."\n";
		return % { decode_json(encode_utf8($response->content)) };
	}
}

sub getParameter($@) {
	my ($hash, @parameterIds) = @_;
	my $url = "$apiBaseUrl/systems/".$hash->{systemId}."/parameters?parameterIds=".join("&parameterIds=", @parameterIds);
	my $response = oauth2($hash)->get( $url );
	if ( $response->is_error ) { 
		print $response->error_as_HTML;
	}
	if ( $response->is_success ) {
		#print $response->content."\n";
		my $decoded = decode_json(encode_utf8($response->content));
		return @ { $decoded };
    }  
}

sub NIBE_HEATPUMP_setParameter($$$) {
	my ($hash, $parameterId, $value) = @_;
	my $url = "$apiBaseUrl/systems/".$hash->{systemId}."/parameters";
	my $json = '{ "settings": { "'.$parameterId.'": "'.$value.'" }}';
	print $json."\n";
	my $response = oauth2($hash)->put( $url, "Content-Type" => "application/json", "Content" => $json );
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
