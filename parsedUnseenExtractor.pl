#!/usr/bin/perl

# Discourse Connective feature extractor
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

# Extracts features over unseen English texts in order to disambiguate Discourse Connectives
# according to their rhetorical relations (see the readme file for the classes of the latter)
# will generate a test set with feature vectors of syntactic, WordNet, TimeML and dependency 
# features to be used by the attached Stanford classifier model (see readme as well)

# Input: Parse your raw texts, consisting of sentences with connectives, one sentence per line, with
# a) a constituency parser (e.g. https://github.com/BLLIP/bllip-parser)
# b) a TimeML parser (http://www.timeml.org/site/tarsqi/toolkit/)
# c) a dependency parser (e.g. https://github.com/agesmundo/IDParser)
# have these outputs ready in corresponding directories, lines 68--73 below

# You also need to have WordNet (http://wordnet.princeton.edu/) installed plus the cpan module to query it (http://search.cpan.org/~jrennie/WordNet-QueryData-1.49/QueryData.pm)
# Set the environment variable WNHOME before executing this script. Under Linux: export WNHOME=/path/to/WordNet

# *************************************************************************************************************
# to run this script: ./parsedUnseenExtractor.pl (although|meanwhile|however|since|though|while|yet) directory/
# *************************************************************************************************************

# see the readme file for how to run the classifier afterwards

# please also see (and cite :-) ) the following papers for details:
# Meyer, Thomas, Popescu-Belis, Andrei, Hajlaoui, Najeh, Gesmundo, Andrea. 2012. Machine Translation of Labeled Discourse Connectives. In Proceedings of the Tenth Biennial Conference of the Association for Machine Translation in the Americas (AMTA), 10 pages, San Diego, CA.
# Meyer, Thomas, Popescu-Belis, Andrei. 2012. Using Sense-labeled Discourse Connectives for Statistical Machine Translation. In Proceedings of the EACL2012 Workshop on Hybrid Approaches to Machine Translation (HyTra), pp. 129-138, Avignon, FR.

use strict;
#DEBUG:
# use warnings;

# if you have installed your cpan packages in a non-default path, point to it with use lib
# use lib "/path/to/cpan/modules";
use WordNet::SenseRelate::AllWords;
use WordNet::QueryData;
use WordNet::Tools;
use WordNet::Similarity::path;

# construct WordNet queries	
my $qd = WordNet::QueryData->new;
defined $qd or die "Construction of WordNet::QueryData failed";
my $wntools = WordNet::Tools->new($qd);
defined $wntools or die "\nCouldn't construct WordNet::Tools object"; 

# specify for which connective the features should be extracted
my $connective = $ARGV[0];

my $indir = $ARGV[1];

my $parsedfile = $indir."/parsed/".$connective.".cparsed"; # file from a constiuent parser
my $depparsedfile = $indir."/depparsed/".$connective.".dparsed"; # file from a dependency parser
my $tarsqifile = $indir."/tarsqi/".$connective.".tarsqi"; # tarsqi-annotated file 

my $maxentfile = $indir.$connective."_testing.maxent"; # definitive syntactic feature file to generate
my $maxentfile_extended = $indir.$connective."_testing.maxent.extended"; # definitive syntactic plus dependency feature file to generate

my @instances_all;  # array of initial feature vectors, is generated at the end of extract_features()

my @wordnetvalues; # array of word distance values obtained from WordNet at the end of wordnet_relatedness();
my @antonym_chains; # array of antonyms, generated in infer_antonyms();


# cleaning dependency parses, getting simplified format
clean_dependency();

# check if parsed files are all complete, will die if not
check_parses();

# find syntactic, TimeML and WordNet features, generate initial vectors
extract_features($connective);

# generate a maxent test file with syntactic features
create_maxent($connective);

# generate dependency features as well and clean up
create_maxent_extended($connective);

sub check_parses {
	
	 open (PARSEDFILE, "<$parsedfile") or die "cannot open $parsedfile, $!";
	 open (DEPPARSEDFILE, "<$depparsedfile.clean") or die "cannot open $depparsedfile.clean, $!";
	 open (TARSQIFILE, "<$tarsqifile") or die "cannot open $tarsqifile, $!";
	
	 my @lines1 = <PARSEDFILE>;
	 my @lines2 = <DEPPARSEDFILE>; 
	 my @lines3 = <TARSQIFILE>;
	
	 close(PARSEDFILE);
	 close(DEPPARSEDFILE);
	 close(TARSQIFILE);	
		 
	 if ($#lines1 != $#lines2 || $#lines2 != $#lines3 || $#lines1 != $#lines3) {
	 		die "Your parse files don't have the same number of or empty lines -- check.\n"
	 }
	 else {
	 	
	 foreach my $line1 (@lines1) {
	 	if ($line1 =~ /^$/) {
	 		die "There was a problem in your syntactic parses. Maybe an empty line in the file?\n";
	 	}
	 }
	 foreach my $line2 (@lines2) {
	 	if ($line2 =~ /^$/) {
	 		die "There was a problem in your dependency parses. Maybe an empty line in the file?\n";
	 	}
	 }
	 foreach my $line3 (@lines3) {
	 	 	if ($line3 =~ /^$/) {
	 		die "There was a problem in your Tarsqi parses. Maybe an empty line in the file?\n";
	 	}
	 }
	 }
	 print "All parses checked. We're good to go...\n";
}


sub extract_features {
	
	print "starting feature extraction...";
	
	my $connective = $_[0];

	my $casedconnective = ucfirst($connective); # upper-case the connective to have all occurrences

	my $connwordform;			# the cased connective (sentence-initial or not)
	my @connwordforms;
	my $class;				# class : the connective sense to be found, here just ? as test instances
	my @classes;
	my $selfcategory;			# POS tag of the connective
	my @selfcategories;
	my $firstverb;				# POS tag of the first verb in the sentence
	my @firstverbs;
	my $firstverbword;			# word form of the first verb
	my @firstverbwords;
	my $auxpreceding;			# type of auxiliary verb before the connective (if any)
	my $auxtypepreceding;
	my @auxtypespreceding;
	my $firstverbafterconn;			# POS tag of the first verb after the connective
	my @firstverbsafterconn;
	my $firstverbafterconnword;		# word form the following verb
	my @firstverbafterconnwords;
	my $auxfollowing;			# type of auxiliary verb after the connective (if any)
	my $auxtypefollowing;
	my @auxtypesfollowing;
	my $previousword;			# word directly preceding the connective
	my $previouswordpos;			# its POS tag
	my $casedpreviousword;			# its lowercased form
	my @previouswords;	
	my @previouswordsposis;
	my $followingword;			# word directly following the connective
	my $followingwordpos;			# its POS tag
	my $casedfollowingword;			# its lowercased form		
	my @followingwords;
	my @followingwordsposis;
	my $firstwordsent;			# first word of the sentence
	my $firstwordsentpos;			# its POS tag
	my $casedfirstwordsent;			# its lowercased form
	my @firstwordsents;
	my @firstwordsentsposis;
	my $lastwordsent;			# last word in the sentence
	my $lastwordsentpos;			# its POS tag
	my $casedlastwordsent;			# its lowercased form
	my @lastwordsents;
	my @lastwordsentsposis;
	my @sentpatterns;			# punctuation pattern in the sentence
	my @syntaxchains;			# syntactical path to the connective
	
	# open Charniak parsed file
    	open (PARSEDFILE, "<$parsedfile") or die "cannot open $parsedfile, $!";
		my @parsedfile_content = <PARSEDFILE>;
	close (PARSEDFILE);

	my $counter = 0; # to keep track of instances    

	# go through lines of the parsed and tagged files and get all the features
	foreach my $line (@parsedfile_content) {
	$counter++;	
	my @wordnetcontext; # definition of array of the 6 words extracted and to be passed to wordnet_relatedness()
	    if ($line =~ /($connective|$casedconnective)\)/) { # get connective word form
		$connwordform = $1;
		push(@connwordforms, $connwordform);
		my $class = "?"; # ? for missing class values
		push(@classes, $class);
		$line =~ /([A-Z]*)\s$connwordform/;
		my $selfcategory = $1;
		push(@selfcategories, $selfcategory);
		$line =~ /.*?VP\s\((VB.?|AUX.?)\s(.*?)\).*?$connwordform/; # get the pos-tag of the first verb in the sentence
		$firstverb = $1;
		$firstverbword = $2;
		if ($firstverb eq "AUX" || $firstverb eq "AUXG") { 	     # get the type of auxiliary verb preceding the connective
			$line =~ /.*?VP\s\(AUX.?\s(.*?)\).*?$connwordform/;
				$auxpreceding = $1;
				$auxtypepreceding = normalize_auxtype($auxpreceding);		
		}
		push(@auxtypespreceding, $auxtypepreceding);
		if ($firstverb !~ /VB|VBD|VBG|VBN|VBP|VBZ|AUX|AUXG/) { # if there is no verb preceding the connective
			$firstverb = "NOVERB";
			$firstverbword = "NOVERBWORD";
		}
		$firstverbword = special_chars($firstverbword);
		push (@firstverbs, $firstverb);
		push (@firstverbwords, $firstverbword);
		push (@wordnetcontext, $firstverbword);
		$line =~ /$connwordform.*?VP\s\((VB.?|AUX.?)\s(.*?)\)/; # get pos-tag of the first verb following connective, incl. auxiliries
		$firstverbafterconn = $1;
		$firstverbafterconnword = $2;
		if ($firstverbafterconn eq "AUX" || $firstverbafterconn eq "AUXG") { # get the type of auxiliary verb following the connective
			$line =~ /$connwordform.*?VP\s\(AUX.?\s(.*?)\)/;
				$auxfollowing = $1;
				$auxtypefollowing = normalize_auxtype($auxfollowing);
		}		
		push(@auxtypesfollowing, $auxtypefollowing);
		if ($firstverbafterconn !~ /VB|VBD|VBG|VBN|VBP|VBZ|AUX|AUXG/) { # if there is no verb following the connective
			$firstverbafterconn = "NOVERB";
			$firstverbafterconnword = "NOVERBWORD";
		}	
		$firstverbafterconnword = special_chars($firstverbafterconnword);
		push (@firstverbsafterconn, $firstverbafterconn);
		push (@firstverbafterconnwords, $firstverbafterconnword);
		push (@wordnetcontext, $firstverbafterconnword);
		$line =~ /([A-Z\d\-\$]{1,8})\s([A-Za-z\-\d]*)\b[^a-z]*$connwordform/; 	# get word directly preceding the connective
			$previouswordpos = $1;
			$previousword = $2;
		if ($previousword =~ /^[A-Z]/) {
			$casedpreviousword = lcfirst($previousword); # lowercase them
			}
		else {
			$casedpreviousword = $previousword;
		}
		if ($connwordform =~ /$casedconnective/) {
			$casedpreviousword = "NOPR";			# if there is no previous word (i.e. the connective is the first word)
			$previouswordpos = "NOPOS";			# if there is no previous POS tag
		}
		$casedpreviousword = special_chars($casedpreviousword);
		push(@previouswords, $casedpreviousword);
		push(@previouswordsposis, $previouswordpos); 
		push(@wordnetcontext, $casedpreviousword);
		$line =~ /$connwordform[^a-z]*\b([A-Z\d\-\$]{1,8})\s([A-Za-z\-\d]*)/;	# get words directly following the connective
		$followingwordpos = $1;
		$followingword = $2;
		if ($followingword =~ /^[A-Z]/) {
			$casedfollowingword = lcfirst($followingword);	# lowercase them
		}
		else {
			$casedfollowingword = $followingword;
		}
		if ($casedfollowingword eq "") {		
			$casedfollowingword = "NOFO"; # if there is no following word
			$followingwordpos = "NOPOS";  # if there is no following POS tag
		}	
		$casedfollowingword = special_chars($casedfollowingword);	
		push(@followingwords, $casedfollowingword);
		push(@followingwordsposis, $followingwordpos);
		push(@wordnetcontext, $casedfollowingword);
		$line =~ /[^\(]([A-Z\d\-\$]{1,8})\s([A-Za-z\-\d\/\*\.\%\?]*)(#|\))/; # get first word in sentence
		$firstwordsentpos = $1;
		$firstwordsent = $2;
		if ($firstwordsent =~ /^[A-Z]/) {
			$casedfirstwordsent = lcfirst($firstwordsent);	# lowercase them
		}
		else {
			$casedfirstwordsent = $firstwordsent;
		}
		if ($connwordform =~ /$casedconnective/) {		
			$casedfirstwordsent = "NOFIRST";		# if there is no first word (i.e. the connective is the first word)
			$firstwordsentpos = "NOPOS";			# if there is no first POS tag
		}		
		$casedfirstwordsent = special_chars($casedfirstwordsent);	
		push(@firstwordsents, $casedfirstwordsent);
		push(@firstwordsentsposis, $firstwordsentpos);
		push(@wordnetcontext, $casedfirstwordsent);
		$line =~ /([A-Z\d\-\$]{1,8})\s([A-Za-z\-\d\/\*\.\%\?]*)[\)\s]*\(\.\s(\.|\?|\!)/; # get last word in sentence
		$lastwordsentpos = $1;
		$lastwordsent = $2;
		if ($lastwordsent =~ /^[A-Z]/) {
			$casedlastwordsent = lcfirst($lastwordsent);		# lowercase them
		}
		else {
			$casedlastwordsent = $lastwordsent;
		}
		if ($casedlastwordsent eq "" || $casedlastwordsent eq "-LRB-" || $casedlastwordsent eq "-RRB-") {		
			$casedlastwordsent = "NOLAST";				# if there is no last word
			$lastwordsentpos = "NOPOS";
		}			
		$casedlastwordsent = special_chars($casedlastwordsent);	
		push(@lastwordsents, $casedlastwordsent);
		push(@lastwordsentsposis, $lastwordsentpos);
		push(@wordnetcontext, $casedlastwordsent);
		wordnet_relatedness(@wordnetcontext); # \@wordnetcontext contains the 6 context words, calls the sub to calculate their relatedness
		antonyms($line,$counter); # calls the big sub-module to get antonyms found in the whole sentence
		
		# get sentence pattern, 'A,CA' etc.
		my $sentpattern = get_sentence_pattern($line,$connwordform);	
		push(@sentpatterns,$sentpattern);
		# get syntactical ancestor category chains before the connective
		my $categorychain = get_syntax_chain($line,$connwordform);
		push (@syntaxchains, $categorychain);
	   }
	}

	# generate initial feature vector
	for (my $i = 0; $i < scalar(@connwordforms); $i++) {
		my $instanceline;
		$instanceline .= $classes[$i]."\t".$connwordforms[$i]." ".$selfcategories[$i]." ".$firstverbwords[$i]." ".$firstverbs[$i]." ".$auxtypespreceding[$i]." ".$firstverbafterconnwords[$i]." ".$firstverbsafterconn[$i]." ".$auxtypesfollowing[$i]." ".$previouswords[$i]." ".$previouswordsposis[$i]." ".$followingwords[$i]." ".$followingwordsposis[$i]." ".$firstwordsents[$i]." ".$firstwordsentsposis[$i]." ".$lastwordsents[$i]." ".$lastwordsentsposis[$i]." ".$sentpatterns[$i]." ".$syntaxchains[$i]." ".$wordnetvalues[$i]." ".$antonym_chains[$i]."\t";
		push(@instances_all, $instanceline);
		}
	
	print "syntactic features have been extracted...\n";
}

sub create_maxent
{	
	
	# write the initial feature vectors test file

	open (MAXENTFILE, ">$maxentfile") or die "cannot write $maxentfile, $!";
	
	print MAXENTFILE join("\n", @instances_all);		# print all \@data instances
	
	close (MAXENTFILE);
	print "initial MaxEnt test set has been generated as $maxentfile\n";
}

sub wordnet_relatedness
{

  my @wordnetcontext = @_;
	
  my $wordnetwindow = join(" ",@wordnetcontext);
  

  # use this module to generate the WordNet query words (noun#n#X, noun#n#Y)
  my $wsd = WordNet::SenseRelate::AllWords->new (wordnet => $qd,
                                                 wntools => $wntools,
                                                 measure => 'WordNet::Similarity::lesk');

  my @context = $wordnetwindow;
  my @results = $wsd->disambiguate (window => 4,
                                    context => [@context]);	# results contains the six disambiguated noun#n#X, noun#n#Y
  my @wordpairs;
  my ($list) = \@results;
   
  my (@print, $str, $i, $j);

  my $size = @{$list};

  # permute to obtain all possible pairs out of the six words	
  for ($i = 0; $i < 2**$size; $i++) {
     $str = sprintf("%*.*b", $size, $size, $i);
     @print = ();
     for ($j = 0; $j < $size; $j++) {
        if (substr($str, $j, 1)) { push (@print, $list->[$j]); }
     }
     if (scalar(@print) == 2) {		# take only pairs
      	push (@wordpairs, (join(" ", @print)));
     }
  }
  
	my @values;
	my %wordnet_values;
	
	foreach my $pair(@wordpairs) {
   		
   		my $value;
   		my @questionpairs = (split /\s/, $pair); # form arrays of only two elements, i.e. the pair to be queried from WordNet
  
	    if ($questionpairs[0] =~ /#n#/ && $questionpairs[1] =~ /#n#/) {	# construct query for nouns
  			my $wn = WordNet::QueryData -> new;
  			my $measure = WordNet::Similarity::path -> new($wn);
  			
  			if ($wordnet_values{$questionpairs[0].$questionpairs[1]}) {
  					$value = $wordnet_values{$questionpairs[0].$questionpairs[1]};
  			}
  			else {
  				$value = $measure -> getRelatedness($questionpairs[0], $questionpairs[1]);
  				$wordnet_values{$questionpairs[0].$questionpairs[1]} = $value;
  				my ($error, $errorstring) = $measure -> getError();
				$value = "?" if $error;
  			}
  	 	}
  	 	elsif ($questionpairs[0] =~ /#v#/ && $questionpairs[1] =~ /#v#/) { # construct query for verbs
  			my $wn = WordNet::QueryData -> new;
  			my $measure = WordNet::Similarity::path -> new($wn);
  			$value = $measure -> getRelatedness($questionpairs[0], $questionpairs[1]);

  			my ($error, $errorstring) = $measure -> getError();

  			$value = "?" if $error;
  		}
    	else {		# other words cannot be measured by these tools
   			$value = "?";
    	}
    	push(@values, $value);				# \@values contains the chains of 6 elements as one array element
 	}
 	push(@wordnetvalues, join(" ", @values));	# return \@wordnetvalues
}

sub antonyms {
	
	my $line = $_[0];
	my $linenumber = $_[1];

	my @verbs;
	my @auxverbs;
	my @nouns;
	my @adjs;

	my @instances;
	
	my @connectives;
	
	my @connforms;
	my @conntags;
	my $connform;
	my $conntag;
	
	my @finalconnforms;
	my @finalconntags;
	
	my @markerpresence;
	
	my @queryverbs;

	my $verbform;
	my $verbtag;
	my $auxverbform;
	my $auxverbtag;

	my @verbforms;
	my @verbtags;
	my @finalverbforms;
	my @finalverbtags;
	
	my @querynouns;

	my $nounform;
	my $nountag;

	my @nounforms;
	my @nountags;
	my @finalnounforms;
	my @finalnountags;
	
	my @queryadjs;
	
	my $adjform;
	my $adjtag;
	
	my @adjforms;
	my @adjtags;
	my @finaladjforms;
	my @finaladjtags;
	
	my @auxverbforms;
	my @auxverbtags;
	my @finalauxverbforms;
	my @finalauxverbtags;
		
	my $verbwindow;
	my $auxwindow;
	my $nounwindow;
	my $adjwindow;
	
	my @verbreturn;
	my @nounreturn;
	my @adjreturn;
	my @realantonyms;
	my @realnounantonyms;
	my @realadjantonyms;
	
	my @verbpairs;
	my @nounpairs;
	my @adjpairs;
	my @finalverbpairs;
	my @finalnounpairs;
	my @finaladjpairs;
	my @realverbpairs;
	my @realnounpairs;
	my @realadjpairs;
	
	my @finaltemporalfeatures;
		
	my @featurevector;
	
	# get all verbs
	if ($line =~ /VB|MD/) {
	@verbs = $line =~ /\(VP\s\(((VB|MD).*?\))/g;
	foreach my $verb (@verbs) {
			$verb =~ /((VB|MD)([A-Z]{1,3})?)\s(.*?)\)/;
			$verbform = $4;
			$verbtag = $2;
			if ($verbform =~ //) {
				$verbform = "?";
			}
			if ($verbtag =~ //) {
				$verbtag = "?";
			}	
		push(@queryverbs,$verbform);
		push(@verbforms,$verbform);
		push(@verbtags,$verbtag);
	}
	push(@finalverbforms,join("-",@verbforms));
	push(@finalverbtags,join("-",@verbtags));
	
	# get antonyms from WordNet
	$verbwindow = join(" ",@queryverbs);
	@verbreturn = &get_antonyms($verbwindow);
	
	# build verb-antonym pairs
	my $pair;
	foreach my $returnverb (@verbreturn) {
		my @singleantonyms = split(/\-/, $returnverb);
		for (my $i = 0; $i<$#singleantonyms; $i++) {
			if (defined($verbforms[$i])) {
				$pair = $verbforms[$i]."-".$singleantonyms[$i];
			}
			else {
				$pair = "?-".$singleantonyms[$i];
			}
			push(@verbpairs, $pair);
		}
	}
	push(@finalverbpairs,join("-",@verbpairs));
		
	# get temporal features from a Tarsqi parsed file
	@finaltemporalfeatures = &get_temporal_features($linenumber);
	
	
	# get auxiliary verbs
	if ($line =~ /AUX/) {
	@auxverbs = $line =~ /\s\(AUXG?.*?\)/g;
	foreach my $auxverb (@auxverbs) {
			$auxverb =~ /(AUXG?)\s(.*?)\)/;
			$auxverbform = $2;
			$auxverbtag = $1;
			if ($auxverbform =~ //) {
				$auxverbform = "?";
			}
			if ($auxverbtag =~ //) {
				$auxverbtag = "?";
			}
		push(@auxverbforms, $auxverbform);
		push(@auxverbtags, $auxverbtag);
	}
	}
	else {
		push(@auxverbforms, "?");
		push(@auxverbtags, "?");
	}
	push(@finalauxverbforms,join("-",@auxverbforms));
	push(@finalauxverbtags,join("-",@auxverbtags));
	
	# get all connectives, prepositions, adverbs
	if ($line =~ /CC|RB|IN/) {
	@connectives = $line =~ /\s\(((CC|RB|IN).*?\))/g;
	foreach my $connective (@connectives) {
			$connective =~ /(CC|RB|IN)\s(.*?)\)/;
			$connform = $2;
			$conntag = $1;
			if ($connform =~ //) {
				$connform = "?";
			}
			if ($conntag =~ //) {
				$conntag = "?";
			}	
		push(@connforms,$connform);
		push(@conntags,$conntag);
	}
	}
	else {
		push(@connforms,"?");
		push(@conntags,"?");
	}
	push(@finalconnforms,join("-",@connforms));
	push(@finalconntags,join("-",@conntags));
	

	# get all nouns
	if ($line =~ /NN/) {
		@nouns = $line =~ /\s\((NN.*?\))/g;
		foreach my $noun (@nouns) {
			$noun =~ /(NN.*?)\s(.*?)\)/;
			$nounform = $2;
			$nountag = $1;
			if ($nounform =~ //) {
				$nounform = "?";
			}
			if ($nountag =~ //) {
				$nountag = "?";
			}	
			push(@querynouns,$nounform);
			push(@nounforms,$nounform);
			push(@nountags,$nountag);
		}
	}
	else {
		push(@nounforms,"?");
		push(@nountags,"?");
	}
	push(@finalnounforms,join("-",@nounforms));
	push(@finalnountags,join("-",@nountags));
	
	# get antonyms
	$nounwindow = join(" ",@querynouns);
	@nounreturn = &get_antonyms($nounwindow);
	
	# build noun-antonym pairs
	my $nounpair;
	foreach my $returnverb (@nounreturn) {
		my @singleantonyms = split(/\-/, $returnverb);
		for (my $i = 0; $i<$#singleantonyms; $i++) {
			if (defined($nounforms[$i])) {
				$nounpair = $nounforms[$i]."-".$singleantonyms[$i];
			}
			else {
				$nounpair = "?-".$singleantonyms[$i];
			}
			push(@nounpairs, $nounpair);
		}
	}
	push(@finalnounpairs,join("-",@nounpairs));
	
	# get all adjectives
	if ($line =~ /JJ/) {
		@adjs = $line =~ /\s\((JJ.*?\))/g;
		foreach my $adj (@adjs) {
			$adj =~ /(JJ.*?)\s(.*?)\)/;
			$adjform = $2;
			$adjtag = $1;
			if ($adjform =~ //) {
				$adjform = "?";
			}
			if ($adjtag =~ //) {
				$adjtag = "?";
			}	
			push(@queryadjs,$adjform);
			push(@adjforms,$adjform);
			push(@adjtags,$adjtag);
		}
	}
	else {
		push(@adjforms,"?");
		push(@adjtags,"?");
	}
	push(@finaladjforms,join("-",@adjforms));
	push(@finaladjtags,join("-",@adjtags));
	
	# get antonyms
	$adjwindow = join(" ",@queryadjs);
	@adjreturn = &get_antonyms($adjwindow);
	
	# build noun-antonym pairs
	my $adjpair;
	foreach my $returnadj (@adjreturn) {
		my @singleantonyms = split(/\-/, $returnadj);
		for (my $i = 0; $i<$#singleantonyms; $i++) {
			if (defined($adjforms[$i])) {
				$adjpair = $adjforms[$i]."-".$singleantonyms[$i];
			}
			else {
				$adjpair = "?-".$singleantonyms[$i];
			}
			push(@adjpairs, $adjpair);
		}
	}
	push(@finaladjpairs,join("-",@adjpairs));
	}
	
	else {
		push(@verbforms,"?");
		push(@verbtags,"?");
		push(@verbreturn,"?");
		if ($line =~ /AUX/) {
			@auxverbs = $line =~ /\s\(AUXG?.*?\)/g;
		foreach my $auxverb (@auxverbs) {
			$auxverb =~ /(AUXG?)\s(.*?)\)/;
			$auxverbform = $2;
			$auxverbtag = $1;
			if ($auxverbform =~ //) {
				$auxverbform = "?";
			}
			if ($auxverbtag =~ //) {
				$auxverbtag = "?";
			}
		push(@auxverbforms, $auxverbform);
		push(@auxverbtags, $auxverbtag);
		}
		}
		else {
			push(@auxverbforms, "?");
			push(@auxverbtags, "?");
		}
		
		# get all connectives, prepositions, adverbs
		if ($line =~ /CC|RB|IN/) {
		@connectives = $line =~ /\s\(((CC|RB|IN).*?\))/g;
		foreach my $connective (@connectives) {
			$connective =~ /(CC|RB|IN)\s(.*?)\)/;
			$connform = $2;
			$conntag = $1;
			if ($connform =~ //) {
				$connform = "?";
			}
			if ($conntag =~ //) {
				$conntag = "?";
			}	
		push(@connforms,$connform);
		push(@conntags,$conntag);
		}
		}
		else {
			push(@connforms,"?");
			push(@conntags,"?");
		}
		
		# get all nouns
		if ($line =~ /NN/) {
		@nouns = $line =~ /\s\((NN.*?\))/g;
		foreach my $noun (@nouns) {
			$noun =~ /(NN.*?)\s(.*?)\)/;
			$nounform = $2;
			$nountag = $1;
			if ($nounform =~ //) {
				$nounform = "?";
			}
			if ($nountag =~ //) {
				$nountag = "?";
			}	
			push(@querynouns,$nounform);
			push(@nounforms,$nounform);
			push(@nountags,$nountag);
		}
		}
		else {
			push(@nounforms,"?");
			push(@nountags,"?");
		}
	
		# get antonyms
		$nounwindow = join(" ",@querynouns);
		@nounreturn = &get_antonyms($nounwindow);
		
		# build noun-antonym pairs
		my $nounpair;
		foreach my $returnverb (@nounreturn) {
			my @singleantonyms = split(/\-/, $returnverb);
				for (my $i = 0; $i<$#singleantonyms; $i++) {
					if (defined($nounforms[$i])) {
						$nounpair = $nounforms[$i]."-".$singleantonyms[$i];
					}
					else {
						$nounpair = "?-".$singleantonyms[$i];
					}
				push(@nounpairs, $nounpair);
				}
		}
		push(@finalnounpairs,join("-",@nounpairs));
		
		# get all adjectives
		if ($line =~ /JJ/) {
			@adjs = $line =~ /\s\((JJ.*?\))/g;
			foreach my $adj (@adjs) {
				$adj =~ /(JJ.*?)\s(.*?)\)/;
				$adjform = $2;
				$adjtag = $1;
				if ($adjform =~ //) {
					$adjform = "?";
				}
				if ($adjtag =~ //) {
					$adjtag = "?";
				}	
				push(@queryadjs,$adjform);
				push(@adjforms,$adjform);
				push(@adjtags,$adjtag);
			}
		}
		else {
			push(@adjforms,"?");
			push(@adjtags,"?");
		}
		push(@finaladjforms,join("-",@adjforms));
		push(@finaladjtags,join("-",@adjtags));
	
		# get antonyms
		$adjwindow = join(" ",@queryadjs);
		@adjreturn = &get_antonyms($adjwindow);
	
		# build noun-antonym pairs
		my $adjpair;
		foreach my $returnadj (@adjreturn) {
			my @singleantonyms = split(/\-/, $returnadj);
			for (my $i = 0; $i<$#singleantonyms; $i++) {
				if (defined($adjforms[$i])) {
					$adjpair = $adjforms[$i]."-".$singleantonyms[$i];
				}
				else {
					$adjpair = "?-".$singleantonyms[$i];
				}
				push(@adjpairs, $adjpair);
			}
		}
		push(@finaladjpairs,join("-",@adjpairs));
		
		push(@finalverbforms,join("-",@verbforms));
		push(@finalverbtags,join("-",@verbtags));
		push(@finalauxverbforms,join("-",@auxverbforms));
		push(@finalauxverbtags,join("-",@auxverbtags));
		push(@finalconnforms,join("-",@connforms));
		push(@finalconntags,join("-",@conntags));
		push(@finalnounforms,join("-",@nounforms));
		push(@finalnountags,join("-",@nountags));
		push(@finaladjforms,join("-",@adjforms));
		push(@finaladjtags,join("-",@adjtags));
	}
	my @dummyverbreturn = @verbreturn;
	my @dummynounreturn = @nounreturn;
	my @dummyadjreturn = @adjreturn;
	
	# get real verb antonyms only
	foreach my $antonym (@dummyverbreturn) {
		if ($antonym =~ /#/) {
			$antonym =~ s/(\?\-|\-\W)*//g;
			push (@realantonyms, $antonym);
		}
		else {
			push (@realantonyms, "?");
		}
	}
	
	# get real noun antonyms only
	foreach my $antonym (@dummynounreturn) {
		if ($antonym =~ /#/) {
			$antonym =~ s/(\?\-|\-\W)*//g;
			push (@realnounantonyms, $antonym);
		}
		else {
			push (@realnounantonyms, "?");
		}
	}
	
	# get real adj antonyms only
	foreach my $antonym (@dummyadjreturn) {
		if ($antonym =~ /#/) {
			$antonym =~ s/(\?\-|\-\W)*//g;
			push (@realadjantonyms, $antonym);
		}
		else {
			push (@realadjantonyms, "?");
		}
	}
	
	# get real verb pairs only
	my @dummyverbpairs = @finalverbpairs;
	my @verb_antonym_found;
	my @verb_antonyms_found;
	
	foreach my $dummypair (@dummyverbpairs) {
		if ($dummypair =~ /#/) {
			@verb_antonym_found = &infer_antonyms($line,$dummypair);
			$dummypair =~ s/(\?\-|\-\W)*//g;
			#DEBUG:
			# print "$dummypair\n";
			push (@realverbpairs, $dummypair);
			push(@verb_antonyms_found,join("-",@verb_antonym_found));
		}
		else {
			push (@realverbpairs, "?");
			push(@verb_antonyms_found, "?");
		}
	}
	
	# get real noun pairs only
	my @dummynounpairs = @finalnounpairs;
	
	foreach my $dummypair (@dummynounpairs) {
		if ($dummypair =~ /#/) {
			$dummypair =~ s/(\?\-|\-\W)*//g;
			push (@realnounpairs, $dummypair);
		}
		else {
			push (@realnounpairs, "?");
		}
	}
	
	# get real adjective pairs only
	my @dummyadjpairs = @finaladjpairs;
	
	foreach my $dummypair (@dummyadjpairs) {
		if ($dummypair =~ /#/) {
			$dummypair =~ s/(\?\-|\-\W)*//g;
			push (@realadjpairs, $dummypair);
		}
		else {
			push (@realadjpairs, "?");
		}
	}
		
	@featurevector = join(" ",@finalconnforms,@finalconntags,@finalverbforms,@finalverbtags,@finalnounforms,@finalnountags,@finaladjforms,@finaladjtags,@verbreturn,@nounreturn,@adjreturn,@realantonyms,@realnounantonyms,@realadjantonyms,@finalverbpairs,@finalnounpairs,@finaladjpairs,@realverbpairs,@realnounpairs,@finaladjpairs,@finalauxverbforms,@finalauxverbtags,join("-",@finaltemporalfeatures),@verb_antonyms_found); # @verb_antonyms_found,@noun_antonyms_found,@adj_antonyms_found
	
	push(@antonym_chains, join(" ", @featurevector));
}

sub get_antonyms {
		
		my @final_antonyms;
		
		my $wordnetwindow = $_[0];
	
		# use SenseRelate to generate the WordNet query words (noun#n#X, noun#n#Y)
  		my $wsd = WordNet::SenseRelate::AllWords->new (wordnet => $qd,
                                                 wntools => $wntools,
                                                 measure => 'WordNet::Similarity::lesk');

  		my @context = $wordnetwindow;
  		my @results = $wsd->disambiguate (window => 4, context => [@context]);	# results contains the six disambiguated noun#n#X, noun#n#Y
 		my $wn = WordNet::QueryData -> new( noload => 1);
 		
  		# start to get antonyms
  		my @antonyms;
  		
  		foreach my $word(@results) {
  		 	
  		 	my @questionwords = (split /\s/, $word); # form arrays of only two elements, i.e. the pair to be queried from WordNet
 
			my $antonym;

 			foreach my $queryword (@questionwords) {
 				if ($queryword !~ /#\w#/) {
 					$queryword = "?";
 				}
 				$antonym = join("-", $wn->queryWord($queryword, "ants"));
				if ($antonym !~ /#/) {
					$antonym = "?";
				}
 			}
 			push (@antonyms, $antonym);	
  		}
  		push(@final_antonyms, join("-", @antonyms));
	 	my @return = @final_antonyms;
}

sub infer_antonyms
{
	my $line = $_[0];
	my $pair = $_[1];
	
	my $answer;
	my @answers;
	
	my @words = split(/\-/, $pair);
	
	for (my $i = 0; $i <= $#words; $i++) {
		if ($words[$i] !~ /\?/ && $words[$i + 1] !~ /\?/ && $line =~ /$words[$i]/ && $line =~ /$words[$i + 1]/) {
			$answer = "yes";
		}
		else {
			$answer = "no";
		}
		push (@answers,$answer);
	}
	my @return = @answers;
}

sub get_temporal_features {
	
	my @finalevents;
	my @finallinks;
	my @temporalfeatures;
	
	my $linenumber = $_[0];
	
	# open tarsqi - processed file ***with same line number as above input file***
	open(TARSQI, "<$tarsqifile") or die "cannot read $tarsqifile, $!";
	while (<TARSQI>) {
		if ($. == $linenumber) {
			my @events = $_ =~ /(<EVENT.*?<\/MAKEINSTANCE>)/g;
			foreach my $event (@events) {
				$event =~ /<EVENT.*?class="(.*?)">(.*?)<.*?polarity="(.*?)".*?\seiid="(.*?)".*?tense="(.*?)"\saspect="(.*?)"/;
				my $eventclass = $1;
				if ($eventclass =~ //) {
					$eventclass = "?";
				}
				my $verb = $2;
				if ($verb =~ //) {
					$verb = "?";
				}
				my $polarity = $3;
				if ($polarity =~ //) {
					$polarity = "?";
				}
				my $id = $4;
				if ($id =~ //) {
					$id = "?";
				}
				my $tense = $5;
				if ($tense =~ //) {
					$tense = "?";
				}
				my $aspect = $6;
				if ($aspect =~ //) {
					$aspect = "?";
				}
				my $finalevent = $eventclass."-".$verb."-".$polarity."-".$id."-".$tense."-".$aspect;
				push(@finalevents, $finalevent);
			}
			my @tlinks = $_ =~ /(<TLINK\slid="l\d*?"\srelatedToEventInstance="[a-z][a-z]\d*?"\srelType="[A-Z]*?"\seventInstanceID="[a-z][a-z]\d*?"\sorigin="CLASSIFIER\s[\d\.]*?"><\/TLINK>)/g;
			foreach my $tlink (@tlinks) {
				$tlink =~ /<TLINK.*?\srelatedToEventInstance="(.*?)"\srelType="(.*?)"\seventInstanceID="(.*?)"/;
				my $event1 = $1;
				if ($event1 =~ //) {
					$event1 = "?";
				}
				my $event2 = $3;
				if ($event2 =~ //) {
					$event2 = "?";
				}
				my $eventtype = $2;
				if ($eventtype =~ //) {
					$eventtype = "?";
				}
				my $finallink = $event1."-".$event2."-".$eventtype;
				push(@finallinks, $finallink);
			}
			my $temporalfeature;
			for (my $i = 0; $i < $#finalevents; $i++) {
				if (defined($finallinks[$i])) {
					$temporalfeature = $finalevents[$i]."-".$finallinks[$i];
				}
				else {
					$temporalfeature = $finalevents[$i]."-?";
				}
				push(@temporalfeatures, $temporalfeature);
			}
		}
	}
	close(TARSQI);
	my @return = @temporalfeatures;	
}

sub create_maxent_extended {
	
	my @dep_features = dependency_features();

	open (MAXENTFILE, "<$maxentfile") or die "cannot read $maxentfile, $!";
	open (MANGLEDFILE, ">$maxentfile_extended") or die "cannot write $maxentfile_extended, $!";

	print "normalizing feature vectors and getting dependency features...\n";

	while(<MAXENTFILE>) {
		$_ =~ /(.*?)\|\s(.*?)\s([A-Za-z].*?)\t/;
		my $normalfeatures = $1;
		my $wordnetvalues = $2;
		my $remainingfeatures = $3;
		$normalfeatures =~ s/\s/\t/g;
		my @wordnetvalues = $wordnetvalues =~ /([\d\.\?]*)/g;
		my @wordnetvalues_1 = join('#',@wordnetvalues);
		my $finalvalue;
		foreach my $value (@wordnetvalues_1) {
			my $newvalue = "#".$value;
			my @values = $newvalue =~ /#(\d.*?)#/g;
			$finalvalue = &calculate_wordnet_value(@values);
		}
	
		$remainingfeatures =~ /([A-Za-z\-#\d\?]*?#[a-z]#\d[A-Za-z\-\?\.]*?)\s((has|had|have|having|are|be|is|were|being|do|does|done|doing|need|needed|needing).*?)\s/;
		my $synonyms = $1;
		my $auxverbs = $2;

		if ($synonyms =~ // || $auxverbs =~ //) {
			$synonyms = "?";
			$_ =~ /([a-z\-]*?)\s([A-Z\-]*?)?AUXG?\s[A-Z]/;
			$auxverbs = $1;
		if ($auxverbs =~ //) {
			$auxverbs = "?";
		}		
	}
	$_ =~ /((OCCURRENCE|STATE|I_ACTION|I_STATE|ASPECTUAL|PERCEPTION|REPORTING).*?)\t/;
	my $timefeatures = $1;
	my @timevalues = $timefeatures =~ /[A-Z]*\-/g;
	foreach my $value (@timevalues) {
		$value =~ s/\-//g;
	}
	my @timevalues_1 = join('#',@timevalues);
	my @final_timevalues;
	foreach my $value (@timevalues_1) {
		$value =~ s/#+/#/g;
		my $newvalue = "#".$value;
		my @intermediate = $newvalue =~ /#([A-Z]*?)#/g;
		
		my %seen;
		my @unique;
	
		foreach my $item (@intermediate){
			push(@unique, $item) unless $seen{$item}++; 
		}		
		
		#DEBUG:
		# print "@intermediate\n";
		@final_timevalues = join('-', @unique);
	}	
		
	$_ =~ s/.*?\|\s.*?\s[A-Za-z].*?\t/$normalfeatures\|\t$finalvalue\t$synonyms\t$auxverbs\t@final_timevalues\t@dep_features[$.-1]/;
	print MANGLEDFILE;
	}
	close(MAXENTFILE);
	close(MANGLEDFILE);
	unlink ("$maxentfile");
	print "Dependency features extracted, cleaned feature vectors. The MaxEnt test set is created in $maxentfile_extended\n";

	sub calculate_wordnet_value {
	
		my @wordnetvalues = @_;
		my $finalvalue;
		my $intermediate;
	
		if ($#wordnetvalues == -1)  {
 			$finalvalue = "?";
 		}
 		elsif ($#wordnetvalues == 0) {
 			$intermediate = $wordnetvalues[0];
 			$finalvalue = sprintf "%.2f", $intermediate;
 		}
 		else {   
			foreach my $value (@wordnetvalues) {
				$intermediate += $value;
			}
			$finalvalue = sprintf "%.2f", $intermediate;
		}
		return $finalvalue;	
	}

	sub dependency_features {
		
	open (DEPPARSEDFILE_CLEAN, "<$depparsedfile.clean") or die "cannot read $depparsedfile.clean, $!";
		my @depparsedfile_content = <DEPPARSEDFILE_CLEAN>;
	close(DEPPARSEDFILE_CLEAN);
			
	my @instances_all;

	my $connwordform;
	my @connwordforms;
	my $selfdependence;
	my @selfdependencies;
	my $selfposition;
	my @selfpositions;
	my $firstverb;
	my @firstverbs;
	my $firstverbdependency;
	my @firstverbdependencies;
	my $firstverbposition;
	my @firstverbpositions;
	my $firstverbafterconn;
	my @firstverbsafterconn;
	my $firstverbafterconndependency;
	my @firstverbafterconndependencies;
	my $firstverbafterposition;
	my @firstverbafterpositions;
	my $previousword;
	my @previouswords;
	my $previousworddependency;
	my @previousworddependencies;
	my @previouswordposis;
	my $previouswordposition;
	my @previouswordpositions;
	my $followingword;
	my @followingwords;
	my $followingworddependency;
	my @followingworddependencies;
	my $followingwordposition;
	my @followingwordpositions;

	my $casedconnective = ucfirst($connective);

	my $counter = 0;

	foreach my $line (@depparsedfile_content) {
	$counter++;
	#DEBUG:
	# print "$counter\n";
	print "could not find $connective in $counter\n" if $line !~ /$casedconnective|$connective/;
	# get connwordforms (connective phrases first, then normal forms), their class, self-category, previous and following words
	if ($line =~ /($casedconnective|$connective)/) {			# get connective word form and label
		$connwordform = $1;
		push(@connwordforms, $connwordform);
		$line =~ /([A-Z]*)_([\d]{1,3})_([A-Za-z_\|]*)\s\"?($casedconnective|$connective)/; # get POS and dependency tags for the connective
		$selfdependence = $3;
		$selfposition = $2;
		if ($selfposition eq "") {
			$selfposition = "0";
		}
		if ($selfdependence eq "") {
			$selfdependence = "NODEP";
		}
		push(@selfdependencies, $selfdependence);
		push(@selfpositions, $selfposition);
		# get the first verb in the sentence and its dependency label
		$line =~ /\((V[A-Z]{1,3})_([\d]{1,3})_([A-Za-z_\|]*)\s(.*?),?\).*?($casedconnective|$connective)/;
		$firstverb = $4;
		$firstverbdependency = $3;
		$firstverbposition = $2;
		if ($firstverb eq "" || $firstverb eq "$connective" || $connwordform =~ /[A-Z]/) { # if there is no verb preceding the connective
			$firstverb = "NOVERB";
			$firstverbdependency = "NODEP";
		}
		if ($firstverbposition eq "") {
			$firstverbposition = "0";
		}
		if ($firstverbdependency eq "") {
			$firstverbdependency = "NODEP";
		}
		push (@firstverbdependencies, $firstverbdependency);
		push (@firstverbs, $firstverb);
		push (@firstverbpositions,$firstverbposition);
		unless ($line !~ /($casedconnective|$connective).*?\((V[A-Z]{1,3})_([\d]{1,3})_([A-Za-z_\|]*)\s(.*?)\,?\)\s/) {
		$line =~ /($casedconnective|$connective).*?\((V[A-Z]{1,3})_([\d]{1,3})_([A-Za-z_\|]*)\s(.*?)\,?\)\s/;	# get first verb following connective and its dependency label
		$firstverbafterconn = $5;
		$firstverbafterconndependency = $4;
		$firstverbafterposition = $3;
		if ($firstverbafterconn eq "") { 	# if there is no verb following the connective
			$firstverbafterconn = "NOVERB";
			$firstverbafterconndependency = "NODEP";
		}
		}
		else {
			$firstverbafterconn = "NOVERB";
			$firstverbafterposition = "0";
			$firstverbafterconndependency = "NODEP";
			
		}
		if ($firstverbafterposition eq "") {
			$firstverbafterposition = "0";
		}
		if ($firstverbafterconndependency eq "") {
			$firstverbafterconndependency = "NODEP";
		}
		push (@firstverbafterconndependencies, $firstverbafterconndependency);
		push (@firstverbsafterconn, $firstverbafterconn);
		push (@firstverbafterpositions, $firstverbafterposition);			 
		$line =~ /\(([A-Z]*)_([\d]{1,3})_([A-Za-z_\|]*)\s([A-Za-z\.\,\:\'\;\?\!\-\=\>\<\"äüößėèòàéùìâæçÿûïîíôœëêµńáó\«\“\”\»\%\+\/\d]*)\)\s\([A-Z]*_[\d]{1,3}_[A-Za-z_]*\s($casedconnective|$connective)/; # get word directly preceding the connective, its POS tag and dependency label
		$previousword = $4;
		$previousworddependency = $3;
		$previouswordposition = $2;		
		if ($connwordform =~ /[A-Z]/ || $previousword eq "") { # if there is no prev. word
			$previousword = "NOPR";
			$previousworddependency = "NODEP";		
		}
		$previousword = special_chars($previousword);
		if ($previouswordposition eq "") {
			$previouswordposition = "0";
		}
		if ($previouswordposition =~ /[A-Z]/) {
			$previouswordposition = "0";
		}
		if ($previousworddependency eq "") {
			$previousworddependency = "NODEP";
		}
		push(@previousworddependencies, $previousworddependency);		
		push(@previouswords, $previousword);
		push(@previouswordpositions, $previouswordposition);
		unless ($line =~ /($casedconnective|$connective)\.\)$/) {
		$line =~ /($casedconnective|$connective).*?\(([A-Z]*)_([\d]{1,3})_([A-Za-z_\|]*)\s([A-Za-z\.\,\:\'\;\?\!\-\=\>\<\"äüößėèòàéùìâæçÿûïîíôœëêµńáó\«\“\”\»\%\+\/\d]*)/; # get word directly following the connective, its POS tag and dependency label
		$followingword = $5;
		$followingworddependency = $4;
		$followingwordposition = $3;
		if ($followingword eq "") {				# if there is no following word
			$followingword = "NOFO";
			$followingworddependency = "NODEP";			
		}
		}
		else {
			$followingword = "NOFO";
			$followingwordposition = "0";
			$followingworddependency = "NODEP";
		}
		$followingword = special_chars($followingword);
		if ($followingwordposition eq "") {
			$followingwordposition = "0";
		}
		if ($followingworddependency eq "") {
			$followingworddependency = "NODEP";
		}	
		push(@followingworddependencies, $followingworddependency);		
		push(@followingwords, $followingword);
		push(@followingwordpositions, $followingwordposition);
	}
	}
	
	#DEBUG:
	# print "$#connwordforms";
	
	# create final MaxEnt instances
	for (my $i = 0; $i <= $#connwordforms; $i++) {
		my $instanceline;
		if ($selfpositions[$i] =~ /[A-Za-z]/) {
			$selfpositions[$i] = "0";	
		}
		if ($firstverbpositions[$i] =~ /[A-Za-z]/) {
			$firstverbpositions[$i] = "0";	
		}
		if ($previouswordpositions[$i] =~ /[A-Za-z]/) {
			$previouswordpositions[$i] = "0";	
		}
		if ($followingwordpositions[$i] =~ /[A-Za-z]/) {
			$followingwordpositions[$i] = "0";	
		}
		if ($firstverbafterpositions[$i] =~ /[A-Za-z]/) {
			$firstverbafterpositions[$i] = "0";	
		}
		$instanceline .= $selfdependencies[$i]."\t".$selfpositions[$i]."\t".$firstverbs[$i]."\t".$firstverbdependencies[$i]."\t".$firstverbpositions[$i]."\t".$previouswords[$i]."\t".$previousworddependencies[$i]."\t".$previouswordpositions[$i]."\t".$followingwords[$i]."\t".$followingworddependencies[$i]."\t".$followingwordpositions[$i]."\t".$firstverbsafterconn[$i]."\t".$firstverbafterconndependencies[$i]."\t".$firstverbafterpositions[$i];
		push(@instances_all, $instanceline);
	}
	return @instances_all;	
	}	
}

sub clean_dependency {
	open (DEPPARSEDFILE, "<$depparsedfile") or die "cannot read $depparsedfile, $!";
	open (DEPPARSEDFILE_INT, ">$depparsedfile.int") or die "cannot write $depparsedfile.int, $!";
	
	while (<DEPPARSEDFILE>) {
		unless ($_ !~ /^\d{1,3}\t/) {
			if ($_ =~ /(\.\.\.|\.|\?|\!|\;|\:|\.\"|\?\")\t.*?ROOT/) {
				print DEPPARSEDFILE_INT "$_\n";
			}
			else {
				print DEPPARSEDFILE_INT $_;
			}
		}	
	}
	close (DEPPARSEDFILE);
	close (DEPPARSEDFILE_INT);
	
	`sh ./normalize_dependency_parses.sh < $depparsedfile.int > $depparsedfile.clean`;
	
	wait;
	
	unlink("$depparsedfile.int");
}

sub special_chars {
	
	my $text = $_[0];
	
	if ($text =~ /(\%|\,|\'|\"|\,)/) {
		my $special_char = $1;
		$text =~ s/(.*?)$special_char.*/\1/; 
	}	
	return $text;
}

sub normalize_auxtype {
	
	my $auxverb = $_[0];
	
	my $auxtype;
	
	if ($auxverb =~ /am|is|are/) {	     # generalize the aux type
					$auxtype = "be_present";
				}
				elsif ($auxverb =~ /was|were/) {
					$auxtype = "be_past";
				}
				elsif ($auxverb =~ /been/) {
					$auxtype = "be_part";
				}
				elsif ($auxverb =~ /being/) {
					$auxtype = "be_gerund";
				}
				elsif ($auxverb =~ /be/) {
					$auxtype = "be_inf";
				}
				elsif ($auxverb =~ /has/) {
					$auxtype = "have_third";
				}
				elsif ($auxverb =~ /have/) {
					$auxtype = "have_inf";
				}
				elsif ($auxverb =~ /having/) {
					$auxtype = "have_gerund";
				}
				elsif ($auxverb =~ /had/) {
					$auxtype = "have_past";
				}
				elsif ($auxverb =~ /done/) {
					$auxtype = "do_part";
				}
				elsif ($auxverb =~ /does/) {
					$auxtype = "do_third";
				}
				elsif ($auxverb =~ /do/) {
					$auxtype = "do_inf";
				}
				elsif ($auxverb =~ /did/) {
					$auxtype = "do_past";
				}
				elsif ($auxverb =~ /need/) {
					$auxtype = "need_inf";
				}
		else {
			$auxtype = "not_found";	       # for sentences without auxiliary verb
		}
	return $auxtype;
}

sub get_sentence_pattern {
	
	my $sentence = $_[0];
	my $connwordform = $_[1];
	my $sentpattern;
	
	if ($sentence !~ /\,/) {
			if ($connwordform =~ /^[A-Z]/) {
				$sentpattern = "'CA'";
			}
			else {
				$sentpattern = "'ACA'";
			}	
		 }
		 else {
		  if ($connwordform =~ /^[A-Z]/) {
		 	if ($sentence =~ /$connwordform[A-Za-z\/\.]*\)[\)\s]*\(\,/) {
				$sentpattern = "'C,A'";
			}
			else {
				$sentpattern = "'CA,A'";
			}
		  }	
		  else {
			if ($sentence =~ /\,\)\s\([A-Z\-\$]{1,}\s\([^\(][A-Z\-\$]{1,8}\s$connwordform[A-Za-z\.\/]*\)\s\(,/) {	# modify spaces according to parsed format !!!
					$sentpattern = "'A,C,A'";
			}
			elsif ($sentence =~ /\,\)\s\([A-Z\-\$]{1,8}\s(\([A-Z\-\$]{1,8})?\s$connwordform/) {
					$sentpattern = "'A,CA'";
			}
			elsif ($sentence =~ /$connwordform[A-Za-z\.\/]*\)\s\(\,/) { 
					$sentpattern = "'AC,A'";
			}
			elsif ($sentence =~ /.+?\(\,.+?$connwordform.+?\s\(\,/) {	
					$sentpattern = "'A,ACA,A'";
			}
			elsif ($sentence =~ /((?!\,).)+?$connwordform.+?\s\(\,/) { 
					$sentpattern = "'ACA,A'";	
			}
			elsif ($sentence =~ /\s\(\,.+?$connwordform/) {
					$sentpattern = "'A,ACA'";	
			}
		  }
		}
		return $sentpattern;	
}

sub get_syntax_chain {
		
		my $line = $_[0];
		my $connwordform = $_[1];
		my $categorychain;
		my @categories;
		my @syntaxchains;
		
		if ($connwordform =~ /^[A-Z]/) {
			if ($line =~ /([A-Z\-\$]{1,8})\s$connwordform/) {
			my $selfpos = $1;
			@categories = ($line =~ /\(([A-Z\-\$\d]{1,8})/g);
			my $i = 0;
			do {
				$categorychain .= "|".$categories[$i]."|";
				$i++;
			} until ($categories[$i] eq $selfpos || $i == 5); # restrict to a certain number or until POS matches actual connective
			push (@syntaxchains, $categorychain);
			}
		}	
		elsif ($line =~ /([A-Z\-\$]{1,8})\s$connwordform/) {
			my $selfpos = $1;
			@categories = ($line =~ /\(([A-Z\-\$\d]{1,8})/g);  
			my $i = 0;
			do {
				$categorychain .= "|".$categories[$i]."|";
				$i++;
			} until ($categories[$i] eq $selfpos || $i == 5);  # restrict to a certain number or until POS matches actual connective
		}
		return $categorychain;
}
