#@ ORIG_PART_1
package AlmaAPI;

use strict;

my $QuickTitle_api_key = '[YOUR_API_KEY_HERE]';
my $Other_api_key = '[MORE_API_KEYS]';
my $base_url = 'https://api-ca.hosted.exlibrisgroup.com/';
my $sru_base_url = 'https://ocul-tu.alma.exlibrisgroup.com/';
my $institution_code = '[YOUR_INSTITUTION_CODE]';

sub api_key
{
	my $request = shift;
	if ($request eq 'QuickTitle') {
		return ($QuickTitle_api_key);
	} elsif ($request eq 'Other') {
		return ($Other_api_key);
	} else {
		die "api_key method requires name of key\n"
	}
}

sub base_url
{
	return ($base_url);
}

sub sru_base_url
{
	return ($sru_base_url);
}

sub institution_code
{
	return ($institution_code);
}
