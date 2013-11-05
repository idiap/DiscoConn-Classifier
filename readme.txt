DiscoConn-Classifiers
=====================

Copyright (c) 2013 Idiap Research Institute, http://www.idiap.ch/
Written by Thomas Meyer, Thomas.Meyer (at) idiap.ch , ithurtstom (a) gmail.com
See LICENSE.txt for the GPL v3 license text under which this software is released.

This package consists of the following:

1. Classifier models in order to tag instances of 7 discourse connectives according to the discourse relation they signal in raw and unseen English text
2. A feature extraction script in order to generate test instances and feature vectors for the connectives to disambiguate

See the sections below for instructions on how to run the scripts.

If you make use of this software, please consider citing the following papers:

@INPROCEEDINGS{Meyer-HyTra-2012,
  author = {Meyer, Thomas and Popescu-Belis, Andrei},
  title = {{Using Sense-labeled Discourse Connectives for Statistical Machine
	Translation}},
  booktitle = {Proceedings of the EACL 2012 Joint Workshop on Exploiting Synergies
	between IR and MT, and Hybrid Approaches to MT (ESIRMT-HyTra)},
  year = {2012},
  pages = {129--138},
  address = {Avignon, FR}
}

@INPROCEEDINGS{Meyer-AMTA-2012,
  author = {Meyer, Thomas and Popescu-Belis, Andrei and Hajlaoui, Najeh and Gesmundo,
	Andrea},
  title = {{Machine Translation of Labeled Discourse Connectives}},
  booktitle = {Proceedings of the Tenth Biennial Conference of the Association for
	Machine Translation in the Americas (AMTA)},
  year = {2012},
  address = {San Diego, CA}
}

--------------------------------------------------
Instructions: Disambiguating Discourse Connectives
--------------------------------------------------

Dependencies:

Install WordNet (http://wordnet.princeton.edu/) and set the environment variable WNHOME to its directory
Install the perl module WordNet::QueryData from cpan: http://search.cpan.org/~jrennie/WordNet-QueryData-1.49/QueryData.pm
You can point to it from the parsedUnseenExtractor.pl script in line 53.
Install the Stanford classifier (http://nlp.stanford.edu/software/classifier.shtml)

Procedure:

1. Prepare a raw UTF-8 text file of your English text in which you want classify the connectives

2. With the script extract_connectives.pl, you can obtain sentences with connectives only, by executing:

./extract_connectives.pl textfile.txt (although|however|meanwhile|since|though|while|yet)

by choosing only one connective at a time.

3. Parse these extracted sentences with:

a) a constituency parser (e.g. https://github.com/BLLIP/bllip-parser), with bracketed tree output (a la PTB)
b) a TimeML parser (http://www.timeml.org/site/tarsqi/toolkit/)
c) a dependency parser (e.g. https://github.com/agesmundo/IDParser), with output in CONLL format

and put the parsed files into corresponding directories.

4. Point to these directories in the code of the script parsedUnseenExtractor.pl and execute:

./parsedUnseenExtractor.pl (although|however|meanwhile|since|though|while|yet) directory/

Note that this can take time for a larger set of sentences, as a lot of queries to WordNet are needed.

5. On the test set output, you can now run the classifier models (which are in the subdirectory 'models' of this package):

./java -Xms1g -Xmx3g -jar /path/to/classifier/stanford-classifier.jar -props /path/to//models/(although|although|however|meanwhile|since|though|while|yet).prop

In the prop-files, change the paths to the models and to the test sets.
The classifier outputs a file classifier_answers.txt with the predicted discourse relations and probabilities.
The possible relations for the connectives are:

although (contrast|concession)
however (contrast|concession)
meanwhile (contrast|temporal)
since (causal|temporal|temporal-causal)
though (contrast|concession)
while (contrast|concession|temporal|temporal-contrast|temporal-causal)
yet (adv|contrast|concession)

For an explanation and an example of the 36 features extracted, please see 'feature_list.txt'.
The format is: feature name TAB example value

If you would like to retrain your own models, the manual gold annotation in Europarl text can be obtained from https://www.idiap.ch/dataset/Disco-Annotation

Please contact Thomas.Meyer (at) idiap.ch or ithurstom (a) gmail.com for any questions.
