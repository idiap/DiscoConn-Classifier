#!/usr/bin/perl

# Extracts sentences with discourse connectives from a text file
#
# Copyright (c) 2013 Idiap Research Institute, http://www.idiap.ch/
# Written by Thomas Meyer <Thomas.Meyer@idiap.ch>, <ithurtstom@gmail.com>
#
#
# This file is part of the DiscoConn-Classifiers.
#
# DiscoConn is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3 as
# published by the Free Software Foundation.
#
# DiscoConn is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with DiscoConn. If not, see <http://www.gnu.org/licenses/>.

# Usage: ./extract_connectives.pl textfile.txt (although|however|meanwhile|since|though|while|yet)

use strict;
use warnings;

my $file = $ARGV[0];
my $connective = $ARGV[1];

my $outfile = $connective.".txt";

open (INFILE, "<$file") or die "cannot read raw text file $file, $!";
open (OUTFILE, ">$outfile") or die "cannot write $outfile, $!";

while (<INFILE>) {
	my $casedconnective = ucfirst($connective);
	my $find_connective;
	$find_connective = "($casedconnective|$connective)";
	if ($connective eq "while" && $_ =~ /(A|a)\s$connective/ || $_ =~ /(W|w)orth$connective/) {
		next;
	}
	elsif ($connective eq "though" && $_ =~ /(As|as)\s$connective/) {
		next;
	}
	elsif ($connective eq "meanwhile" && $_ =~ /(The|the)\s$connective/) {
		next;
	}
	if ($_ =~ /(.*?\s)?$find_connective(\s|\,|\.|\?|\!|\:|\;|\'|\’|$).*/) {
		print OUTFILE;
	}
} 
close(INFILE);
