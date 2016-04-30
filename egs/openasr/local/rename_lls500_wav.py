#!/usr/bin/python
# -*- encoding: utf-8 -*-
__author__ = 'Feiteng'
import sys
import os
import logging
import shutil
from optparse import OptionParser
# reload(sys)
# sys.setdefaultencoding("utf-8")


usage = '%prog [options] '
parser = OptionParser(usage)
parser.add_option('--xxoo', dest='xxoo', default=False)
(opt, argv) = parser.parse_args()

if len(argv) != 2:
    print parser.print_help()
    exit(-1)

in_wav_lines = open(argv[0]).readlines()
with open(argv[1], 'w') as f:
    for line in in_wav_lines:
        line = line.strip().replace('//', '/')
        (key, wav_file) = line.split()
        splits = wav_file.split('/')
        new_name = '_'.join(splits[-2:])
        splits[-1] = new_name
        new_wavfile = '/'.join(splits)
        shutil.move(wav_file, new_wavfile)
        print >>f, key, new_wavfile

print "DONE!"


