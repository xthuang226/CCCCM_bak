#!/usr/bin/perl
use warnings;
use strict;
use feature 'say';

use Mojolicious::Lite;
use DBI;
use Mojo::JSON qw(decode_json encode_json);
use Scalar::Util qw(looks_like_number);
plugin 'RenderFile';
plugin 'RemoteAddr';

use LWP::UserAgent;
use Encode;


# color setting
# my @color = qw/#FF5959 #FF6363 #FF6D6D #FF7777 #FF8181 #FF8B8B #FF9595 #FF9F9F #FFA9A9 #FFB3B3 #FFBDBD/;
# my @color = qw/#595959 #636363 #6D6D6D #777777 #818181 #8B8B8B #959595 #9F9F9F #A9A9A9 #B3B3B3 #BDBDBD/;
# my @color = qw/#FCF8BD #F2EEB3 #E8E4A9 #DEDA9F #D4D095 #CAC68B #C0BC81 #B6B277 #ACA86D #A29E63/;

my @color = qw/4A5049 545B55 5F6661 6A716E 757C7A 808787 8B9293 969DA0 A1A8AC ACB3B9/;

my $noip = {
	"107.182.184.13" => 1,
	"98.142.136.12" => 1
};

my $hightest_contact = 0.28;


# connect to database
my $dbh = DBI->connect("dbi:SQLite:dbname=data/cc_list.db3","","",{ RaiseError => 1 }) or die $DBI::errstr;
helper db => sub { $dbh };

# read auto cre list
my $sql = '
	SELECT * FROM contact_cell_list
';

my $sth = $dbh->prepare( $sql );
$sth->execute();
my $cell_names = $sth->fetchall_arrayref;

my @json_rows;
foreach my $cn (@$cell_names){
	push @json_rows, encode_json {('name', $$cn[0])};
}

my $cellnames = '['.(join (',', @json_rows)).']';


my @query_name;
helper search => sub {
	my $self = shift;
	my ($name) = @_;
	my $sth;
	

	if (defined $name){
		my $sql_nodes;
		my $sql_rows;
		my $sql_rows_search;
		my ($nodes, $rows, $rows_search);
		my @query_names = split(/,/, $name);
		my %query_names;
		foreach (@query_names) {
			$query_names{$_}=1;
		}
		@query_name = keys %query_names;

		
		if (scalar @query_name == 1){
			
			my $key = $query_name[0];
			
			$sql_nodes = '
				select Cell1 from cc_list where cast (? as text) in (upper(Cell1), upper(Cell2))
				union
				select Cell2 from cc_list where cast (? as text) in (upper(Cell1), upper(Cell2))
			';
			
			$sql_rows = '
				with linked(name) as (
					select Cell1 from cc_list where cast (? as text) in (upper(Cell1), upper(Cell2))
					union
					select Cell2 from cc_list where cast (? as text) in (upper(Cell1), upper(Cell2))
				)
				select * from cc_list
				WHERE Cell1 IN (SELECT * FROM linked) AND Cell2 IN (SELECT * FROM linked)
			';

			$sth = eval { $self->db->prepare( $sql_nodes ) } || return undef;
			$sth->execute($key,$key);
			$nodes = $sth->fetchall_arrayref;

			$sth = eval { $self->db->prepare( $sql_rows ) } || return undef;
			$sth->execute($key,$key);
			$rows = $sth->fetchall_arrayref;


			$sql_rows_search = '
				select * from cc_list
				WHERE upper(Cell1) LIKE ? OR upper(Cell2) LIKE ?
			';

			$sth = eval { $self->db->prepare( $sql_rows_search ) } || return undef;
			$sth->execute($key,$key);
			$rows_search= $sth->fetchall_arrayref;

		
		}else{
			my $key = join ('\',\'', @query_name);
			$key = '\''.$key.'\'';
			$sql_nodes = '
				SELECT * FROM contact_cell_list
				WHERE upper(cell_name) in ('.$key.')
			';

			$sql_rows = '
				select * from cc_list
				WHERE upper(Cell1) IN ('.$key.') AND upper(Cell2) IN ('.$key.')
			';
			
			$sth = eval { $self->db->prepare( $sql_nodes ) } || return undef;
			$sth->execute();
			$nodes = $sth->fetchall_arrayref;

			$sth = eval { $self->db->prepare( $sql_rows ) } || return undef;
			$sth->execute();
			$rows = $sth->fetchall_arrayref;
		}

		return ($nodes, $rows, $rows_search);
	}
};


my %cell_svg_info;
open (INPUT, "data/wild_tree.svg") || die $!;
foreach (<INPUT>) {
	chomp;
	if (/<line data-toggle="[^"]+" id="([^"]+)" stroke="[^"]+" stroke-width="[^"]+" title="[^"]+" x1="([^"]+)" x2="([^"]+)" y1="([^"]+)" y2="([^"]+)" \/>/) {
		my @ele;
		foreach ($2, $3, $4, $5) {
			push @ele, $_;
		}
		$cell_svg_info{$1} = \@ele;
	}
}
close INPUT;


my %leader_cell;
foreach (qw/P0 AB ABa ABp P1 EMS MS E C D P2 P3 P4/) {
	$leader_cell{$_} = 1;
}



my %menu_tree_key;
my $i = 0;
open (INPUT, "data/menu_tree.json") || die $!;
foreach (<INPUT>) {
	chomp;
	if (/"text": "([^"]+)"/) {
		my $name = $1;
		$name = uc $name;
		$menu_tree_key{$name} = $i;
		$i++;
	}
}
close INPUT;


any '/' => sub {
	my $self = shift;
	$self->stash(names => $cellnames);
	$self->render('/ccccm_index');

	my $ip = $self->remote_addr;
	unless (defined $$noip{$ip}) {
		my $dbh_ip = DBI->connect("dbi:SQLite:dbname=data/ip_record.db3","","",{ RaiseError => 1 }) or die $DBI::errstr;
		& ip_info($ip, $dbh_ip);
		$dbh_ip->disconnect;
	}
};

my ($query, $nodes, $rows, $rows_search, $nodes_global, $edges_global, $edges_global_search);



any '/search' => sub {
	my $self = shift;
	$query = $self->param('cell_name');
	$query = uc($query);
	$query =~ s/\s+//g;

	($nodes, $rows, $rows_search)= $self->search($query);

	$nodes_global = &to_json($nodes,'nodes');
	$edges_global = &to_json($rows,'edges');
	$edges_global_search = &to_json($rows_search,'edges');

	$self->stash(cell_name => $query, nodes => $nodes, cell_svg_info => \%cell_svg_info, leader_cell => \%leader_cell, treeid => $menu_tree_key{$query});

	$self->render('/ccccm_search');

	my $ip = $self->remote_addr;
	unless (defined $$noip{$ip}) {
		my $dbh_ip = DBI->connect("dbi:SQLite:dbname=data/ip_record.db3","","",{ RaiseError => 1 }) or die $DBI::errstr;
		& ip_search($ip, $dbh_ip);
		$dbh_ip->disconnect;
	}
};

any '/graph1' => sub {
	my $self = shift;
	$self->stash(draw_nodes => $nodes_global, draw_edges => $edges_global);
	$self->render('/ccccm_graph1');
};

any '/graph2' => sub {
	my $self = shift;
	$self->stash(draw_nodes => $nodes_global, draw_edges => $edges_global_search);
	$self->render('/ccccm_graph2');
};

any '/table1' => sub {
	my $self = shift;
	$self->stash(cell_name => $query, nodes => $nodes, rows => $rows);
	$self->render('/ccccm_table');
};

any '/table2' => sub {
	my $self = shift;
	$self->stash(cell_name => $query, nodes => $nodes, rows => $rows_search);
	$self->render('/ccccm_table');
};

any '/download_contact_list' => sub {
	my $self = shift;
	my $file = "effective_connect_list.csv";
	$self->render_file('filepath' => "./download/$file");

	my $ip = $self->remote_addr;
	unless (defined $$noip{$ip}) {
		my $dbh_ip = DBI->connect("dbi:SQLite:dbname=data/ip_record.db3","","",{ RaiseError => 1 }) or die $DBI::errstr;
		& ip_download($ip, $dbh_ip);
		$dbh_ip->disconnect;
	}
};



any '/access' => sub {
	my $self = shift;

	my $dbh_ip = DBI->connect("dbi:SQLite:dbname=data/ip_record.db3","","",{ RaiseError => 1 }) or die $DBI::errstr;

	my $sql_ip = '
		SELECT ip_info.remoter_ip, location, counter, last_access, access_history FROM ip_info
		LEFT JOIN ip_location
		ON ip_info.remoter_ip=ip_location.remoter_ip
		ORDER BY last_access DESC
	';
	my $sth = $dbh_ip->prepare( $sql_ip );
	$sth->execute();
	my $tmp = $sth->fetchall_arrayref;

	my $query_ip_info;
	foreach (@$tmp) {
		my @line;
		foreach (@$_) {
			push @line, decode("utf8", $_);
		}
		push @$query_ip_info, \@line;
	}


	$sql_ip = '
		SELECT ip_search.remoter_ip, location, counter, last_access, access_history FROM ip_search
		LEFT JOIN ip_location
		ON ip_search.remoter_ip=ip_location.remoter_ip
		ORDER BY last_access DESC
	';
	$sth = $dbh_ip->prepare( $sql_ip );
	$sth->execute();
	$tmp = $sth->fetchall_arrayref;

	my $query_ip_search;
	foreach (@$tmp) {
		my @line;
		foreach (@$_) {
			push @line, decode("utf8", $_);
		}
		push @$query_ip_search, \@line;
	}


	$sql_ip = '
		SELECT ip_download.remoter_ip, location, counter, last_access, access_history FROM ip_download
		LEFT JOIN ip_location
		ON ip_download.remoter_ip=ip_location.remoter_ip
		ORDER BY last_access DESC
	';
	$sth = $dbh_ip->prepare( $sql_ip );
	$sth->execute();
	$tmp = $sth->fetchall_arrayref;

	my $query_ip_download;
	foreach (@$tmp) {
		my @line;
		foreach (@$_) {
			push @line, decode("utf8", $_);
		}
		push @$query_ip_download, \@line;
	}


	$dbh_ip->disconnect;


	$self->stash(query_ip_info => $query_ip_info, query_ip_search => $query_ip_search, query_ip_download => $query_ip_download);
	$self->render('/access');
};



app->start;


sub to_json {
	my ($rows, $para) = @_;
	my @json_rows;
	my $result = 'null';
	
	if ($para eq 'nodes'){
		
		if (@query_name > 1){
			foreach my $row (@$rows){
				push @json_rows, encode_json {('data'), {('id', $$row[0])}, ('css'), {('background-color', '#E74C3C', 'width', 40, 'height', 40)}};
			}
		}else{
			foreach my $row (@$rows){
				if (uc($$row[0]) eq $query_name[0]){
					push @json_rows, encode_json {('data'), {('id', $$row[0])}, ('css'), {('background-color', '#E74C3C', 'width', 55, 'height', 55)}};
				}else{
					push @json_rows, encode_json {('data'), {('id', $$row[0])}, ('css'), {('background-color', '#447983', 'width', 40, 'height', 40)}};
				}
			}
		}

		$result = '['.(join (',', @json_rows)).']' if scalar @$rows != 0;
	}else{
		foreach my $row (@$rows){
			my $scale = int(10*($$row[2]/$hightest_contact)); # 0-10 integer
			my $color = '#'.$color[10-$scale];
			my $width = 2 * $scale;
			my $opacity = 0.5*$scale + 0.5;
			push @json_rows, encode_json {('data'), {('id', $$row[0].$$row[1], 'source', $$row[0], 'target', $$row[1], 'weight', $$row[2])}, ('css'), {('line-color', $color, 'width', $width, 'opacity', $opacity)}};
		}

		$result = '['.(join (',', @json_rows)).']' if scalar @$rows != 0;
	}
	
	return $result;
}


sub ip_location_record {
	my ($ip, $dbh) = @_;

	my $sql = '
		SELECT * FROM ip_location
		WHERE remoter_ip IS ?
	';

	my $sth = $dbh->prepare( $sql );
	$sth->execute($ip);

	my $query_ip_info = $sth->fetchall_arrayref;

	my $row = $$query_ip_info[0];

	if (scalar @$query_ip_info == 0){
		my @locations = & ip_location($ip);
		$sql = '
			INSERT INTO ip_location (remoter_ip,location)
			VALUES (?, ?)
		';

		$sth = $dbh->prepare( $sql );
		$sth->execute($ip, join(' ; ',@locations));
	}
}


### update_remote_ip_info
sub ip_info {
	my ($ip, $dbh) = @_;
	
	my $sql = '
		SELECT * FROM ip_info
		WHERE remoter_ip IS ?
	';
	
	my $sth = $dbh->prepare( $sql );
	$sth->execute($ip);
	
	my $query_ip_info = $sth->fetchall_arrayref;
	
	my $row = $$query_ip_info[0];
	my $count = $$row[1];
	my $access_history = $$row[3];
	
	if (scalar @$query_ip_info == 1){
		$count += 1;
		$access_history =~ s/}/ ; /;
		
		my $sql = '
			UPDATE ip_info
			SET counter = '.$count.', last_access = (SELECT datetime(\'now\',\'localtime\',\'+12 hours\')), access_history = \''.$access_history.'\'||(SELECT datetime(\'now\',\'localtime\',\'+12 hours\'))||\'}\'
			WHERE remoter_ip IS ?
		';
		my $sth = $dbh->prepare( $sql );
		$sth->execute($ip);
	}else{
		my $sql = '
			INSERT INTO ip_info (remoter_ip,counter,last_access,access_history)
			VALUES (?, 1, (SELECT datetime(\'now\',\'localtime\',\'+12 hours\')), \'{\'||(SELECT datetime(\'now\',\'localtime\',\'+12 hours\'))||\'}\')
		';
		my $sth = $dbh->prepare( $sql );
		$sth->execute($ip);
	}

	& ip_location_record($ip, $dbh);
}

### update_remote_ip_info_download_file
sub ip_download {
	my ($ip, $dbh) = @_;
	
	my $sql = '
		SELECT * FROM ip_download
		WHERE remoter_ip IS ?
	';
	
	my $sth = $dbh->prepare( $sql );
	$sth->execute($ip);
	
	my $query_ip_info = $sth->fetchall_arrayref;
	
	my $row = $$query_ip_info[0];
	my $count = $$row[1];
	my $access_history = $$row[3];
	
	if (scalar @$query_ip_info == 1){
		$count += 1;
		$access_history =~ s/}/ ; /;
		
		my $sql = '
			UPDATE ip_download
			SET counter = '.$count.', last_access = (SELECT datetime(\'now\',\'localtime\',\'+12 hours\')), access_history = \''.$access_history.'\'||(SELECT datetime(\'now\',\'localtime\',\'+12 hours\'))||\'}\'
			WHERE remoter_ip IS ?
		';
		my $sth = $dbh->prepare( $sql );
		$sth->execute($ip);
	}else{
		my $sql = '
			INSERT INTO ip_download (remoter_ip,counter,last_access,access_history)
			VALUES (?, 1, (SELECT datetime(\'now\',\'localtime\',\'+12 hours\')), \'{\'||(SELECT datetime(\'now\',\'localtime\',\'+12 hours\'))||\'}\')
		';
		my $sth = $dbh->prepare( $sql );
		$sth->execute($ip);
	}

	& ip_location_record($ip, $dbh);
}


### update_remote_ip_search_
sub ip_search {
	my ($ip, $dbh) = @_;
	
	my $sql = '
		SELECT * FROM ip_search
		WHERE remoter_ip IS ?
	';
	
	my $sth = $dbh->prepare( $sql );
	$sth->execute($ip);
	
	my $query_ip_info = $sth->fetchall_arrayref;
	
	my $row = $$query_ip_info[0];
	my $count = $$row[1];
	my $access_history = $$row[3];
	
	if (scalar @$query_ip_info == 1){
		$count += 1;
		$access_history =~ s/}/ ; /;
		
		my $sql = '
			UPDATE ip_search
			SET counter = '.$count.', last_access = (SELECT datetime(\'now\',\'localtime\',\'+12 hours\')), access_history = \''.$access_history.'\'||(SELECT datetime(\'now\',\'localtime\',\'+12 hours\'))||\'}\'
			WHERE remoter_ip IS ?
		';
		my $sth = $dbh->prepare( $sql );
		$sth->execute($ip);
	}else{
		my $sql = '
			INSERT INTO ip_search (remoter_ip,counter,last_access,access_history)
			VALUES (?, 1, (SELECT datetime(\'now\',\'localtime\',\'+12 hours\')), \'{\'||(SELECT datetime(\'now\',\'localtime\',\'+12 hours\'))||\'}\')
		';
		my $sth = $dbh->prepare( $sql );
		$sth->execute($ip);
	}

	& ip_location_record($ip, $dbh);
}




sub ip_location {
	my ($ip) = @_;
	my @res;

	my $ua = LWP::UserAgent->new;
	$ua->agent('Mozilla/5.0');
	$ua->cookie_jar({});
	
	my $url1 = "http://www.query-ip.com/";
	my $url2 = "http://ip.chinaz.com/$ip";
	my $url3 = "https://db-ip.com/$ip";

	my $response;

	$response = $ua->post( $url1,
		[
			ip => $ip
		]
	);
	if ($response->is_success) {
		my $content = $response->decoded_content;
		if ($content =~ /is located in <strong>([^<>]+)<\/strong>/){
			my $key = $1;
			$key =~ s/\s+/ /g;
			$key =~ s/^\s+//;
			$key =~ s/\s+$//;
			push @res, $key;
		}
	}else {
		warn $response->status_line;
	}


	$response = $ua->get( $url2	);
	if ($response->is_success) {
		my $content = $response->decoded_content;
		
		if ($content =~ /w50-0">([^<>]+)<\/span>[\s\n]+<\/p>[\s\n]+<div class="clearfix plr10">/){
			push @res, $1;
		}
		
	}else {
		warn $response->status_line;
	}


	$response = $ua->get( $url3	);
	if ($response->is_success) {
		my $content = $response->decoded_content;
		
		my @keys;
		if ($content =~ /<tr><th>Country<\/th><td>([^<>&]+)&nbsp;/){
			my $key = $1;
			$key =~ s/^[\n\s]+//;
			$key =~ s/[\n\s]+$//;
			push @keys, $key;
		}
		if ($content =~ /<tr><th>State \/ Region<\/th><td>([^<>]+)<\/td><\/tr>/){
			my $key = $1;
			$key =~ s/^[\n\s]+//;
			$key =~ s/[\n\s]+$//;
			push @keys, $key;
		}
		if ($content =~ /<tr><th>City<\/th><td>([^<>]+)<\/td><\/tr>/){
			my $key = $1;
			$key =~ s/^[\n\s]+//;
			$key =~ s/[\n\s]+$//;
			push @keys, $key;
		}
		if ($content =~ /<tr><th>Organization<\/th><td>([^<>]+)<\/td><\/tr>/){
			my $key = $1;
			$key =~ s/^[\n\s]+//;
			$key =~ s/[\n\s]+$//;
			push @keys, $key;
		}
		if ($content =~ /<tr><th>ISP<\/th><td>([^<>]+)<\/td><\/tr>/){
			my $key = $1;
			$key =~ s/^[\n\s]+//;
			$key =~ s/[\n\s]+$//;
			push @keys, $key;
		}

		push @res, join (', ', @keys);

	}else {
		warn $response->status_line;
	}

	return @res;
}



