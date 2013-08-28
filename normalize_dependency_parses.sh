#!/bin/bash

# Normalizes dependency parses to a PTB-like format.
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

# run with < fileIn > fileOut, creates a PTB-like format: 
# (PRO_1_mod What)...
# where: (POS tag_sentence-position_dependency Word)

SEP="\t";
TAG="[^${SEP}]*";
SENTENCESEP="<SENTENCE123456789SEP>";

exec cat $1 | perl -pe "s/^(${TAG})${SEP}(${TAG})${SEP}${TAG}${SEP}${TAG}${SEP}${TAG}${SEP}${TAG}${SEP}${TAG}${SEP}${TAG}${SEP}${TAG}${SEP}(${TAG})${TAG}${SEP}${TAG}${SEP}${TAG}${SEP}${TAG}${SEP}${TAG}${SEP}${TAG}${SEP}${TAG}${SEP}${TAG}${SEP}(${TAG}).*$/\(\3_\1_\4 \2\)/g" | perl -pe "s/^\s*$/\n/g" | perl -pe "s/^$/${SENTENCESEP}/g" | perl -pe "s/\n/ /g" | perl -pe "s/ ${SENTENCESEP} /\n/g"
