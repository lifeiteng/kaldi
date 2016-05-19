#!/usr/bin/python
# -*- encoding: utf-8 -*-
__author__ = 'Feiteng'
import sys
import os
import logging
from optparse import OptionParser

from parse_nnet import AmNnetSimple

if __name__ == '__main__':
    cmd_parser = OptionParser(
        usage="usage: %prog [options] <tdnn-text >pruned-tdnn-text")
    # cmd_parser.add_option('-V', '--verbose',
    #                       action="store", type="int", dest="V", default=0, help='Verbose level')
    # cmd_parser.add_option('--cer', action="store_true", dest="cer", help='Calculate Character Error Rate')

    cmd_parser.parse_args()
    (opts, argv) = cmd_parser.parse_args()

    if len(argv) != 2:
        print cmd_parser.print_help()
        exit(-1)

    am_nnet = AmNnetSimple()
    am_nnet.Read(open(argv[0]))
    am_nnet.Prune()
    am_nnet.Write(open(argv[1], 'w'))
