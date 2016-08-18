#!/usr/bin/env python


# Copyright 2016 Feiteng
# Apache 2.0.

import argparse
import sys
import logging
import traceback
import shutil
import os
import random
from optparse import OptionParser


logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)
handler = logging.StreamHandler()
handler.setLevel(logging.INFO)
formatter = logging.Formatter('%(asctime)s [%(filename)s:%(lineno)s - %(funcName)s - %(levelname)s ] %(message)s')
handler.setFormatter(formatter)
logger.addHandler(handler)
logger.info('Starting chain train_get_egs.py')


def GetArgs():
    usage = '%prog egs-dir-1 egs-dir-2 egs-dir-3 combined-egs-dir'
    parser = OptionParser(usage)
    parser.add_option('--random', dest='random', action='store_false', default=True)
    parser.add_option('-C', '--copy', dest='copy', action='store_true', default=False)
    (opt, args) = parser.parse_args()
    assert len(args) >= 2
    return [args, opt]

# args is a Namespace with the required parameters
def Combine(args, opt):
    logger.info("Combining egs")
    num_archives = []
    for egs_dir in args[:-1]:
        num_archive = len([ egs for egs in os.listdir(egs_dir) if egs.endswith('.ark')])
        assert num_archive > 0
        num_archives.append(num_archive)
    combine_egs_dir = args[-1]
    if not os.path.isdir(combine_egs_dir):
        os.mkdir(combine_egs_dir)
    logger.info("[ %s ] egs -> %d egs" % (' '.join([ str(v) for v in num_archives]), sum(num_archives)))
    combine_numbers = range(1, sum(num_archives) + 1)
    if opt.random:
        random.shuffle(combine_numbers)
    for e in range(0, len(args[:-1])):
        for i in range(1, num_archives[e] + 1):
            aidx = random.choice(combine_numbers)
            combine_numbers.remove(aidx)
            if args[e].find('combine') < 0 or opt.copy:
                shutil.copy("{0}/cegs.{1}.ark".format(args[e], i), "{0}/cegs.{1}.ark".format(combine_egs_dir, aidx))
            else:
                shutil.move("{0}/cegs.{1}.ark".format(args[e], i), "{0}/cegs.{1}.ark".format(combine_egs_dir, aidx))
    assert len(combine_numbers) == 0
    for egs in ['combine.cegs', 'train_diagnostic.cegs', 'valid_diagnostic.cegs']:
        if os.path.isfile(os.path.join(combine_egs_dir, egs)):
            os.remove(os.path.join(combine_egs_dir, egs))
        with open(os.path.join(combine_egs_dir, egs), 'a') as f:
            for egs_dir in args[:-1]:
                f.write(open(os.path.join(egs_dir, egs)).read())
    if os.path.isdir(os.path.join(combine_egs_dir, 'info')):
        shutil.rmtree(os.path.join(combine_egs_dir, 'info'))
    shutil.copytree(os.path.join(args[0], 'info'), os.path.join(combine_egs_dir, 'info'))
    with open(os.path.join(combine_egs_dir, 'info/num_archives'), 'w') as f:
        print >>f, sum(num_archives)
    open(os.path.join(combine_egs_dir, '.done'), 'a').close()


def Main():
    [args, opt] = GetArgs()
    try:
        Combine(args, opt)
    except Exception as e:
        traceback.print_exc()
        raise e

if __name__ == "__main__":
    Main()
