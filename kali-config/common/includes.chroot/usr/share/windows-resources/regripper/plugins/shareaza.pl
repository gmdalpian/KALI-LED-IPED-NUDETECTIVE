#-----------------------------------------------------------
# shareaza.pl
# 
#
# Change History
#   20160808 - 
#   20160630 - adapted to Shareaza
#
#-----------------------------------------------------------
package shareaza;
use strict;

my %config = (hive          => "NTUSER\.DAT",
              hasShortDescr => 1,
              hasDescr      => 0,
              hasRefs       => 0,
              osmask        => 22,
              version       => 20160630);

sub getConfig{return %config}
sub getShortDescr {
	return "Gets contents of user's Software/Shareaza key";	
}
sub getDescr{}
sub getRefs {}
sub getHive {return $config{hive};}
sub getVersion {return $config{version};}


my $VERSION = getVersion();

sub pluginmain {
	my $class = shift;
	my $ntuser = shift;
	::logMsg("--------------------------------");
	::logMsg("Launching shareaza v.".$VERSION);
	::logMsg("--------------------------------");
	my $reg = Parse::Win32Registry->new($ntuser);
	my $root_key = $reg->get_root_key;

	my $key_path = 'Software\\Shareaza\\Shareaza';
	my $key;
	if ($key = $root_key->get_subkey($key_path)) {
		::rptMsg($key_path);
		::rptMsg("LastWrite Time ".gmtime($key->get_timestamp())." (UTC)");
#		::rptMsg("");
		my %shareaza = ();
		my @vals = $key->get_list_of_values();
		if (scalar(@vals) > 0) {
			foreach my $v (@vals) {
				#$shareaza{$v->get_name()} = $v->get_data();
				::rptMsg($v->get_name()." -> ".$v->get_data());
			}

			::rptMsg("");

		}
		else {
			::rptMsg($key->get_name()." has no values.");
		}
		::rptMsg("");
		getSearchTerms($key);
		getDownloads($key);
		
	}
	else {
		::rptMsg($key_path." not found.");
	}
}

sub getSearchTerms {
	my $key = shift;
	
	my $count = 0;
	::rptMsg("Shareaza Search:");

		my $gen = $key->get_subkey("Search");
		my @vals = $gen->get_list_of_values();
		if (scalar(@vals) > 0) {
			$count = 1;
			::rptMsg($gen->get_name());
			::rptMsg("LastWrite: ".gmtime($gen->get_timestamp())." (UTC)");
			foreach my $v (@vals) {
				#next if ($v->get_name() eq "");
				#::rptMsg("  ".hex2ascii($v->get_name()));
				::rptMsg($v->get_name()." -> ".$v->get_data());
			}
		}

	::rptMsg("No search terms found\.") if ($count == 0);
}




sub getDownloads {
	my $key = shift;
	
	my $count = 0;
	::rptMsg("");
	::rptMsg("Shareaza Downloads:");

		my $gen = $key->get_subkey("Downloads");
		my @vals = $gen->get_list_of_values();
		if (scalar(@vals) > 0) {
			$count = 1;
			::rptMsg($gen->get_name());
			::rptMsg("LastWrite: ".gmtime($gen->get_timestamp())." (UTC)");
			foreach my $v (@vals) {
				::rptMsg($v->get_name()." -> ".$v->get_data());
			}
		}

	::rptMsg("No search terms found\.") if ($count == 0);
}


sub hex2ascii {
  return pack('H*',shift); 
}

1;

