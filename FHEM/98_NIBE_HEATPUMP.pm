package main;
use strict;
use warnings;
use JSON;
use Encode;
use HttpUtils;
use Scalar::Util qw(looks_like_number);

my $apiBaseUrl = 'https://api.nibeuplink.com/api/v1';
my $oauthTokenBaseUrl = 'https://api.nibeuplink.com/oauth/token';
my $redirectUrl	= "https://www.marshflattsfarm.org.uk/nibeuplink/oauth2callback/index.php";
my $apiTimeout = 20;

my %parameter = (
	"10012" => "verdichterBlockiert",
	#"10033" => "zhBlockiert",
	"40004" => "aussenTemp",
	"40008" => "vorlaufTemp",
	"40012" => "ruecklaufTemp",
	"40013" => "brauchwasserOben",
	"40014" => "brauchwasserbereitung",
	"40025" => "abluftTemp",
	"40026" => "fortluftTemp",
	"40067" => "mittlAussenTemp",
	"43005" => "gradminuten",
	"43420" => "betriebszeitVerdichter",
	"43424" => "betriebszeitVerdichterBW",
	"47011" => "vorlaufIndex",
	"47041" => "komfortmodus",
	"47260" => "ventilationsdrehz"
);

sub NIBE_HEATPUMP_Initialize($) {
    my ($hash) = @_;

    $hash->{DefFn}      = 'NIBE_HEATPUMP_Define';
    $hash->{UndefFn}    = 'NIBE_HEATPUMP_Undef';
    $hash->{SetFn}      = 'NIBE_HEATPUMP_Set';
    $hash->{AttrFn}     = 'NIBE_HEATPUMP_Attr';

    $hash->{AttrList} = "systemId refreshInterval debugMode:0,1 maxNotifications ".$readingFnAttributes;
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
	$hash->{accessCodeUrl} = "https://api.nibeuplink.com/oauth/authorize?response_type=code&client_id=".$hash->{clientId}."&scope=WRITESYSTEM+READSYSTEM&redirect_uri=$redirectUrl&state=STATE";
	$attr{$hash->{NAME}}{refreshInterval} = 600;
	$attr{$hash->{NAME}}{debugMode} = 0;
	$attr{$hash->{NAME}}{maxNotifications} = 10;
	$attr{$hash->{NAME}}{devStateIcon} = "DEFAULT_OPERATION:rc_HOME AWAY_FROM_HOME:user_away VACATION:user_ext_away";
	$attr{$hash->{NAME}}{icon} = "sani_buffer_temp_all";

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
	my ( $hash, $name, $cmd, @args ) = @_;
	
	return "\"set $name\" needs at least one argument" unless(defined($cmd));

	if (ReadingsVal($name, ".access_token", 0) != 0) {
		if ($cmd eq "accessCode") {
			NIBE_HEATPUMP_requestToken($hash, $args[0]);
		} else {
			return "Unknown argument $cmd, choose one of accessCode" ;
		}
	} elsif (!exists $attr{$name}{systemId}) {
		if ($cmd eq "systemId") {
			$attr{$name}{systemId} = $args[0];
			InternalTimer(gettimeofday() + $attr{$hash->{NAME}}{refreshInterval}, "NIBE_HEATPUMP_refresh", $hash);
		} else {
			return "Unknown argument $cmd, choose one of systemId" ;
		}			
	} else {	
		if ($cmd eq "refresh") {
			NIBE_HEATPUMP_refresh($hash);
		} elsif ($cmd eq "mode") {
			if ($args[0] =~ m/(DEFAULT_OPERATION|AWAY_FROM_HOME|VACATION)/) {
				NIBE_HEATPUMP_setSmartHomeMode($hash, $args[0]);
			} else {
				return "Unknown value $args[0] for $cmd, choose one of DEFAULT_OPERATION AWAY_FROM_HOME VACATION";
			}
		} else {
			return "Unknown argument $cmd, choose one of mode:DEFAULT_OPERATION,AWAY_FROM_HOME,VACATION refresh:noArg";
		}
	}
}

sub NIBE_HEATPUMP_Attr(@) {
	my ($cmd,$name,$attr_name,$attr_value) = @_;
	if($cmd eq "set") {
        if($attr_name eq "systemId") {
			if(length($attr_value) ne 5 || !looks_like_number($attr_value)) {
			    my $err = "Invalid argument $attr_value to $attr_name. Must be numeric with 5 digits";
			    Log3 $name, 3, $err;
			    return3 $err;
			}
		} elsif ($attr_name =~ m/(refreshInterval|maxNotifications)/) {
			if(!looks_like_number($attr_value)) {
			    my $err = "Invalid argument $attr_value to $attr_name. Must be numeric";
			    Log3 $name, 3, $err;
			    return $err;
			}
		} 	
	}
	return undef;
}

sub NIBE_HEATPUMP_getToken($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	
	if (ReadingsVal($name, ".token_expiration", 0) <= time()) {
		NIBE_HEATPUMP_refreshToken($hash);
	}
	
	return ReadingsVal($name, ".access_token", 0);
}

sub NIBE_HEATPUMP_saveToken($$$) {
	my ($hash, $err, $data) = @_;
    my $name = $hash->{NAME};
	Log3 $name, 1, "Saving Token" if ($attr{$name}{debugMode});

    if ($err ne "") {
        Log3 $name, 3, "error while requesting - $err";
    } elsif ($data ne "") {
		my $decoded = decode_json($data);
		if (exists $decoded->{error}) {
			Log3 $name, 3, "error while requesting - ".$decoded->{error};
		} else {
			readingsBeginUpdate($hash);
			readingsBulkUpdate($hash, ".access_token", $decoded->{access_token} );
			readingsBulkUpdate($hash, ".refresh_token", $decoded->{refresh_token} );
			readingsBulkUpdate($hash, ".token_expiration", time() - 10 + $decoded->{expires_in});
			readingsEndUpdate($hash, 1);
			Log3 $name, 1, "Got new Token" if ($attr{$name}{debugMode});
		}
    }
}

sub NIBE_HEATPUMP_requestToken($$) {
	my ($hash, $accessCode) = @_;
	my $name = $hash->{NAME};
	Log3 $name, 1, "Requesting Token" if ($attr{$name}{debugMode});
	
	chomp $accessCode;
	my %urlParams = (
		"grant_type" => "authorization_code",
		"client_id" => urlEncode($hash->{clientId}),
		"client_secret" => urlEncode($hash->{clientSecret}),
		"code" => urlEncode($accessCode),
		"redirect_uri" => $redirectUrl,
		"scope" => "READSYSTEM+WRITESYSTEM"
	);
		
	my $param = {
		url => $oauthTokenBaseUrl,
		timeout => 5,
		method => "POST",
		header => "Content-Type: application/x-www-form-urlencoded;charset=UTF-8",
		data => join("&", map { "$_=$urlParams{$_}" } keys %urlParams)
	};

	my ($err, $data) = HttpUtils_BlockingGet($param);
	NIBE_HEATPUMP_saveToken($hash, $err, $data);
}

sub NIBE_HEATPUMP_refreshToken($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	Log3 $name, 1, "Refreshing Token" if ($attr{$name}{debugMode});
	
	my %urlParams = (
		"grant_type" => "refresh_token",
		"client_id" => urlEncode($hash->{clientId}),
		"client_secret" => urlEncode($hash->{clientSecret}),
		"refresh_token" => ReadingsVal($name, ".refresh_token", "")
	);
	my $param = {
		url => $oauthTokenBaseUrl,
		timeout => 5,
		method => "POST",
		header => "Content-Type: application/x-www-form-urlencoded;charset=UTF-8",
		data => join("&", map { "$_=$urlParams{$_}" } keys %urlParams)
	};

	my ($err, $data) = HttpUtils_BlockingGet($param);
	NIBE_HEATPUMP_saveToken($hash, $err, $data);
}

sub NIBE_HEATPUMP_refresh($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	Log3 $name, 1, "Refresh" if ($attr{$name}{debugMode});
						
	my $nextRefresh = gettimeofday() + $attr{$name}{refreshInterval};
	readingsSingleUpdate($hash, "nextRefresh", FmtDateTime($nextRefresh), 1);
	InternalTimer($nextRefresh, "NIBE_HEATPUMP_refresh", $hash);
	
	NIBE_HEATPUMP_refreshSmartHomeMode($hash);
	NIBE_HEATPUMP_refreshParameters($hash);
	NIBE_HEATPUMP_refreshConfig($hash);
	NIBE_HEATPUMP_refreshNotifications($hash);
}

sub NIBE_HEATPUMP_refreshSmartHomeMode($) {
    my ($hash) = @_;
	my $name = $hash->{NAME};
	Log3 $name, 1, "Refresh SmartHome mode" if ($attr{$name}{debugMode});

	my $param = {
		url        => "$apiBaseUrl/systems/".$attr{$name}{systemId}."/smarthome/mode",
		timeout    => $apiTimeout,
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
							eval {
								readingsSingleUpdate($hash, "mode", $decoded->{'mode'}, 1);
								$hash->{STATE} = $decoded->{'mode'};
							} or do {
								my $e = $@;
								Log3 $hash->{NAME}, 3, "error while requesting ".$param->{url}." - $e";
							};
						}
					}
	};
	HttpUtils_NonblockingGet($param);
}

sub NIBE_HEATPUMP_refreshParameters($) {
    my ($hash) = @_;
	my $name = $hash->{NAME};
	Log3 $name, 1, "Refreshing parameter" if ($attr{$name}{debugMode});
	
	my $param = {
		url        => "$apiBaseUrl/systems/".$attr{$name}{systemId}."/parameters?parameterIds=".join("&parameterIds=", keys %parameter),
		timeout    => $apiTimeout,
		hash       => $hash, 
		method     => "GET",
		header     => "Authorization: Bearer ".NIBE_HEATPUMP_getToken($hash),
		callback   => sub($) {
						my ($param, $err, $data) = @_;
  						my $hash = $param->{hash};
    					if ($err ne "") {
        					Log3 $hash->{NAME}, 3, "error while requesting ".$param->{url}." - $err";
    					} elsif ($data ne "") {
							eval {
								readingsBeginUpdate($hash);
								my $decoded = decode_json($data);
								for my $hashref (@{ $decoded }) {
									my $parameterId = $hashref->{ 'parameterId' };
									my $parameterValue = $hashref->{ 'rawValue' };
									my $parameterUnit = $hashref->{ 'unit' };
									$parameterValue = $parameterValue / 10 if ($parameterUnit eq "°C");
																		
									readingsBulkUpdate($hash, $parameter{$parameterId}, $parameterValue);
								}
								readingsEndUpdate($hash, 1);
							} or do {
								my $e = $@;
								Log3 $hash->{NAME}, 3, "error while requesting ".$param->{url}." - $e";
							};
						}
					}
	};
	HttpUtils_NonblockingGet($param);
}

sub NIBE_HEATPUMP_refreshConfig($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	Log3 $name, 1, "Refreshing config" if ($attr{$name}{debugMode});
	
	my $param = {
		url        => "$apiBaseUrl/systems/".$attr{$name}{systemId}."/config",
		timeout    => $apiTimeout,
		hash       => $hash, 
		method     => "GET",
		header     => "Authorization: Bearer ".NIBE_HEATPUMP_getToken($hash),
		callback   => sub($) {
						my ($param, $err, $data) = @_;
  						my $hash = $param->{hash};
    					if ($err ne "") {
        					Log3 $hash->{NAME}, 3, "error while requesting ".$param->{url}." - $err";
    					} elsif ($data ne "") {
							eval {
								readingsBeginUpdate($hash);
								my $decoded = decode_json($data);
								readingsBulkUpdate($hash, "conf_hasCooling", $decoded->{hasCooling});
								readingsBulkUpdate($hash, "conf_hasHeating", $decoded->{hasHeating});
								readingsBulkUpdate($hash, "conf_hasHotWater", $decoded->{hasHotWater});
								readingsBulkUpdate($hash, "conf_hasVentilation", $decoded->{hasVentilation});		
								readingsEndUpdate($hash, 1);
							} or do {
								my $e = $@;
								Log3 $hash->{NAME}, 3, "error while requesting ".$param->{url}." - $e";
							};
						}
					}
	};
	HttpUtils_NonblockingGet($param);
}

sub NIBE_HEATPUMP_refreshNotifications($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	Log3 $name, 1, "Refreshing notifications" if ($attr{$name}{debugMode});
	
	my $param = {
		url        => "$apiBaseUrl/systems/".$attr{$name}{systemId}."/notifications?itemsPerPage=".$attr{$name}{maxNotifications},
		timeout    => $apiTimeout,
		hash       => $hash, 
		method     => "GET",
		header     => "Authorization: Bearer ".NIBE_HEATPUMP_getToken($hash),
		callback   => sub($) {
						my ($param, $err, $data) = @_;
  						my $hash = $param->{hash};
    					if ($err ne "") {
        					Log3 $hash->{NAME}, 3, "error while requesting ".$param->{url}." - $err";
    					} elsif ($data ne "") {
							eval {
								readingsBeginUpdate($hash);
								my $maxNotifications = $attr{$name}{maxNotifications};
								my $decoded = decode_json($data);
								my @objects = $decoded->{objects};
								for my $i (0 .. $#objects) {					
									readingsBulkUpdate($hash, "notification_".sprintf("%02d", $i+1), $objects[$i]);
								}
								for my $i ($#objects .. $maxNotifications-1) {					
									readingsBulkUpdate($hash, "notification_".sprintf("%02d", $i+1), "");
								}
								readingsEndUpdate($hash, 1);
								for my $readingsname (keys %{$hash->{READINGS}}) {
									if ($readingsname =~ m/notification_\d+/) {
										my ($no) = ($readingsname =~ m/notification_(\d+)/);
										readingsDelete($hash, $readingsname) if (length $no != 2 || $no < 1 || $no > $maxNotifications);
									}
								}
							} or do {
								my $e = $@;
								Log3 $hash->{NAME}, 3, "error while requesting ".$param->{url}." - $e";
							};
						}
					}
	};
	HttpUtils_NonblockingGet($param);
}

sub NIBE_HEATPUMP_setSmartHomeMode($$) {
    my ($hash, $value) = @_;
	my $name = $hash->{NAME};
	Log3 $name, 1, "Set SmartHome mode $value" if ($attr{$name}{debugMode});
	
	my $param = {
		url => "$apiBaseUrl/systems/".$attr{$name}{systemId}."/smarthome/mode",
		timeout => 10,
		method => "PUT",
		data => '{ "mode": "'.$value.'" }',
		header => "Authorization: Bearer ".NIBE_HEATPUMP_getToken($hash)."\nContent-Type: application/json"
	};
	my ($err, $data) = HttpUtils_BlockingGet($param);
	
	if ($err ne "") {
		Log3 $hash->{NAME}, 3, "error while requesting ".$param->{url}." - $err";
    } else {
		NIBE_HEATPUMP_refresh($hash);
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
