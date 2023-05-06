use strict;
use Encode;
use HTTP::Request;
use JSON;
use LWP::UserAgent;
use Net::SFTP::Foreign;
use XML::Twig;
use lib qw(PATH_FOR_LOCAL_PERL_MODULES);        # Create path to custom modules
use AlmaAPI;

my ($curLine);
my @fields;
my $verbose = 0;

# If you make any modifications to the reports, you'll need to update these variables
my $CITATIONS = 'COU - Citations for possible short loan.txt';
my $CITATION_HEADERS = "MMS Id";
my $ITEM_POLICIES = 'PHI - Items with Item policies.txt';
my $ITEM_POLICIES_HEADERS = "MMS Id\tHolding Id\tPhysical Item Id\tBarcode\tProcess Type\tItem Policy\tTemporary Physical Location In Use\tTemporary Item Policy\tTemporary Library Code (Active)\tTemporary Location Code\tLibrary Code (Active)\tLocation Code";

# Download the citation MMS IDs and physical items with item policies and other information. You could use the $CITATIONS and $ITEM_POLICIES constants above here...
my $sftp = Net::SFTP::Foreign->new('SFTP_HOST_ADDRESS', user => 'SFTP_USER', key_path => 'PATH_TO_KEYFILE');
$sftp->get('REMOTE_SFTP_PATH1/PHI - Items with Item policies.txt', 'LOCAL_PATH_FOR_STL_REPORTS\PHI - Items with Item policies.txt');
$sftp->get('REMOTE_SFTP_PATH2/COU - Citations for possible short loan.txt', 'LOCAL_PATH_FOR_STL_REPORTS\COU - Citations for possible short loan.txt');

my $mms_id;
my %citations;
my %item_policies;
my $delete_response;
my %deleted_barcodes;

my ($holding_id_index, $item_id_index, $barcode_index, $holding_id_index, $process_type_index, $item_policy_index, $library_code_active_index, $location_code_index);
my ($temporary_physical_location_in_use_index, $temporary_item_policy_index, $temporary_library_code_active_index, $temporary_location_code_index);

my $now_string = localtime;  # e.g., "Mon Sep 23 18:47:34 2017"
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
$year += 1900;
$mon = sprintf("%02d", ($mon+1));
$mday = sprintf("%02d", $mday);
my $date_today = "$year-$mon-$mday";

my $qt_api_key = AlmaAPI::api_key('QuickTitle');
my $base_url = AlmaAPI::base_url();
my $institution_code = AlmaAPI::institution_code();

open(LOG, ">:encoding(UTF-8)",  'short-loan.log') or die $!;
open(ADD, ">:encoding(UTF-8)",  'short-loan-add.log') or die $!;
print ADD $ITEM_POLICIES_HEADERS, "\n";
open(REMOVE, ">:encoding(UTF-8)",  'short-loan-remove.log') or die $!;
print REMOVE $ITEM_POLICIES_HEADERS, "\n";

# Flush output
$| = 1;

open (CITATIONS, '<:encoding(UTF-16)', $CITATIONS) or die $!;
print LOG "### PROCESSING CITATIONS ###\n";
my $lineCtr = 0;
my $recCtr = 0;

while (<CITATIONS>) {
	$curLine = $_;
	$curLine =~ s/\s+$//;
	$lineCtr++;
	my @fields = split ("\t", $curLine);

	if($lineCtr == 1) {
		unless ($curLine eq $CITATION_HEADERS) {
			print LOG "FATAL ERROR: Headers not as expected in '", $CITATIONS, "'.\n";
			print LOG "Headers: $curLine";
			exit(1);
		}
	} else {
		$recCtr++;
		print LOG "### RECORD $recCtr ###\n";
		unless (scalar(@fields) == 1) {
			print LOG "FATAL ERROR: Unexpected column count: $curLine";
			exit(1);
		}

		$mms_id = $curLine;
		print LOG "MMS ID: $mms_id\n\n";

		$citations{$mms_id}++;
	}
}

open (ITEM_POLICIES, '<:encoding(UTF-16)', $ITEM_POLICIES) or die $!;
print LOG "\n### PROCESSING PHYSICAL ITEMS ###\n";
$lineCtr = 0;
$recCtr = 0;

while (<ITEM_POLICIES>) {
	$curLine = $_;
	$curLine =~ s/\s+$//;
	$lineCtr++;
	my @fields = split ("\t", $curLine);

	if($lineCtr == 1) {
		unless ($curLine eq $ITEM_POLICIES_HEADERS) {
			print LOG "FATAL ERROR: Headers not as expected in '", $ITEM_POLICIES, "'.\n";
			print LOG "Headers: $curLine";
			exit(1);
		}
		for (my $i=0;$i<(scalar(@fields));$i++) {
			# MMS Id\tHolding Id\tPhysical Item Id\tBarcode\tProcess Type\tItem Policy\tTemporary Physical Location In Use\tTemporary Item Policy\tTemporary Library Code (Active)\tTemporary Location Code\tLibrary Code (Active)\tLocation Code
			$holding_id_index = $i if ($fields[$i] eq 'Holding Id');
			$item_id_index = $i if ($fields[$i] eq 'Physical Item Id');
			$barcode_index = $i if ($fields[$i] eq 'Barcode');
			$process_type_index = $i if ($fields[$i] eq 'Process Type');
			$item_policy_index = $i if ($fields[$i] eq 'Item Policy');
			$temporary_physical_location_in_use_index = $i if ($fields[$i] eq 'Temporary Physical Location In Use');
			$temporary_item_policy_index = $i if ($fields[$i] eq 'Temporary Item Policy');
			$temporary_library_code_active_index = $i if ($fields[$i] eq 'Temporary Library Code (Active)');
			$temporary_location_code_index = $i if ($fields[$i] eq 'Temporary Location Code');
			$library_code_active_index = $i if ($fields[$i] eq 'Library Code (Active)');
			$location_code_index = $i if ($fields[$i] eq 'Location Code');
		}
	} else {
		$recCtr++;
#		print LOG "### RECORD $recCtr ###\n";
		unless (scalar(@fields) == 12) {
			print LOG "FATAL ERROR: Unexpected column count: $curLine";
			exit(1);
		}

		$mms_id = $fields[0];

		if ($citations{$mms_id}) {
			if (($fields[$temporary_item_policy_index] eq "SHORT") && ($fields[$temporary_physical_location_in_use_index] eq "Yes")) {
				print LOG "INFO SKIP: barcode $fields[$barcode_index] has corresponding MMS ID in citation file but is already on Short-term loan. (Temp item policy value is ", $fields[$temporary_item_policy_index], ")\n";
				log_details(@fields);
				next;
			}
			print LOG "INFO ADD: barcode $fields[$barcode_index] has corresponding MMS ID in citation file but is not on Short-term loan. (Temp item policy value is ", $fields[$temporary_item_policy_index], ")\n";
			log_details(@fields);

			# curl -X GET "https://api-ca.hosted.exlibrisgroup.com/almaws/v1/bibs/MMS_ID/holdings/HOLDING_ID/items/ITEM_ID" -H "accept: application/json"
			my $url = $base_url . 'almaws/v1/bibs/' . $mms_id . '/holdings/' . $fields[$holding_id_index] .'/items/' . $fields[$item_id_index];
			my $data = make_alma_request('GET',$url,'',$qt_api_key,'json');
			my $json_new = encode_json($data);
			print LOG "Received JSON item\n", $json_new, "\n\n";

			print LOG "INFO ADD: Confirmed Permanent location is ", $data->{'item_data'}->{'location'}->{'value'}, "\n";
			print LOG "INFO ADD: Confirmed item policy is ", $data->{'item_data'}->{'policy'}->{'value'}, "\n";
			print LOG "INFO ADD: Confirmed Temporary item in effect is ", $data->{'holding_data'}->{'in_temp_location'}, "\n";
			print LOG "INFO ADD: Confirmed Temporary location is ", $data->{'holding_data'}->{'temp_location'}->{'value'}, "\n";
			print LOG "INFO ADD: Confirmed Temporary item policy is ", $data->{'holding_data'}->{'temp_policy'}->{'value'}, "\n";

			# Exclude non-circulating locations. With a JOIN report, perhaps this could be done at the Analytics stage, but this does the checks in real time.
			if ((substr($data->{'item_data'}->{'location'}->{'value'},0,3) eq 'RES') ||
			    (substr($data->{'item_data'}->{'location'}->{'value'},0,3) eq 'RSV') ||
			    (substr($data->{'holding_data'}->{'temp_location'}->{'value'},0,3) eq 'RES') ||
			    (substr($data->{'holding_data'}->{'temp_location'}->{'value'},0,3) eq 'RSV')) {
				print LOG "INFO ADD: skipping barcode $fields[$barcode_index] : Reserve location\n\n";
			} elsif ((substr($data->{'item_data'}->{'location'}->{'value'},0,3) eq 'SPE') ||
			         (substr($data->{'item_data'}->{'location'}->{'value'},0,3) eq 'SPC') ||
			         (substr($data->{'holding_data'}->{'temp_location'}->{'value'},0,3) eq 'SPE') ||
			         (substr($data->{'holding_data'}->{'temp_location'}->{'value'},0,3) eq 'SPC')) {
				print LOG "INFO ADD: skipping barcode $fields[$barcode_index] : Special collections location\n\n";
			} elsif ((substr($data->{'item_data'}->{'location'}->{'value'},0,3) eq 'WRK') ||
			         (substr($data->{'holding_data'}->{'temp_location'}->{'value'},0,3) eq 'WRK')) {
				print LOG "INFO ADD: skipping barcode $fields[$barcode_index] : Workroom copy\n\n";
			} elsif (((substr($data->{'item_data'}->{'policy'}->{'value'},0,3) eq 'GOV') && ($data->{'item_data'}->{'policy'}->{'value'} ne 'GOVT-CIRC'))  ||
			         ((substr($data->{'holding_data'}->{'temp_policy'}->{'value'},0,3) eq 'GOV') && ({'holding_data'}->{'temp_policy'}->{'value'} ne 'GOVT-CIRC'))) {
				print LOG "INFO ADD: skipping barcode $fields[$barcode_index] : Non-circulating item policy\n\n";
			} elsif ($data->{'holding_data'}->{'in_temp_location'} && ($data->{'holding_data'}->{'temp_policy'}->{'value'} eq 'SHORT')) {
				print LOG "INFO ADD: skipping barcode $fields[$barcode_index] : Short-term loan item policy already in effect\n\n";
			} elsif (substr($data->{'item_data'}->{'barcode'},0,3) ne '011') {
				print LOG "INFO ADD: skipping Physical Item ID $fields[$item_id_index] : Barcode not as expected\n\n";
			} else {
				$data->{'holding_data'}->{'in_temp_location'} = \1;
				$data->{'holding_data'}->{'temp_policy'}->{'value'} = 'SHORT';
				$data->{'holding_data'}->{'temp_policy'}->{'desc'} = 'Short-term loan';
				$data->{'holding_data'}->{'temp_location'}->{'value'} = $data->{'item_data'}->{'location'}->{'value'};
				$data->{'holding_data'}->{'temp_location'}->{'desc'} = $data->{'item_data'}->{'location'}->{'desc'};
				$data->{'holding_data'}->{'temp_library'}->{'value'} = $data->{'item_data'}->{'library'}->{'value'};
				$data->{'holding_data'}->{'temp_library'}->{'desc'} = $data->{'item_data'}->{'library'}->{'desc'};
				$data->{'item_data'}->{'fulfillment_note'} = 'Short-term loan: 4 days for students, staff and faculty; no loan for alumni and community';
				$json_new = encode_json($data);
				print LOG "Submitted new JSON item\n", $json_new, "\n\n";
				# curl -X PUT "https://api-ca.hosted.exlibrisgroup.com/almaws/v1/bibs/MMS_ID/holdings/HOLDING_ID/items/ITEM_ID" -H "accept: application/json" -d [JSON]
				$url = $base_url . 'almaws/v1/bibs/' . $mms_id . '/holdings/' . $fields[$holding_id_index] .'/items/' . $fields[$item_id_index];
				$data = make_alma_request('JSONPUT',$url,$json_new,$qt_api_key,'json');
				$json_new = encode_json($data);
				print LOG "Received new JSON item\n", $json_new, "\n\n";

				print ADD "$mms_id\t$fields[$holding_id_index]\t$fields[$item_id_index]\t$fields[$barcode_index]\t$fields[$process_type_index]\t" .
					  "$fields[$temporary_physical_location_in_use_index]\t$fields[$temporary_item_policy_index]\t$fields[$temporary_library_code_active_index]\t$fields[$temporary_location_code_index]\t" .
					  "$fields[$library_code_active_index]\t$fields[$location_code_index]\n";
			}

		}
		if (!($citations{$mms_id}) && ($fields[$temporary_item_policy_index] eq "SHORT")) {
			print LOG "INFO REMOVE: barcode $fields[$barcode_index] does not have corresponding MMS ID in citation file yet is on Short-term loan.\n";
			log_details(@fields);

			# curl -X GET "https://api-ca.hosted.exlibrisgroup.com/almaws/v1/bibs/MMS_ID/holdings/HOLDING_ID/items/ITEM_ID" -H "accept: application/json"
			my $url = $base_url . 'almaws/v1/bibs/' . $mms_id . '/holdings/' . $fields[$holding_id_index] .'/items/' . $fields[$item_id_index];
			my $data = make_alma_request('GET',$url,'',$qt_api_key,'json');
			my $json_new = encode_json($data);
			print LOG "Received JSON item\n", $json_new, "\n\n";

			$data->{'holding_data'}->{'in_temp_location'} = \0;
			$data->{'holding_data'}->{'temp_policy'}->{'value'} = '';
			$data->{'holding_data'}->{'temp_policy'}->{'desc'} = '';
			$data->{'item_data'}->{'fulfillment_note'} = '';
			$json_new = encode_json($data);
			print LOG "Submitted new JSON item\n", $json_new, "\n\n";
			# curl -X PUT "https://api-ca.hosted.exlibrisgroup.com/almaws/v1/bibs/MMS_ID/holdings/HOLDING_ID/items/ITEM_ID" -H "accept: application/json" -d [JSON]
			$url = $base_url . 'almaws/v1/bibs/' . $mms_id . '/holdings/' . $fields[$holding_id_index] .'/items/' . $fields[$item_id_index];
			$data = make_alma_request('JSONPUT',$url,$json_new,$qt_api_key,'json');
			$json_new = encode_json($data);
			print LOG "Received new JSON item\n", $json_new, "\n\n";

			print REMOVE "$mms_id\t$fields[$holding_id_index]\t$fields[$item_id_index]\t$fields[$barcode_index]\t$fields[$process_type_index]\t" .
			             "$fields[$temporary_physical_location_in_use_index]\t$fields[$temporary_item_policy_index]\t$fields[$temporary_library_code_active_index]\t$fields[$temporary_location_code_index]\t" .
			             "$fields[$library_code_active_index]\t$fields[$location_code_index]\n";
		}
	}
}

exit(0);

sub make_alma_request {
	my $method = shift;
	my $url = shift;
	my $post_data = shift;
	my $api_key = shift;
	my $response_expected = shift; # response expected? Values: xml, json, none
	my $req;

	my $twig = XML::Twig->new( pretty_print => 'indented');
	my $ua = LWP::UserAgent->new( timeout => 10);

	if ($method eq 'POST') {
		# set custom HTTP request header fields
		$req = HTTP::Request->new(POST => $url);
		$req->header('accept' => 'application/xml');
		$req->header('Content-Type' => 'application/json');
		$req->header('authorization' => "apikey $api_key");
		$req->content($post_data);
	} elsif ($method eq 'XMLPOST') {
		# set custom HTTP request header fields
		$req = HTTP::Request->new(POST => $url);
		$req->header('accept' => 'application/xml');
		$req->header('Content-Type' => 'application/xml');
		$req->header('authorization' => "apikey $api_key");
		$req->content($post_data);
	} elsif ($method eq 'JSONPUT') {
		$req = HTTP::Request->new(PUT => $url);
		$req->header('accept' => 'application/json');
		$req->header('Content-Type' => 'application/json');
		$req->header('authorization' => "apikey $api_key");
		$req->content($post_data);
	} elsif ($method eq 'DELETE') {
		$req = HTTP::Request->new(DELETE => $url);
		$req->header('accept' => '*/*');
		$req->header('authorization' => "apikey $api_key");
	} elsif ($method eq 'GET') {
		$req = HTTP::Request->new(GET => $url);
		$req->header('accept' => 'application/json');
		$req->header('authorization' => "apikey $api_key");
	} elsif ($method eq 'SRUGET') {
		$req = HTTP::Request->new(GET => $url);
		$req->header('accept' => 'application/xml');
	}

	my $response = $ua->request($req);
	my $status = log_alma_response($response);

	# Try not to overrun the server
	sleep(0.1);

	if ($response_expected eq 'xml') {
		my $twig = XML::Twig->new( pretty_print => 'indented');
		my $xml_string = $response->content;
		$twig->parse( $xml_string );
		return $twig;
	} elsif ($response_expected eq 'json') {
		my $data = decode_json($response->content);
		return $data;
	} elsif ($response_expected eq 'none') {
		return (0);
	} else {
		die "Unexpected response type specified.\n";
	}
}

sub log_alma_response {
	my $response = shift;
	if ($response->is_success) {
		print LOG 'Response retrieved from Alma:' . $response->status_line . "\n" if ($verbose);
	} else {
		print LOG 'ERROR: Error while getting URL: ' . $response->request->uri . "\n";
		print LOG 'ERROR: ' . $response->status_line . "\n\n";
	}
	return (0);
}

sub log_details {
	my @fields = @_;
	print LOG "\tPermanent Library: ", $fields[$library_code_active_index], "\n";
	print LOG "\tPermanent Location: ", $fields[$location_code_index], "\n";
	print LOG "\tPermanent Item Policy: ", $fields[$item_policy_index], "\n";
	print LOG "\tTemporary Location in use: ", $fields[$temporary_physical_location_in_use_index], "\n";
	print LOG "\tTemporary Library: ", $fields[$temporary_library_code_active_index], "\n";
	print LOG "\tTemporary Location: ", $fields[$temporary_location_code_index], "\n";
	print LOG "\tTemporary Item Policy: ", $fields[$temporary_item_policy_index], "\n";
	print LOG "\tCurrent Process: ", $fields[$process_type_index], "\n\n";
	return (0);
}
