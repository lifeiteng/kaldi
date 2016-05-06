#!/usr/bin/python
# -*- encoding: utf-8 -*-
__author__ = 'Feiteng'
import sys
import os
import logging
from optparse import OptionParser
# reload(sys)
# sys.setdefaultencoding("utf-8")


usage = '%prog [options] '
parser = OptionParser(usage)
parser.add_option('--xxoo', dest='xxoo', default=False)
(opt, argv) = parser.parse_args()

if len(argv) != 3:
    print parser.print_help()
    exit(-1)

print "DONE!"


