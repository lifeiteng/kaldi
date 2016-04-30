#!/usr/bin/python
# -*- encoding: utf-8 -*-
__author__ = 'Feiteng'
import sys
import os
import re
from optparse import OptionParser

reload(sys)
sys.setdefaultencoding("utf-8")

usage = '%prog --option in-wav-scp out-wav-scp'
parser = OptionParser(usage)


(opt, argv) = parser.parse_args()

if len(argv) != 2:
    print parser.print_help()
    exit(-1)

in_wav_scp_lines = open(argv[0]).readlines()

try:
    with open(argv[1], 'w') as f:
        for line in in_wav_scp_lines:
            line = line.strip()
            wav_file = line.split()[-1]
            if os.stat(wav_file).st_size > 200:
                print >>f, line
            else:
                print "Bad wav file:", wav_file

except Exception, e:
    print sys.exc_info()[0]
    print "Exception write back to", argv[0]
    with open(argv[0], 'w') as f:
        for line in in_wav_scp_lines:
            print >>f, line.strip()




