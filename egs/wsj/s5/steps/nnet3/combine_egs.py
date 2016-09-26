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
logger.info('Starting combine_egs.py')


def GetArgs():
    usage = '%prog egs-dir-1 egs-dir-2 egs-dir-3 combined-egs-dir'
    parser = OptionParser(usage)
    parser.add_option('-T', '--test', dest='test', action='store_true', default=False)
    parser.add_option('--sort', dest='sort', action='store_true', default=False)
    parser.add_option('--sort-reverse', dest='sort_reverse', action='store_true', default=False)
    parser.add_option('--random-seed', dest='seed', type=int, default=None)
    parser.add_option('--percent', dest='percent', type=str, default="")
    parser.add_option('-C', '--copy', dest='copy', action='store_true', default=False)
    (opt, args) = parser.parse_args()
    if len(args) < 2:
        parser.print_help()
        exit(-1)
    if opt.seed:
        random.seed(opt.seed)

    return [args, opt]

# args is a Namespace with the required parameters
def Combine(args, opt):
    logger.info("Combining egs")
    num_archives = []
    num_archives_choosed = []
    for egs_dir in args[:-1]:
        num_archive = len([ egs for egs in os.listdir(egs_dir) if egs.endswith('.ark')])
        assert num_archive > 0
        num_archives.append(num_archive)
        num_archives_choosed.append([random.random() for i in range(num_archive)])

    combine_egs_dir = args[-1]
    if not os.path.isdir(combine_egs_dir):
        os.mkdir(combine_egs_dir)
    combine_numbers = range(1, sum(num_archives) + 1)
    percents = None
    num_archives_keeped = [v for v in num_archives]
    if opt.percent:
        logger.info("Percent: %s" % (opt.percent))
        percents = [float(v) for v in opt.percent.split()]
        assert len(percents) == len(num_archives)
        assert len(percents) == len(num_archives_choosed)
        num_final_egs = 0
        for i in range(0, len(num_archives)):
            keep = sum([ v <= percents[i] for v in num_archives_choosed[i]])
            num_archives_keeped[i] = keep
            num_final_egs += keep

        combine_numbers = range(1, num_final_egs + 1)
        if len(combine_numbers) == 0:
            logger.error("bad percent %s" % (opt.percent))
            exit(-1)

    max_egs_num = combine_numbers[-1]
    logger.info("[ %s ] egs -> %d egs" % (' '.join([str(v) for v in num_archives_keeped]), max_egs_num))

    if (not opt.sort) and (not opt.sort_reverse):
        random.shuffle(combine_numbers)
    elif not opt.sort_reverse:
        combine_numbers.reverse()
    logger.info("[ %s ]" % (' '.join([str(v) for v in combine_numbers])))

    for e in range(0, len(args[:-1])):
        num_copy_mv = 0
        for i in range(1, num_archives[e] + 1):
            if percents:
                if num_archives_choosed[e][i-1] > percents[e]:
                    continue
            num_copy_mv += 1
            aidx = combine_numbers.pop()
            if not opt.test:
                logger.info("Move/Copy {0}/cegs.{1}.ark -> {2}/cegs.{3}.ark".format(args[e], i, combine_egs_dir, aidx))
            if args[e].find('combine') < 0 or opt.copy:
                if opt.test:
                    print("cp {0}/cegs.{1}.ark {2}/cegs.{3}.ark".format(args[e], i, combine_egs_dir, aidx))
                else:
                    shutil.copy("{0}/cegs.{1}.ark".format(args[e], i), "{0}/cegs.{1}.ark".format(combine_egs_dir, aidx))
            else:
                if opt.test:
                    print("mv {0}/cegs.{1}.ark {2}/cegs.{3}.ark".format(args[e], i, combine_egs_dir, aidx))
                else:
                    shutil.move("{0}/cegs.{1}.ark".format(args[e], i), "{0}/cegs.{1}.ark".format(combine_egs_dir, aidx))
        logger.info("[ Origin %d == Copy/Mv %d ]" % (num_archives_keeped[e], num_copy_mv))
        assert num_copy_mv == num_archives_keeped[e]

    if len(combine_numbers) != 0:
        logger.info("\nNot Empty!!! : [ %s ]" % ' '.join([str(v) for v in combine_numbers]))
        exit(-1)
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
        print >>f, max_egs_num
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
