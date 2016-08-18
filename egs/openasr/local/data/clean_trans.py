#!/usr/bin/python
# -*- encoding: utf-8 -*-
__author__ = 'Feiteng'
import sys
import re
from optparse import OptionParser

reload(sys)
sys.setdefaultencoding("utf-8")

usage = '%prog --option value'
parser = OptionParser(usage)
parser.add_option('--lower', dest='lower', default=False)
parser.add_option('--clean-oov', dest='oov', default=False)

(opt, argv) = parser.parse_args()

to_lower = (opt.lower == 'True')
rm_oov = (opt.oov == 'True')

if rm_oov:
    assert len(argv) == 3
    # num_oov = 0
    oov_utt = 0;
    oov_words = set()
    print "dict text clean_text"
    zidian = dict()
    with open(argv[0]) as f:
        for line in f:
            zidian[line.split()[0]] = 1
    trans_lines = open(argv[1]).readlines()
    try:
        with open(argv[2], 'w') as tf:
            for line in trans_lines:
                line = line.strip()
                splits = line.split()
                ssp = ' '.join(splits[1:]).replace('-', ' ').split()
                splits = [splits[0]]
                splits.extend(ssp)

                has_oov = False
                for i in range(1, len(splits)):
                    if not zidian.has_key(splits[i].lower()):
                        oov_utt += 1
                        oov_words.add(splits[i].lower())
                        # print "OOV[%s] in [%s]" % (splits[i].lower(), ' '.join(splits[1:]).lower())
                        has_oov = True
                        break
                if not has_oov:
                    if to_lower:
                        print >> tf, splits[0], ' '.join(splits[1:]).lower()
                    else:
                        print >> tf, splits[0], ' '.join(splits[1:])
        print "%d utt has OOV!" % (oov_utt), oov_words, len(oov_words)
    except:
        with open(argv[1], 'w') as f:
            for line in trans_lines:
                print >>f, line.strip()
        print "Except occur!!!"
        exit(-1)

elif to_lower:
    lines = open(argv[0]).readlines()
    try:
        with open(argv[1], 'w') as tf:
            for line in lines:
                line = line.strip()
                splits = line.split()
                print >> tf, splits[0], ' '.join(splits[1:]).lower()
    except:
        with open(argv[1], 'w') as f:
            for line in lines:
                print >>f, line.strip()
        print "Except occur!!!"
        exit(-1)


