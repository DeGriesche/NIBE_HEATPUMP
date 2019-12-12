package main;
use strict;
use warnings;
use JSON;
use Encode;
use HttpUtils;
use Scalar::Util qw(looks_like_number);
use Date::Parse;

my $apiBaseUrl = 'https://api.nibeuplink.com/api/v1';

my %parameter = (
	"40004" => "aussenTemp",
	"40067" => "mittlAussenTemp",
	"48132" => "voruebergLuxus",
	"47041" => "komfortmodus",
	"40014" => "brauchwasserbereitung",
	"47260" => "ventilationsdrehz",
	"40025" => "abluftTemp",
	"40026" => "fortluftTemp",
	"40008" => "vorlaufTemp",
	"40012" => "ruecklaufTemp",
	"43420" => "betriebszeitVerdichter",
	"43424" => "betriebszeitVerdichterBW"
);

sub NIBE_HEATPUMP_Initialize($) {
    my ($hash) = @_;

    $hash->{DefFn}      = 'NIBE_HEATPUMP_Define';
    $hash->{UndefFn}    = 'NIBE_HEATPUMP_Undef';
    $hash->{SetFn}      = 'NIBE_HEATPUMP_Set';
    $hash->{AttrFn}     = 'NIBE_HEATPUMP_Attr';

    $hash->{AttrList} = "systemId refreshInterval ".$readingFnAttributes;
}

sub NIBE_HEATPUMP_Define($$) {
    my ($hash, $def) = @_;
    my @param = split('[ \t]+', $def);
    
	if(int(@param) != 4) {
    	return "wrong number of parameters: define <name> NIBE_HEATPUMP <clientId> <clientSecret>";
    }
	
	$hash->{name}  = $param[0];
	$hash->{clientId} = $param[2];
	$hash->{clientSecret} = $param[3];    
	$hash->{accessCodeUrl} = "https://api.nibeuplink.com/oauth/authorize?response_type=code&client_id=".$hash->{clientId}."&scope=WRITESYSTEM+READSYSTEM&redirect_uri=https://www.marshflattsfarm.org.uk/nibeuplink/oauth2callback/index.php&state=STATE";
	$attr{$hash->{NAME}}{refreshInterval} = 10;

    return undef;
}

sub NIBE_HEATPUMP_Undef($$) {
	my ( $hash, $name) = @_;       
	DevIo_CloseDev($hash);         
	RemoveInternalTimer($hash);    
	return undef;
}

sub NIBE_HEATPUMP_Delete ($$) {
	my ( $hash, $name ) = @_;
	# nothing to do
	return undef;
}

sub NIBE_HEATPUMP_Set($@) {
	print "SET\n";
	my ( $hash, $name, $cmd, @args ) = @_;

	if (!exists $hash->{access_token}) {
		if ($cmd eq "accessCode") {
			NIBE_HEATPUMP_requestToken($hash, @args[0]);
		} else {
			return "Unknown argument $cmd, choose one of accessCode" ;
		}
	} elsif (!exists $attr{$name}{systemId}) {
		if ($cmd eq "systemId") {
			$attr{$name}{systemId} = @args[0];
			InternalTimer(gettimeofday() + $attr{$hash->{NAME}}{refreshInterval}, "NIBE_HEATPUMP_refresh", $hash);
		} else {
			return "Unknown argument $cmd, choose one of systemId" ;
		}			
	} else {	
		return "Attribute systemId is undefined" unless($cmd eq "systemId" || $cmd eq "?" || exists $attr{$name}{systemId});
		return "\"set $name\" needs at least one argument" unless(defined($cmd));

		if ($cmd eq "refresh") {
			print "COMMAND REFRESH\n";
			NIBE_HEATPUMP_refresh($hash);
		} elsif ($cmd eq "mode") {
			if ($args[0] =~ m/(DEFAULT_OPERATION|AWAY_FROM_HOME|VACATION)/) {
				NIBE_HEATPUMP_setSmartHomeMode($hash, $args[0]);
			} else {
				return "Unknown value $args[0] for $cmd, choose one of DEFAULT_OPERATION AWAY_FROM_HOME VACATION";
			}
		} else {
			return "Unknown argument $cmd, choose one of mode:DEFAULT_OPERATION,AWAY_FROM_HOME,VACATION refresh:noArg systemId";
		}
	}
}

sub NIBE_HEATPUMP_Attr(@) {
	my ($cmd,$name,$attr_name,$attr_value) = @_;
	if($cmd eq "set") {
        if($attr_name eq "systemId") {
			if(length($attr_value) ne 5 || !looks_like_number($attr_value)) {
			    my $err = "Invalid argument $attr_value to $attr_name. Must be numeric with 5 digits.";
			    Log 3, "Hello: ".$err;
			    return $err;
			}
		} else {
		    return "Unknown attr $attr_name";
		}
	}
	return undef;
}

sub NIBE_HEATPUMP_getToken($) {
	my ($hash) = @_;
	
	if ($hash->{token_expiration} <= time()) {
		NIBE_HEATPUMP_refreshToken($hash);
	}
	
	return $hash->{access_token};
}

sub NIBE_HEATPUMP_getSystemId($) {
	my ($hash) = @_;
	my $name = $hash->{name};
	if (!exists($attr{$name}{systemId})) {
		
		return undef;
	}
}

sub NIBE_HEATPUMP_saveToken($$$) {
	print "SAVE TOKEN\n";
	my ($param, $err, $data) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    if ($err ne "") {
        Log3 $name, 3, "error while requesting ".$param->{url}." - $err";
    } elsif ($data ne "") {
		my $decoded = decode_json($data);
		my $expTime = time() - 10 + $decoded->{expires_in};
	
		$hash->{access_token} = $decoded->{access_token};
		$hash->{refresh_token} = $decoded->{refresh_token};
		$hash->{token_expiration} = $expTime;
    }
}

sub NIBE_HEATPUMP_requestToken($$) {
	Log 1, "REQUEST TOKEN";
	
	my ($hash, $accessCode) = @_;
	#my $accessCode= $hash->{accessCode};
	chomp $accessCode;
	my %urlParams = (
		"grant_type" 		=> "authorization_code",
		"client_id" 		=> urlEncode($hash->{clientId}),
		"client_secret" 	=> urlEncode($hash->{clientSecret}),
		"code"			=> urlEncode($accessCode),
		"redirect_uri"	 	=> "https://www.marshflattsfarm.org.uk/nibeuplink/oauth2callback/index.php",
		"scope" 		=> "READSYSTEM+WRITESYSTEM"
	);
		
	my $param = {
		url        => "https://api.nibeuplink.com/oauth/token",
		timeout    => 5,
		hash       => $hash, # Muss gesetzt werden, damit die Callback funktion wieder $hash hat
		method     => "POST",
		header     => "Content-Type: application/x-www-form-urlencoded;charset=UTF-8",
		data		=> join("&", map { "$_=$urlParams{$_}" } keys %urlParams),
		callback   => \&NIBE_HEATPUMP_saveToken
	};

	HttpUtils_NonblockingGet($param);
}

sub NIBE_HEATPUMP_refreshToken($) {
	Log 1, "REFRESH TOKEN\n";
	my ($hash) = @_;
	my $refreshToken = $hash->{refresh_token};
	
	my %urlParams = (
		"grant_type" 	=> "refresh_token",
		"client_id" 	=> urlEncode($hash->{clientId}),
		"client_secret" => urlEncode($hash->{clientSecret}),
		"refresh_token"	=> $refreshToken
	);
	my $param = {
		url        => "https://api.nibeuplink.com/oauth/token",
		timeout    => 5,
		hash       => $hash, 
		method     => "POST",
		header     => "Content-Type: application/x-www-form-urlencoded;charset=UTF-8",
		data		=> join("&", map { "$_=$urlParams{$_}" } keys %urlParams),
		callback   => \&NIBE_HEATPUMP_saveToken
	};

	my ($err, $data) = HttpUtils_BlockingGet($param);
	NIBE_HEATPUMP_saveToken(("hash" => $hash), $err, $data);
}

sub NIBE_HEATPUMP_refresh($) {
	my ($hash) = @_;
	InternalTimer(gettimeofday() + $attr{$hash->{NAME}}{refreshInterval}, "NIBE_HEATPUMP_refresh", $hash);
}

sub NIBE_HEATPUMP_refreshSmartHomeMode($) {
	print "REFRESH SMARTHOME MODE\n";
    my ($hash) = @_;
	my $name = $hash->{NAME};
	my $param = {
		url        => "$apiBaseUrl/systems/".$attr{$name}{systemId}."/smarthome/mode",
		timeout    => 5,
		hash       => $hash, 
		method     => "GET",
		header     => "Authorization: Bearer ".NIBE_HEATPUMP_getToken($hash),
		callback   => sub($) {
						my ($param, $err, $data) = @_;
  						my $hash = $param->{hash};
    					if ($err ne "") {
        					Log3 $hash->{NAME}, 3, "error while requesting ".$param->{url}." - $err";
    					} elsif ($data ne "") {
							my $decoded = decode_json($data);
							readingsSingleUpdate($hash, "mode", $decoded->{'mode'}, 1);
							$hash->{STATE} = $decoded->{'mode'};
						}
					}
	};
	HttpUtils_NonblockingGet($param);
}

sub NIBE_HEATPUMP_refreshParameters($) {
	print "REFRESH PARAMETER\n";
    my ($hash) = @_;
	my $name = $hash->{NAME};
	my $param = {
		url        => "$apiBaseUrl/systems/".$attr{$name}{systemId}."/parameters?parameterIds=".join("&parameterIds=", keys %parameter),
		timeout    => 5,
		hash       => $hash, 
		method     => "GET",
		header     => "Authorization: Bearer ".NIBE_HEATPUMP_getToken($hash),
		callback   => sub($) {
						my ($param, $err, $data) = @_;
  						my $hash = $param->{hash};
    					if ($err ne "") {
        					Log3 $hash->{NAME}, 3, "error while requesting ".$param->{url}." - $err";
    					} elsif ($data ne "") {
							#print $data."\n";
							readingsBeginUpdate($hash);
							my $decoded = decode_json($data);
							for my $hashref (@{ $decoded }) {
								my $parameterId = $hashref->{ 'parameterId' };
								my $parameterValue = $hashref->{ 'rawValue' };
								my $parameterUnit = $hashref->{ 'unit' };

								if ($parameterUnit eq "°C") {
									$parameterValue = $parameterValue / 10;
								}
								
								readingsBulkUpdate($hash, $parameter{$parameterId}, $parameterValue);
							}
							readingsEndUpdate($hash, 1);
						}
					}
	};
	HttpUtils_NonblockingGet($param);
}

sub NIBE_HEATPUMP_setSmartHomeMode($$) {
	print "SET SMARTHOME MODE\n";
    my ($hash, $value) = @_;
	my $name = $hash->{NAME};
	my $json = '{ "mode": "'.$value.'" }';
	my $param = {
		url        => "$apiBaseUrl/systems/".$attr{$name}{systemId}."/smarthome/mode",
		timeout    => 5,
		hash       => $hash, 
		method     => "PUT",
		data	   => $json,
		header     => "Authorization: Bearer ".NIBE_HEATPUMP_getToken($hash)."\nContent-Type: application/json",
		callback   => sub($) {
						my ($param, $err, $data) = @_;
  						my $hash = $param->{hash};
    					if ($err ne "") {
        					Log3 $hash->{NAME}, 3, "error while requesting ".$param->{url}." - $err";
    					} elsif ($data ne "") {
							print $data."\n";
						}
					}
	};
	HttpUtils_NonblockingGet($param);
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

1;

=pod
=begin html

<a name="NIBE_HEATPUMP"></a>
<h3>NIBE_HEATPUMP</h3>
<ul>
    <i>NIBE_HEATPUMP</i> implements the classical "Hello World" as a starting point for module development. 
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
